import Foundation

/// What the file system says about one item, for the Properties window.
public struct ItemInfo: Equatable, Sendable {
    /// Name on disk (folders are not translated here).
    public let name: String
    public let url: URL
    public let kind: String
    /// A folder that is browsed, as opposed to a file or a bundle.
    public let isFolder: Bool
    public let isHidden: Bool
    public let isReadOnly: Bool
    /// Size of a file in bytes; `nil` for folders and bundles, which need
    /// `FolderSize`.
    public let fileSize: Int64?
    public let created: Date?
    public let modified: Date?
    public let lastOpened: Date?

    public init(
        name: String, url: URL, kind: String, isFolder: Bool, isHidden: Bool, isReadOnly: Bool,
        fileSize: Int64?, created: Date?, modified: Date?, lastOpened: Date?
    ) {
        self.name = name
        self.url = url
        self.kind = kind
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.isReadOnly = isReadOnly
        self.fileSize = fileSize
        self.created = created
        self.modified = modified
        self.lastOpened = lastOpened
    }

    /// Reads the properties of `url`, or `nil` if it cannot be read.
    public static func read(_ url: URL) -> ItemInfo? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isHiddenKey, .isWritableKey, .fileSizeKey,
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey, .localizedTypeDescriptionKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDirectory = values.isDirectory == true
        let isPackage = values.isPackage == true
        return ItemInfo(
            name: url.lastPathComponent,
            url: url,
            kind: values.localizedTypeDescription ?? "",
            isFolder: isDirectory && !isPackage,
            isHidden: values.isHidden == true,
            isReadOnly: values.isWritable == false,
            fileSize: isDirectory ? nil : values.fileSize.map(Int64.init),
            created: values.creationDate,
            modified: values.contentModificationDate,
            lastOpened: values.contentAccessDate
        )
    }

    /// True when the size needs to be computed by walking the item.
    public var needsMeasuring: Bool { fileSize == nil }
}
