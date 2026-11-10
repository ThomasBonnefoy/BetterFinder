import AppKit
import BetterFinderCore
import Observation

extension VolumeStore {
    /// Mounted volumes, minus the ones already listed as network drives.
    func volumes(besides driveMonitor: DriveMonitor) -> [VolumeInfo] {
        let driveRoots = Set(driveMonitor.volumeRoots.values.map(\.path))
        return volumes.filter { !driveRoots.contains($0.url.path) }
    }
}

extension VolumeInfo {
    /// SF Symbol that stands for the volume.
    var symbolName: String {
        if !isLocal { return "externaldrive.connected.to.line.below" }
        return isEjectable ? "externaldrive" : "internaldrive"
    }
}

/// Mounted volumes, kept up to date as disks are plugged in or ejected.
@MainActor
@Observable
final class VolumeStore {
    private(set) var volumes: [VolumeInfo] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            observers.append(observer)
        }
        refresh()
    }

    func refresh() {
        // Listing volumes touches every mount point: keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = VolumeLister.list()
            Task { @MainActor in self?.volumes = list }
        }
    }
}
