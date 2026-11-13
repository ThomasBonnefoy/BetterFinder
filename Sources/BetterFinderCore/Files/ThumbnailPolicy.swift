import Foundation
import UniformTypeIdentifiers

/// Which files are shown as a small picture of their content, as the
/// Finder does, instead of the icon of their type.
public enum ThumbnailPolicy {
    /// True for images, videos and PDF documents. Folders, apps and other
    /// documents keep their icon: asking for a preview of every file would
    /// make a big folder slow for little gain.
    public static func wantsThumbnail(for url: URL, isDirectory: Bool) -> Bool {
        guard !isDirectory, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .pdf)
    }
}
