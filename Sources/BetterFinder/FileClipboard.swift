import AppKit
import Observation

/// Files copied or cut, shared by every window through the system
/// pasteboard: what is copied here can be pasted in the Finder, and back.
///
/// macOS has no notion of "cut" for files. A cut is remembered here, tied to
/// the pasteboard's change count: if anything else is copied meanwhile, the
/// cut is forgotten and a paste copies instead of moving.
@MainActor
@Observable
final class FileClipboard {
    static let shared = FileClipboard()

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var cutChangeCount: Int?
    private var cutItems: Set<URL> = []

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Items waiting to be moved by the next paste, shown dimmed in lists.
    var cutURLs: Set<URL> {
        cutChangeCount == pasteboard.changeCount ? cutItems : []
    }

    var hasFiles: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    func copy(_ urls: [URL]) {
        write(urls)
        cutItems = []
        cutChangeCount = nil
    }

    func cut(_ urls: [URL]) {
        write(urls)
        cutItems = Set(urls)
        cutChangeCount = pasteboard.changeCount
    }

    /// The files on the pasteboard, and whether pasting them is a move.
    func contents() -> (urls: [URL], isCut: Bool) {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return (objects, !objects.isEmpty && cutChangeCount == pasteboard.changeCount)
    }

    /// Called once cut items have been moved: they cannot be pasted twice.
    func clearCut() {
        guard cutChangeCount == pasteboard.changeCount else { return }
        pasteboard.clearContents()
        cutItems = []
        cutChangeCount = nil
    }

    func copyText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        cutItems = []
        cutChangeCount = nil
    }

    private func write(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }
}
