import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

/// A pretend server whose share is "mounted" on a real temporary folder, so
/// that the window model can list it.
private final class FakeShare: @unchecked Sendable {
    private let lock = NSLock()
    private var reachable = false
    private var mounted = false
    let host = "nas"
    let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    var isReachable: Bool {
        get { lock.withLock { reachable } }
        set { lock.withLock { reachable = newValue } }
    }

    var isMounted: Bool {
        get { lock.withLock { mounted } }
        set { lock.withLock { mounted = newValue } }
    }

    var entries: [MountEntry] {
        isMounted ? [MountEntry(source: "//someone@nas/commun", mountPoint: folder.path, fileSystem: "smbfs")] : []
    }
}

private struct ShareProbe: ReachabilityProbing {
    let share: FakeShare
    func isReachable(host: String, port: Int) async -> Bool { host == share.host && share.isReachable }
}

private struct ShareMounter: DriveMounting {
    let share: FakeShare
    func mount(_ drive: NetworkDrive, allowUI: Bool) async throws -> URL {
        guard share.isReachable else { throw MountError.serverUnreachable }
        share.isMounted = true
        return share.folder
    }
    func unmount(_ mountPoint: URL, force: Bool) async throws {
        share.isMounted = false
    }
}

@MainActor
@Suite struct BrowserModelDriveTests {
    private let root: URL
    private let share: FakeShare
    private let monitor: DriveMonitor
    private let drive = NetworkDrive(name: "Commun", url: URL(string: "smb://nas/commun")!)

    init() throws {
        let files = FileManager.default
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderDriveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base.appending(path: "share/Projets"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base.appending(path: "share/rapport.txt"))
        root = BrowserModel.normalized(base)

        let share = FakeShare(folder: BrowserModel.normalized(base.appending(path: "share")))
        self.share = share
        monitor = DriveMonitor(
            store: NetworkDriveStore(fileURL: base.appending(path: "drives.json")),
            probe: ShareProbe(share: share),
            mounter: ShareMounter(share: share),
            mountTable: { share.entries }
        )
        monitor.add(drive)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    private func settled(_ model: BrowserModel) async throws {
        // Lets the tasks started by the model (refresh, connect, load) finish.
        for _ in 0..<500 {
            try await Task.sleep(for: .milliseconds(10))
            if model.state != .loading, monitor.status(of: drive.id) != .connecting, monitor.status(of: drive.id) != .unknown {
                return
            }
        }
        Issue.record("The model did not settle")
    }

    private func startedModel() async throws -> BrowserModel {
        let model = BrowserModel(start: root)
        model.attach(monitor)
        model.start()
        try await settled(model)
        return model
    }

    @Test func anOfflineDriveOpensItsPageInsteadOfAList() async throws {
        defer { cleanUp() }
        let model = try await startedModel()

        model.openDrive(drive.id)
        try await settled(model)

        #expect(model.location == .drive(drive.id))
        #expect(model.displayedDriveID == drive.id)
        #expect(model.currentURL == nil)
        #expect(model.items.isEmpty)
        #expect(model.title == "Commun")
        #expect(monitor.status(of: drive.id) == .offline)
        #expect(model.canGoBack)
    }

    @Test func clickingAReachableDriveConnectsItAndShowsItsContent() async throws {
        defer { cleanUp() }
        let model = try await startedModel()
        share.isReachable = true

        model.openDrive(drive.id)
        try await settled(model)

        #expect(model.location == .folder(share.folder))
        #expect(model.displayedDriveID == nil)
        #expect(model.items.map(\.name) == ["Projets", "rapport.txt"])
        #expect(model.title == "Commun")

        model.goBack()
        try await settled(model)
        #expect(model.currentURL == root)
    }

    @Test func theDrivePageTurnsIntoTheContentWhenTheDriveComesBack() async throws {
        defer { cleanUp() }
        let model = try await startedModel()
        model.openDrive(drive.id)
        try await settled(model)
        #expect(model.location == .drive(drive.id))

        // The VPN comes up and the drive gets mounted (here: by hand).
        share.isReachable = true
        await monitor.refresh()
        await monitor.connect(drive.id)
        model.driveStatusesChanged()
        try await settled(model)

        #expect(model.location == .folder(share.folder))
        #expect(model.items.map(\.name) == ["Projets", "rapport.txt"])
    }

    @Test func aFolderOnADriveThatGoesOfflineIsReplacedByTheDrivePage() async throws {
        defer { cleanUp() }
        let model = try await startedModel()
        share.isReachable = true
        model.openDrive(drive.id)
        try await settled(model)
        let projets = share.folder.appending(path: "Projets")
        model.navigate(to: projets)
        try await settled(model)
        #expect(model.displayedDriveID == nil)

        share.isReachable = false                  // the VPN drops
        await monitor.refresh()
        model.driveStatusesChanged()

        #expect(model.displayedDriveID == drive.id)
        #expect(model.blockedDrive == drive.id)
        #expect(model.items.isEmpty)
        #expect(model.location == .folder(projets))     // the place is remembered

        share.isReachable = true                   // the VPN is back
        await monitor.refresh()
        model.driveStatusesChanged()
        try await settled(model)

        #expect(model.displayedDriveID == nil)
        #expect(model.currentURL == projets)
        #expect(model.state == .loaded)
    }

    @Test func typingAKnownShareAddressOpensTheDrive() async throws {
        defer { cleanUp() }
        let model = try await startedModel()

        #expect(model.submitAddress(#"\\NAS\Commun"#))
        try await settled(model)

        #expect(model.location == .drive(drive.id))
        #expect(model.driveEditor == nil)
    }

    @Test func typingAnUnknownShareAddressOffersToAddIt() async throws {
        defer { cleanUp() }
        let model = try await startedModel()

        #expect(model.submitAddress("smb://autre/partage"))

        #expect(model.driveEditor?.address == "smb://autre/partage")
        #expect(model.driveEditor?.existing == nil)
        #expect(model.currentURL == root)

        #expect(!model.submitAddress("smb://serveur-sans-partage"))
    }
}
