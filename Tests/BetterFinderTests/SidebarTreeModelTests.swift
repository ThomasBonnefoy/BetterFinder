import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct SidebarTreeModelTests {
    /// Temporary tree:  root/Alpha/Inner/Deep, root/Beta, root/.git, root/notes.txt
    private func makeTree() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderTreeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Alpha/Inner/Deep"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "Beta"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appending(path: "notes.txt"))
        return BrowserModel.normalized(root)
    }

    private func settled(_ tree: SidebarTreeModel) async throws {
        for _ in 0..<500 {
            if tree.loading.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The tree did not finish loading")
    }

    private func loaded(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            if model.state != .loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not finish loading")
    }

    private func names(_ tree: SidebarTreeModel, _ folder: URL, showHidden: Bool = false) -> [String]? {
        tree.subfolders(of: folder, showHidden: showHidden)?.map(\.name)
    }

    @Test func unfoldingARowReadsItsSubfolders() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = SidebarTreeModel()
        let node = FolderTreeNode(root: root, url: root)

        #expect(names(tree, root) == nil)
        tree.setExpanded(node, true)
        #expect(tree.isExpanded(node))
        try await settled(tree)

        #expect(names(tree, root) == ["Alpha", "Beta"])
        #expect(names(tree, root, showHidden: true) == [".git", "Alpha", "Beta"])
    }

    @Test func folderWithoutSubfolderBecomesALeaf() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = SidebarTreeModel()
        let beta = root.appending(path: "Beta")

        #expect(!tree.isLeaf(beta, showHidden: false))
        tree.setExpanded(FolderTreeNode(root: root, url: beta), true)
        try await settled(tree)
        #expect(tree.isLeaf(beta, showHidden: false))
    }

    @Test func unreadableFolderHasNothingToUnfold() async throws {
        let tree = SidebarTreeModel()
        let missing = URL(filePath: "/nonexistent-\(UUID().uuidString)")
        tree.setExpanded(FolderTreeNode(root: missing, url: missing), true)
        try await settled(tree)
        #expect(tree.isLeaf(missing, showHidden: true))
    }

    @Test func unreachableFolderIsNotRead() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = SidebarTreeModel()
        tree.isUnreachable = { _ in true }

        tree.setExpanded(FolderTreeNode(root: root, url: root), true)
        #expect(tree.loading.isEmpty)
        #expect(names(tree, root) == nil)
    }

    @Test func revealUnfoldsDownToTheFolder() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = SidebarTreeModel()
        let deep = root.appending(path: "Alpha/Inner/Deep")

        tree.reveal(deep, roots: [root])
        try await settled(tree)

        #expect(tree.visibleNode(for: deep, roots: [root], showHidden: false)
            == FolderTreeNode(root: root, url: deep))
    }

    @Test func reloadSeesFoldersCreatedElsewhere() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = SidebarTreeModel()
        tree.setExpanded(FolderTreeNode(root: root, url: root), true)
        try await settled(tree)

        try FileManager.default.createDirectory(
            at: root.appending(path: "Gamma"), withIntermediateDirectories: false)
        tree.reload()
        try await settled(tree)

        #expect(names(tree, root) == ["Alpha", "Beta", "Gamma"])
    }

    @Test func listingAFolderInTheWindowFeedsTheTree() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BrowserModel(start: root)
        model.start()
        try await loaded(model)

        // Nothing was unfolded: the tree knows the folder from the list.
        #expect(names(model.sidebarTree, root) == ["Alpha", "Beta"])

        model.navigate(to: root.appending(path: "Beta"))
        try await loaded(model)
        #expect(model.sidebarTree.isLeaf(root.appending(path: "Beta"), showHidden: false))
    }

    @Test func folderCreatedInTheListShowsInTheTree() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BrowserModel(start: root.appending(path: "Beta"))
        model.start()
        try await loaded(model)
        let beta = root.appending(path: "Beta")
        #expect(model.sidebarTree.isLeaf(beta, showHidden: false))

        model.newFolder()
        for _ in 0..<500 where names(model.sidebarTree, beta) != ["Nouveau dossier"] {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(names(model.sidebarTree, beta) == ["Nouveau dossier"])
    }
}
