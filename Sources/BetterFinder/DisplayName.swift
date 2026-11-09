import Foundation

enum DisplayName {
    /// Name of a folder as macOS shows it ("Bureau" for ~/Desktop,
    /// "Macintosh HD" for /).
    ///
    /// Only the startup disk is asked for localized names: other volumes may
    /// be network shares, where a disk access on the main thread could stall.
    static func of(_ url: URL) -> String {
        let path = url.path
        if path.hasPrefix("/Volumes/") {
            return url.lastPathComponent
        }
        return FileManager.default.displayName(atPath: path)
    }
}
