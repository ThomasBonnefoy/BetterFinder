import Foundation

/// One row of the sidebar's folder tree: a folder, under the sidebar entry
/// (favorite, drive or volume) it was unfolded from.
///
/// The same folder can show up under several entries (the Desktop under the
/// home folder and as a favorite): the root tells the rows apart.
public struct FolderTreeNode: Hashable, Sendable {
    public let root: URL
    public let url: URL

    public init(root: URL, url: URL) {
        self.root = root
        self.url = url
    }
}

/// What the sidebar's folder tree knows: which rows are unfolded, and the
/// sub-folders of the folders read so far.
///
/// It never touches the disk. URLs are expected in one spelling (no trailing
/// slash, no "." or ".." segment).
public struct FolderTree: Sendable {
    public private(set) var expanded: Set<FolderTreeNode> = []
    /// Sub-folders by folder, hidden ones included, sorted by name.
    private var content: [URL: [FileItem]] = [:]

    public init() {}

    // MARK: - Unfolding

    public func isExpanded(_ node: FolderTreeNode) -> Bool {
        expanded.contains(node)
    }

    public mutating func setExpanded(_ node: FolderTreeNode, _ isExpanded: Bool) {
        if isExpanded {
            expanded.insert(node)
        } else {
            // Rows below keep their state, like in Explorer: unfolding the
            // row again shows the tree as it was left.
            expanded.remove(node)
        }
    }

    /// Folders whose sub-folders are on screen, or would be if their parents
    /// were unfolded.
    public var expandedFolders: Set<URL> {
        Set(expanded.map(\.url))
    }

    // MARK: - Content

    /// Records what a folder contains. Only folders that can be browsed are
    /// kept.
    public mutating func setContent(_ items: [FileItem], of folder: URL) {
        content[folder] = items.filter(\.isBrowsable).sorted(by: FileSort())
    }

    /// Sub-folders of a folder, or `nil` when it has not been read yet.
    public func subfolders(of folder: URL, showHidden: Bool) -> [FileItem]? {
        guard let folders = content[folder] else { return nil }
        return showHidden ? folders : folders.filter { !$0.isHidden }
    }

    /// True when the folder is known to have no sub-folder to show: its row
    /// needs no disclosure arrow.
    public func isLeaf(_ folder: URL, showHidden: Bool) -> Bool {
        subfolders(of: folder, showHidden: showHidden)?.isEmpty ?? false
    }

    /// Drops what is known about folders that are not unfolded, so that they
    /// are read again when needed.
    public mutating func forgetCollapsedFolders() {
        let kept = expandedFolders
        content = content.filter { kept.contains($0.key) }
    }

    // MARK: - Finding a folder in the tree

    /// The folders from `root` down to `url`, both included, or `nil` when
    /// `url` is not inside `root`.
    public static func chain(from root: URL, to url: URL) -> [URL]? {
        let rootParts = root.pathComponents
        let parts = url.pathComponents
        guard parts.count >= rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        var chain = [root]
        var current = root
        for part in parts.dropFirst(rootParts.count) {
            current = URL(filePath: (current.path as NSString).appendingPathComponent(part), directoryHint: .notDirectory)
            chain.append(current)
        }
        return chain
    }

    /// Among sidebar entries, the ones `url` is in, closest first.
    private static func roots(containing url: URL, among roots: [URL]) -> [URL] {
        roots
            .filter { chain(from: $0, to: url) != nil }
            .sorted { $0.pathComponents.count > $1.pathComponents.count }
    }

    /// The row currently showing `url`, if there is one: every folder above
    /// it must be unfolded. Sidebar entries themselves are not tree rows.
    public func visibleNode(for url: URL, roots: [URL], showHidden: Bool) -> FolderTreeNode? {
        for root in Self.roots(containing: url, among: roots) {
            guard let chain = Self.chain(from: root, to: url), chain.count > 1 else { continue }
            let isVisible = zip(chain, chain.dropFirst()).allSatisfy { parent, child in
                isExpanded(FolderTreeNode(root: root, url: parent))
                    && subfolders(of: parent, showHidden: showHidden)?.contains { $0.url == child } == true
            }
            if isVisible {
                return FolderTreeNode(root: root, url: url)
            }
        }
        return nil
    }

    /// Unfolds the tree down to `url`, under the closest sidebar entry that
    /// contains it. Returns the folders that were unfolded, top first: their
    /// content is needed to show the row.
    @discardableResult
    public mutating func reveal(_ url: URL, roots: [URL]) -> [URL] {
        guard let root = Self.roots(containing: url, among: roots).first,
              let chain = Self.chain(from: root, to: url)
        else { return [] }
        let parents = Array(chain.dropLast())
        for parent in parents {
            expanded.insert(FolderTreeNode(root: root, url: parent))
        }
        return parents
    }
}
