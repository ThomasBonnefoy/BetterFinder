import AppKit
import BetterFinderCore
import QuickLookThumbnailing

/// Small pictures of images, videos and PDF documents, made by Quick Look
/// away from the main thread and kept for the next time the file is drawn.
@MainActor
enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2000
        return cache
    }()

    /// True when `item` should show its content rather than its type icon.
    /// Never on a network share: reading each file only to draw a list could
    /// be slow, so shares keep the generic icons.
    static func wants(_ item: FileItem, isLocalVolume: Bool) -> Bool {
        isLocalVolume && ThumbnailPolicy.wantsThumbnail(for: item.url, isDirectory: item.isDirectory)
    }

    /// The thumbnail if it was made already.
    static func cached(for item: FileItem, side: CGFloat) -> NSImage? {
        cache.object(forKey: key(item, side))
    }

    /// Makes the thumbnail, or returns `nil` when Quick Look has none (the
    /// caller then keeps the icon).
    static func load(for item: FileItem, side: CGFloat) async -> NSImage? {
        let key = key(item, side)
        if let image = cache.object(forKey: key) { return image }
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }

    /// A new version of the file (another modification date) is another
    /// thumbnail.
    private static func key(_ item: FileItem, _ side: CGFloat) -> NSString {
        let date = item.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(item.url.path)|\(date)|\(Int(side))" as NSString
    }
}
