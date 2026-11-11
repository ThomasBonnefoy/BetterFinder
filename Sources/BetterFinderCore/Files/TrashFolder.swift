import Foundation

/// The user's Trash (`~/.Trash`).
///
/// macOS keeps it behind a privacy protection: an app can put files in it,
/// but can only read it once the user has given it "Full Disk Access".
public enum TrashFolder {
    /// Folder of the Trash, in the standardized spelling of the other URLs.
    public static var url: URL {
        let files = FileManager.default
        let trash = files.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? files.homeDirectoryForCurrentUser.appending(path: ".Trash", directoryHint: .isDirectory)
        return URL(filePath: trash.standardizedFileURL.path, directoryHint: .notDirectory)
    }

    /// True when `folder` is the Trash itself.
    public static func isTrash(_ folder: URL, trash: URL = url) -> Bool {
        folder.standardizedFileURL.path == trash.standardizedFileURL.path
    }

    /// True when `item` is the Trash or lies inside it.
    public static func contains(_ item: URL, trash: URL = url) -> Bool {
        let path = item.standardizedFileURL.path
        let root = trash.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    /// What there is to delete to empty the Trash, or an error when it cannot
    /// be read (see `isPermissionDenied`). The `.DS_Store` file the Finder
    /// keeps there is not counted.
    public static func contents(of trash: URL = url) async throws -> [URL] {
        let listing = try await DirectoryLoader.load(trash)
        return listing.items.map(\.url).filter { $0.lastPathComponent != ".DS_Store" }
    }

    /// True when `error` says the app is not allowed to read or change
    /// something, as opposed to the thing being missing or broken.
    public static func isPermissionDenied(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                if nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
                    return true
                }
            case NSPOSIXErrorDomain:
                if nsError.code == Int(EPERM) || nsError.code == Int(EACCES) { return true }
            default:
                break
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
