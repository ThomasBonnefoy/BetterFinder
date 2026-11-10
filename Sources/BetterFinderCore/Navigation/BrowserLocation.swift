import Foundation

/// What a browser window can show.
public enum BrowserLocation: Hashable, Sendable {
    /// The content of a folder.
    case folder(URL)
    /// The page of a network drive that cannot be browsed right now
    /// (offline, or not connected yet).
    case drive(UUID)
    /// The overview of the computer: main folders, disks and network drives
    /// ("This PC" in Explorer).
    case computer
}

extension BrowserLocation {
    /// True for the top folder of a disk or of a share: the startup disk, or
    /// anything mounted in /Volumes. Going up from there leads to the
    /// computer's overview, as in Explorer.
    public static func isVolumeRoot(_ url: URL) -> Bool {
        let parts = url.pathComponents
        return parts == ["/"] || (parts.count == 3 && parts[1] == "Volumes")
    }
}
