import BetterFinderCore
import Foundation
import Observation

/// The folder tree of one window's sidebar: which rows are unfolded, and the
/// sub-folders read so far. Folders are read when their row is unfolded.
@MainActor
@Observable
final class SidebarTreeModel {
    private(set) var tree = FolderTree()
    /// Folders being read.
    private(set) var loading: Set<URL> = []

    /// Tells whether a folder is on a network drive whose server is gone:
    /// reading it would only wait on a dead mount.
    @ObservationIgnored var isUnreachable: @MainActor (URL) -> Bool = { _ in false }

    // MARK: - Reading the tree

    func isExpanded(_ node: FolderTreeNode) -> Bool {
        tree.isExpanded(node)
    }

    func subfolders(of folder: URL, showHidden: Bool) -> [FileItem]? {
        tree.subfolders(of: folder, showHidden: showHidden)
    }

    func isLeaf(_ folder: URL, showHidden: Bool) -> Bool {
        tree.isLeaf(folder, showHidden: showHidden)
    }

    func visibleNode(for url: URL, roots: [URL], showHidden: Bool) -> FolderTreeNode? {
        tree.visibleNode(for: url, roots: roots, showHidden: showHidden)
    }

    // MARK: - Unfolding

    func setExpanded(_ node: FolderTreeNode, _ isExpanded: Bool) {
        tree.setExpanded(node, isExpanded)
        if isExpanded {
            // Known content is shown right away, and checked again.
            load(node.url)
        }
    }

    /// Unfolds the tree down to a folder ("Expand to open folder" in Explorer).
    func reveal(_ url: URL, roots: [URL]) {
        for folder in tree.reveal(url, roots: roots)
        where tree.subfolders(of: folder, showHidden: true) == nil {
            load(folder)
        }
    }

    // MARK: - Content

    /// The window just listed a folder: the tree gets its sub-folders for free.
    func folderLoaded(_ url: URL, items: [FileItem]) {
        tree.setContent(items, of: url)
    }

    /// Reads again every unfolded folder, and forgets the others.
    func reload() {
        tree.forgetCollapsedFolders()
        for folder in tree.expandedFolders {
            load(folder)
        }
    }

    private func load(_ folder: URL) {
        guard !loading.contains(folder), !isUnreachable(folder) else { return }
        loading.insert(folder)
        Task {
            // A folder that cannot be read (no permission, gone) has nothing
            // to unfold.
            let items = (try? await DirectoryLoader.load(folder))?.items ?? []
            loading.remove(folder)
            tree.setContent(items.map(BrowserModel.normalized), of: folder)
        }
    }
}
