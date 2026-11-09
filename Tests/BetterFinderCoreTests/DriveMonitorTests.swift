import Foundation
import Testing
@testable import BetterFinderCore

/// A pretend network: which servers answer, and what is mounted.
final class FakeNetwork: @unchecked Sendable {
    private let lock = NSLock()
    private var reachableHosts: Set<String> = []
    private var entries: [MountEntry] = []
    private var nextMountError: MountError?
    private var mounts: [(drive: NetworkDrive, allowUI: Bool)] = []
    private var unmounts: [(path: String, force: Bool)] = []

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func setReachable(_ host: String, _ reachable: Bool) {
        locked { _ = reachable ? reachableHosts.insert(host).inserted : (reachableHosts.remove(host) != nil) }
    }

    func isReachable(_ host: String) -> Bool { locked { reachableHosts.contains(host) } }
    var mountTable: [MountEntry] { locked { entries } }
    var mountCalls: [(drive: NetworkDrive, allowUI: Bool)] { locked { mounts } }
    var unmountCalls: [(path: String, force: Bool)] { locked { unmounts } }
    func failNextMount(with error: MountError) { locked { nextMountError = error } }

    func mount(_ drive: NetworkDrive, allowUI: Bool) throws -> URL {
        try locked {
            mounts.append((drive, allowUI))
            if let error = nextMountError {
                nextMountError = nil
                throw error
            }
            guard reachableHosts.contains(drive.host) else { throw MountError.serverUnreachable }
            let mountPoint = "/Volumes/" + NetworkDrive.suggestedName(for: drive.url)
            entries.append(MountEntry(
                source: "//someone@\(drive.host)/\(drive.sharePath)",
                mountPoint: mountPoint,
                fileSystem: "smbfs"
            ))
            return URL(filePath: mountPoint, directoryHint: .isDirectory)
        }
    }

    func unmount(_ mountPoint: URL, force: Bool) {
        locked {
            unmounts.append((mountPoint.path, force))
            entries.removeAll { $0.mountPoint == mountPoint.path }
        }
    }
}

struct FakeProbe: ReachabilityProbing {
    let network: FakeNetwork
    func isReachable(host: String, port: Int) async -> Bool { network.isReachable(host) }
}

struct FakeMounter: DriveMounting {
    let network: FakeNetwork
    func mount(_ drive: NetworkDrive, allowUI: Bool) async throws -> URL {
        try network.mount(drive, allowUI: allowUI)
    }
    func unmount(_ mountPoint: URL, force: Bool) async throws {
        network.unmount(mountPoint, force: force)
    }
}

@MainActor
@Suite struct DriveMonitorTests {
    private let network = FakeNetwork()
    private let storeFile = FileManager.default.temporaryDirectory
        .appending(path: "BetterFinderMonitorTests-\(UUID().uuidString)/drives.json")

    private func makeMonitor() -> DriveMonitor {
        let network = self.network
        return DriveMonitor(
            store: NetworkDriveStore(fileURL: storeFile),
            probe: FakeProbe(network: network),
            mounter: FakeMounter(network: network),
            mountTable: { network.mountTable }
        )
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: storeFile.deletingLastPathComponent())
    }

    private func drive(_ share: String = "commun", auto: Bool = false) -> NetworkDrive {
        NetworkDrive(name: share.capitalized, url: URL(string: "smb://nas/\(share)")!, reconnectAutomatically: auto)
    }

    // MARK: - The reason this app exists

    @Test func aDriveStaysListedWhenItsServerIsUnreachable() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)

        await monitor.refresh()

        #expect(monitor.drives == [commun])
        #expect(monitor.status(of: commun.id) == .offline)
    }

    @Test func statusFollowsTheVPNGoingUpAndDown() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)

        await monitor.refresh()
        #expect(monitor.status(of: commun.id) == .offline)

        network.setReachable("nas", true)          // VPN connected
        await monitor.refresh()
        #expect(monitor.status(of: commun.id) == .available)

        let folder = await monitor.connect(commun.id)
        #expect(folder?.path == "/Volumes/commun")
        #expect(monitor.status(of: commun.id) == .mounted(URL(filePath: "/Volumes/commun", directoryHint: .isDirectory)))

        network.setReachable("nas", false)         // VPN dropped, mount is stale
        await monitor.refresh()
        #expect(monitor.status(of: commun.id) == .offline)
        #expect(monitor.drives == [commun])
        #expect(monitor.volumeRoots[commun.id]?.path == "/Volumes/commun")

        network.setReachable("nas", true)          // VPN back
        await monitor.refresh()
        #expect(monitor.status(of: commun.id) == .mounted(URL(filePath: "/Volumes/commun", directoryHint: .isDirectory)))
    }

    // MARK: - Status

    @Test func resolveCoversEveryCase() {
        let folder = URL(filePath: "/Volumes/x")
        #expect(DriveStatus.resolve(folder: nil, isReachable: false) == .offline)
        #expect(DriveStatus.resolve(folder: folder, isReachable: false) == .offline)
        #expect(DriveStatus.resolve(folder: nil, isReachable: true) == .available)
        #expect(DriveStatus.resolve(folder: folder, isReachable: true) == .mounted(folder))
    }

    @Test func findsTheDriveThatContainsAFolder() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)
        network.setReachable("nas", true)
        await monitor.connect(commun.id)

        #expect(monitor.drive(containing: URL(filePath: "/Volumes/commun")) == commun)
        #expect(monitor.drive(containing: URL(filePath: "/Volumes/commun/Sub/Folder")) == commun)
        #expect(monitor.drive(containing: URL(filePath: "/Volumes/commun2")) == nil)
        #expect(monitor.drive(containing: URL(filePath: "/Users/someone")) == nil)
    }

    // MARK: - Connecting

    @Test func failedConnectionKeepsTheReason() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)
        network.setReachable("nas", true)
        network.failNextMount(with: .authenticationFailed)

        let folder = await monitor.connect(commun.id)

        #expect(folder == nil)
        #expect(monitor.lastErrors[commun.id] == .authenticationFailed)
        #expect(monitor.status(of: commun.id) == .available)
    }

    @Test func cancellingTheLoginWindowIsNotAnError() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)
        network.setReachable("nas", true)
        network.failNextMount(with: .cancelled)

        await monitor.connect(commun.id)

        #expect(monitor.lastErrors[commun.id] == nil)
        #expect(monitor.status(of: commun.id) == .available)
    }

    @Test func aStaleMountIsForceUnmounted() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)
        network.setReachable("nas", true)
        await monitor.connect(commun.id)
        network.setReachable("nas", false)
        await monitor.refresh()

        await monitor.disconnect(commun.id)

        #expect(network.unmountCalls.count == 1)
        #expect(network.unmountCalls.first?.path == "/Volumes/commun")
        #expect(network.unmountCalls.first?.force == true)
        #expect(monitor.volumeRoots[commun.id] == nil)
        #expect(monitor.status(of: commun.id) == .offline)
    }

    @Test func aLiveMountIsUnmountedCleanly() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)
        network.setReachable("nas", true)
        await monitor.connect(commun.id)

        await monitor.disconnect(commun.id)

        #expect(network.unmountCalls.first?.force == false)
        #expect(monitor.status(of: commun.id) == .available)
    }

    // MARK: - Automatic reconnection

    @Test func reconnectsByItselfWhenTheServerComesBack() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive(auto: true)
        monitor.add(commun)

        await monitor.refresh()
        #expect(network.mountCalls.isEmpty)

        network.setReachable("nas", true)
        await monitor.refresh()

        #expect(network.mountCalls.count == 1)
        #expect(network.mountCalls.first?.allowUI == false)
        #expect(monitor.status(of: commun.id) == .mounted(URL(filePath: "/Volumes/commun", directoryHint: .isDirectory)))
    }

    @Test func doesNotReconnectWithoutTheOption() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive(auto: false)
        monitor.add(commun)
        network.setReachable("nas", true)

        await monitor.refresh()

        #expect(network.mountCalls.isEmpty)
        #expect(monitor.status(of: commun.id) == .available)
    }

    @Test func aFailedSilentReconnectionIsTriedOnlyOncePerReturn() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive(auto: true)
        monitor.add(commun)
        network.setReachable("nas", true)
        network.failNextMount(with: .authenticationFailed)

        await monitor.refresh()
        await monitor.refresh()
        await monitor.refresh()

        #expect(network.mountCalls.count == 1)
        #expect(monitor.lastErrors[commun.id] == nil)   // silent attempt: no error shown
        #expect(monitor.status(of: commun.id) == .available)

        network.setReachable("nas", false)              // server goes away…
        await monitor.refresh()
        network.setReachable("nas", true)               // …and comes back: one new attempt
        await monitor.refresh()
        #expect(network.mountCalls.count == 2)
    }

    @Test func aDriveDisconnectedByHandIsNotRemountedRightAway() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive(auto: true)
        monitor.add(commun)
        network.setReachable("nas", true)
        await monitor.refresh()
        #expect(network.mountCalls.count == 1)

        await monitor.disconnect(commun.id)
        await monitor.refresh()

        #expect(network.mountCalls.count == 1)
        #expect(monitor.status(of: commun.id) == .available)
    }

    // MARK: - The list

    @Test func theListSurvivesARestart() async {
        defer { cleanUp() }
        let first = makeMonitor()
        let commun = drive()
        let perso = drive("perso", auto: true)
        first.add(commun)
        first.add(perso)

        let second = makeMonitor()
        second.loadDrives()

        #expect(second.drives == [commun, perso])
        #expect(second.status(of: commun.id) == .unknown)
        #expect(second.storageError == nil)
    }

    @Test func removingADriveForgetsIt() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        let commun = drive()
        monitor.add(commun)
        monitor.remove(commun.id)

        #expect(monitor.drives.isEmpty)
        let reloaded = makeMonitor()
        reloaded.loadDrives()
        #expect(reloaded.drives.isEmpty)
    }

    @Test func changingTheAddressResetsTheStatus() async {
        defer { cleanUp() }
        let monitor = makeMonitor()
        var commun = drive()
        monitor.add(commun)
        network.setReachable("nas", true)
        await monitor.connect(commun.id)

        commun.url = URL(string: "smb://other/share")!
        commun.name = "Autre"
        monitor.update(commun)

        #expect(monitor.drives == [commun])
        #expect(monitor.status(of: commun.id) == .unknown)
        #expect(monitor.volumeRoots[commun.id] == nil)

        await monitor.refresh()
        #expect(monitor.status(of: commun.id) == .offline)
    }
}
