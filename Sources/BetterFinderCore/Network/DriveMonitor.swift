import Foundation
import Network
import Observation

/// What the sidebar shows next to a network drive.
public enum DriveStatus: Equatable, Sendable {
    /// Not checked yet.
    case unknown
    /// Mounted and its server answers: ready to browse.
    case mounted(URL)
    /// The server answers but the share is not mounted.
    case available
    /// The server does not answer (typically: the VPN is off).
    case offline
    /// A mount is in progress.
    case connecting

    /// A mounted share whose server no longer answers counts as offline:
    /// browsing it would only stall.
    public static func resolve(folder: URL?, isReachable: Bool) -> DriveStatus {
        guard isReachable else { return .offline }
        if let folder { return .mounted(folder) }
        return .available
    }
}

/// Keeps the list of network drives and their live status.
///
/// The list comes from a file, not from what is currently mounted: a drive
/// stays in the sidebar when its server is unreachable. Status checks never
/// touch a mounted volume (a dead network mount would block), they only read
/// the kernel's mount table and probe the server over TCP.
@MainActor
@Observable
public final class DriveMonitor {
    public private(set) var drives: [NetworkDrive] = []
    public private(set) var statuses: [UUID: DriveStatus] = [:]
    /// Volume root of each mounted drive, kept while the drive is offline so
    /// that a stale mount can still be recognized and disconnected.
    public private(set) var volumeRoots: [UUID: URL] = [:]
    /// Why the last connection or disconnection asked by the user failed.
    public private(set) var lastErrors: [UUID: MountError] = [:]
    /// Set when the drive list could not be read or saved.
    public private(set) var storageError: String?

    @ObservationIgnored private let store: NetworkDriveStore
    @ObservationIgnored private let probe: any ReachabilityProbing
    @ObservationIgnored private let mounter: any DriveMounting
    @ObservationIgnored private let mountTable: @Sendable () -> [MountEntry]

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledRefresh: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var connecting: Set<UUID> = []
    /// Drives that must not be mounted automatically until they have gone
    /// offline again: already tried, or disconnected by the user.
    @ObservationIgnored private var autoReconnectBlocked: Set<UUID> = []

    public init(
        store: NetworkDriveStore = NetworkDriveStore(),
        probe: any ReachabilityProbing = TCPReachabilityProbe(),
        mounter: any DriveMounting = NetFSMountService(),
        mountTable: @escaping @Sendable () -> [MountEntry] = { MountTable.current() }
    ) {
        self.store = store
        self.probe = probe
        self.mounter = mounter
        self.mountTable = mountTable
    }

    // MARK: - Lifecycle

    /// Loads the saved drives. Safe to call more than once.
    public func loadDrives() {
        do {
            drives = try store.load()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
        for drive in drives where statuses[drive.id] == nil {
            statuses[drive.id] = .unknown
        }
    }

    /// Loads the drives and keeps their status fresh: on every network
    /// change (a VPN going up or down is one) and on a slow timer.
    public func start(refreshInterval: Duration = .seconds(30)) {
        guard !hasStarted else { return }
        hasStarted = true
        loadDrives()

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        monitor.start(queue: DispatchQueue(label: "betterfinder.network-path"))
        pathMonitor = monitor

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        timerTask?.cancel()
        timerTask = nil
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        hasStarted = false
    }

    // MARK: - Queries

    public func drive(_ id: UUID) -> NetworkDrive? {
        drives.first { $0.id == id }
    }

    public func status(of id: UUID) -> DriveStatus {
        statuses[id] ?? .unknown
    }

    /// The drive whose mounted volume contains this folder, if any.
    public func drive(containing url: URL) -> NetworkDrive? {
        let path = url.path
        return drives.first { drive in
            guard let root = volumeRoots[drive.id]?.path else { return false }
            return path == root || path.hasPrefix(root + "/")
        }
    }

    // MARK: - Editing the list

    public func add(_ drive: NetworkDrive) {
        drives.append(drive)
        statuses[drive.id] = .unknown
        persist()
        scheduleRefresh()
    }

    public func update(_ drive: NetworkDrive) {
        guard let index = drives.firstIndex(where: { $0.id == drive.id }) else { return }
        let addressChanged = drives[index].url != drive.url
        drives[index] = drive
        if addressChanged {
            statuses[drive.id] = .unknown
            volumeRoots[drive.id] = nil
            lastErrors[drive.id] = nil
        }
        persist()
        scheduleRefresh()
    }

    /// Forgets a drive. A mounted share stays mounted.
    public func remove(_ id: UUID) {
        drives.removeAll { $0.id == id }
        statuses[id] = nil
        volumeRoots[id] = nil
        lastErrors[id] = nil
        autoReconnectBlocked.remove(id)
        persist()
    }

    private func persist() {
        do {
            try store.save(drives)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    // MARK: - Status

    /// Checks again shortly, and once more a few seconds later: after a VPN
    /// connects, names and routes can take a moment to work.
    public func scheduleRefresh() {
        scheduledRefresh?.cancel()
        scheduledRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh()
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Probes every server and reads the mount table, then updates statuses.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let probe = self.probe
        let targets = drives.map { (id: $0.id, host: $0.host, port: $0.port) }

        let reachable = await withTaskGroup(of: (UUID, Bool).self) { group in
            for target in targets {
                group.addTask {
                    (target.id, await probe.isReachable(host: target.host, port: target.port))
                }
            }
            var results: [UUID: Bool] = [:]
            for await (id, isReachable) in group {
                results[id] = isReachable
            }
            return results
        }
        // A newer refresh started meanwhile: let it have the last word.
        guard generation == refreshGeneration else { return }

        let entries = mountTable()
        for drive in drives {
            guard let isReachable = reachable[drive.id] else { continue }
            let match = MountTable.match(for: drive, in: entries)
            if volumeRoots[drive.id] != match?.volume {
                volumeRoots[drive.id] = match?.volume
            }
            guard !connecting.contains(drive.id) else { continue }

            let status = DriveStatus.resolve(folder: match?.folder, isReachable: isReachable)
            if status == .offline {
                autoReconnectBlocked.remove(drive.id)
            }
            if statuses[drive.id] != status {
                statuses[drive.id] = status
            }
        }

        await reconnectAutomatically()
    }

    private func reconnectAutomatically() async {
        let candidates = drives.filter { drive in
            drive.reconnectAutomatically
                && statuses[drive.id] == .available
                && !autoReconnectBlocked.contains(drive.id)
        }
        for drive in candidates {
            // One silent attempt per time the server comes back.
            autoReconnectBlocked.insert(drive.id)
            await connect(drive.id, allowUI: false)
        }
    }

    // MARK: - Connecting

    /// Mounts a drive. Returns the folder to open, or `nil` on failure (the
    /// reason is then in `lastErrors`, except when the user cancelled).
    @discardableResult
    public func connect(_ id: UUID, allowUI: Bool = true) async -> URL? {
        guard let drive = drive(id) else { return nil }
        if case .mounted(let folder) = statuses[id] { return folder }
        guard !connecting.contains(id) else { return nil }

        connecting.insert(id)
        statuses[id] = .connecting
        lastErrors[id] = nil
        if allowUI {
            autoReconnectBlocked.remove(id)
        }

        do {
            let mountPoint = try await mounter.mount(drive, allowUI: allowUI)
            connecting.remove(id)
            // Read the table rather than trusting the path blindly: it also
            // gives the volume root when the drive points inside a share.
            let match = MountTable.match(for: drive, in: mountTable())
            let folder = match?.folder ?? mountPoint
            volumeRoots[id] = match?.volume ?? mountPoint
            statuses[id] = .mounted(folder)
            return folder
        } catch {
            connecting.remove(id)
            statuses[id] = .unknown
            if allowUI, let mountError = error as? MountError, mountError != .cancelled {
                lastErrors[id] = mountError
            }
            await refresh()
            return nil
        }
    }

    /// Unmounts a drive. A drive whose server is gone is force-unmounted,
    /// since a clean unmount would wait for the server.
    public func disconnect(_ id: UUID) async {
        guard let volume = volumeRoots[id] else { return }
        let force = statuses[id] == .offline
        // Do not mount it again behind the user's back while the server
        // stays reachable. The block is lifted once the drive goes offline.
        autoReconnectBlocked.insert(id)
        lastErrors[id] = nil
        do {
            try await mounter.unmount(volume, force: force)
        } catch {
            lastErrors[id] = error as? MountError ?? .other(code: -1)
        }
        await refresh()
    }
}
