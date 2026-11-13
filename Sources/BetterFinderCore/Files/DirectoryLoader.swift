import Foundation

/// The content of one directory, as read from disk.
public struct DirectoryListing: Sendable {
    public let url: URL
    /// Every entry, hidden ones included, in no particular order.
    public let items: [FileItem]
    /// False for network shares, where per-file disk access must stay rare.
    public let isLocalVolume: Bool
}

/// Reads directories away from the main thread.
///
/// The work runs on a concurrent GCD queue rather than on Swift's cooperative
/// pool: a listing on a network share whose VPN just dropped can block for a
/// long time, and it must not starve the rest of the app.
public enum DirectoryLoader {
    private static let queue = DispatchQueue(
        label: "betterfinder.directory-loader",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static let itemKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey,
        .localizedNameKey, .localizedTypeDescriptionKey,
    ]

    public static func load(_ url: URL) async throws -> DirectoryListing {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try loadSync(url) })
            }
        }
    }

    /// Blocking variant of `load`. Never call it from the main thread.
    public static func loadSync(_ url: URL) throws -> DirectoryListing {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(itemKeys),
            options: []
        )
        let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true
        return DirectoryListing(url: url, items: urls.map(makeItem), isLocalVolume: isLocal)
    }

    static func makeItem(_ url: URL) -> FileItem {
        let values = try? url.resourceValues(forKeys: itemKeys)
        var isDirectory = values?.isDirectory ?? false
        if values?.isSymbolicLink == true {
            // Resource values describe the link itself: look at its target so
            // that a link to a folder can be browsed like a folder.
            let target = url.resolvingSymlinksInPath()
            isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        }
        let isPackage = values?.isPackage ?? false
        let name: String
        if isDirectory, !isPackage, let localized = values?.localizedName {
            name = localized
        } else {
            name = url.lastPathComponent
        }
        return FileItem(
            url: url,
            name: name,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isHidden: values?.isHidden ?? false,
            size: isDirectory ? nil : values?.fileSize.map(Int64.init),
            modificationDate: values?.contentModificationDate,
            kind: values?.localizedTypeDescription ?? ""
        )
    }
}
