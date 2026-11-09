import Foundation

/// One entry (file or folder) of a directory listing.
public struct FileItem: Identifiable, Hashable, Sendable {
    public let url: URL
    /// Name shown in the list. Folders use their localized name ("Bureau"),
    /// files keep their real name with its extension.
    public let name: String
    public let isDirectory: Bool
    /// A directory that macOS presents as a single file (an app, a bundle).
    public let isPackage: Bool
    public let isHidden: Bool
    /// Size in bytes. `nil` for directories.
    public let size: Int64?
    public let modificationDate: Date?
    /// Localized type description ("Dossier", "Image PNG").
    public let kind: String

    public var id: URL { url }

    /// True when double-clicking the item should show its content in the list.
    public var isBrowsable: Bool { isDirectory && !isPackage }

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool = false,
        isHidden: Bool = false,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        kind: String = ""
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.size = size
        self.modificationDate = modificationDate
        self.kind = kind
    }
}
