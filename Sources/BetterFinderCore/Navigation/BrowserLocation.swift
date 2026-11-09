import Foundation

/// What a browser window can show.
public enum BrowserLocation: Hashable, Sendable {
    /// The content of a folder.
    case folder(URL)
    /// The page of a network drive that cannot be browsed right now
    /// (offline, or not connected yet).
    case drive(UUID)
}
