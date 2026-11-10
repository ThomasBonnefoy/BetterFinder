import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FolderTreeTests {
    private func url(_ path: String) -> URL {
        URL(filePath: path, directoryHint: .notDirectory)
    }

    private func folder(_ path: String, hidden: Bool = false) -> FileItem {
        let url = url(path)
        return FileItem(url: url, name: url.lastPathComponent, isDirectory: true, isHidden: hidden)
    }

    private func file(_ path: String) -> FileItem {
        let url = url(path)
        return FileItem(url: url, name: url.lastPathComponent, isDirectory: false)
    }

    private func node(_ root: String, _ path: String) -> FolderTreeNode {
        FolderTreeNode(root: url(root), url: url(path))
    }

    // MARK: - Content

    @Test func keepsOnlyFoldersSortedByName() {
        var tree = FolderTree()
        let app = FileItem(url: url("/a/Tool.app"), name: "Tool.app", isDirectory: true, isPackage: true)
        tree.setContent(
            [folder("/a/img10"), file("/a/notes.txt"), folder("/a/img2"), app, folder("/a/Alpha")],
            of: url("/a")
        )

        #expect(tree.subfolders(of: url("/a"), showHidden: false)?.map(\.name) == ["Alpha", "img2", "img10"])
    }

    @Test func unreadFolderHasNoKnownContent() {
        let tree = FolderTree()
        #expect(tree.subfolders(of: url("/a"), showHidden: true) == nil)
        #expect(!tree.isLeaf(url("/a"), showHidden: true))
    }

    @Test func hiddenFoldersFollowTheSetting() {
        var tree = FolderTree()
        tree.setContent([folder("/a/.git", hidden: true)], of: url("/a"))

        #expect(tree.subfolders(of: url("/a"), showHidden: true)?.map(\.name) == [".git"])
        #expect(tree.subfolders(of: url("/a"), showHidden: false) == [])
        #expect(tree.isLeaf(url("/a"), showHidden: false))
        #expect(!tree.isLeaf(url("/a"), showHidden: true))
    }

    @Test func folderWithoutSubfolderIsALeaf() {
        var tree = FolderTree()
        tree.setContent([file("/a/notes.txt")], of: url("/a"))
        #expect(tree.isLeaf(url("/a"), showHidden: true))
    }

    // MARK: - Unfolding

    @Test func sameFolderUnfoldsSeparatelyUnderEachRoot() {
        var tree = FolderTree()
        tree.setExpanded(node("/Users/me", "/Users/me/Desktop"), true)

        #expect(tree.isExpanded(node("/Users/me", "/Users/me/Desktop")))
        #expect(!tree.isExpanded(node("/Users/me/Desktop", "/Users/me/Desktop")))
        #expect(tree.expandedFolders == [url("/Users/me/Desktop")])

        tree.setExpanded(node("/Users/me", "/Users/me/Desktop"), false)
        #expect(tree.expanded.isEmpty)
    }

    @Test func forgettingKeepsUnfoldedFolders() {
        var tree = FolderTree()
        tree.setContent([folder("/a/b")], of: url("/a"))
        tree.setContent([], of: url("/a/b"))
        tree.setExpanded(node("/a", "/a"), true)

        tree.forgetCollapsedFolders()
        #expect(tree.subfolders(of: url("/a"), showHidden: true) != nil)
        #expect(tree.subfolders(of: url("/a/b"), showHidden: true) == nil)
    }

    // MARK: - Chains

    @Test func chainListsEveryFolderFromTheRoot() {
        #expect(FolderTree.chain(from: url("/Users/me"), to: url("/Users/me/Docs/Work"))
            == [url("/Users/me"), url("/Users/me/Docs"), url("/Users/me/Docs/Work")])
        #expect(FolderTree.chain(from: url("/"), to: url("/Users/me"))
            == [url("/"), url("/Users"), url("/Users/me")])
        #expect(FolderTree.chain(from: url("/a"), to: url("/a")) == [url("/a")])
    }

    @Test func chainIsNilOutsideTheRoot() {
        #expect(FolderTree.chain(from: url("/Users/me"), to: url("/Users/other")) == nil)
        // A name that merely starts the same way is not inside.
        #expect(FolderTree.chain(from: url("/Users/me"), to: url("/Users/meadow/x")) == nil)
        #expect(FolderTree.chain(from: url("/a/b"), to: url("/a")) == nil)
    }

    // MARK: - Finding the row of a folder

    @Test func nodeIsVisibleOnlyWhenEveryParentIsUnfolded() {
        var tree = FolderTree()
        let roots = [url("/a")]
        tree.setContent([folder("/a/b")], of: url("/a"))
        tree.setContent([folder("/a/b/c")], of: url("/a/b"))

        #expect(tree.visibleNode(for: url("/a/b/c"), roots: roots, showHidden: false) == nil)

        tree.setExpanded(node("/a", "/a"), true)
        #expect(tree.visibleNode(for: url("/a/b"), roots: roots, showHidden: false) == node("/a", "/a/b"))
        #expect(tree.visibleNode(for: url("/a/b/c"), roots: roots, showHidden: false) == nil)

        tree.setExpanded(node("/a", "/a/b"), true)
        #expect(tree.visibleNode(for: url("/a/b/c"), roots: roots, showHidden: false) == node("/a", "/a/b/c"))
    }

    @Test func rootsAreNotTreeRows() {
        var tree = FolderTree()
        tree.setExpanded(node("/a", "/a"), true)
        #expect(tree.visibleNode(for: url("/a"), roots: [url("/a")], showHidden: false) == nil)
    }

    @Test func hiddenRowIsNotVisible() {
        var tree = FolderTree()
        tree.setContent([folder("/a/.git", hidden: true)], of: url("/a"))
        tree.setExpanded(node("/a", "/a"), true)

        #expect(tree.visibleNode(for: url("/a/.git"), roots: [url("/a")], showHidden: false) == nil)
        #expect(tree.visibleNode(for: url("/a/.git"), roots: [url("/a")], showHidden: true) == node("/a", "/a/.git"))
    }

    @Test func closestRootWinsWhenAFolderShowsTwice() {
        var tree = FolderTree()
        let roots = [url("/Users/me"), url("/Users/me/Desktop")]
        tree.setContent([folder("/Users/me/Desktop")], of: url("/Users/me"))
        tree.setContent([folder("/Users/me/Desktop/x")], of: url("/Users/me/Desktop"))
        tree.setExpanded(node("/Users/me", "/Users/me"), true)
        tree.setExpanded(node("/Users/me", "/Users/me/Desktop"), true)

        // Only shown under the home folder: that row is the one.
        #expect(tree.visibleNode(for: url("/Users/me/Desktop/x"), roots: roots, showHidden: false)
            == node("/Users/me", "/Users/me/Desktop/x"))

        tree.setExpanded(node("/Users/me/Desktop", "/Users/me/Desktop"), true)
        #expect(tree.visibleNode(for: url("/Users/me/Desktop/x"), roots: roots, showHidden: false)
            == node("/Users/me/Desktop", "/Users/me/Desktop/x"))
    }

    // MARK: - Reveal

    @Test func revealUnfoldsParentsUnderTheClosestRoot() {
        var tree = FolderTree()
        let roots = [url("/"), url("/Users/me"), url("/Volumes/USB")]

        let unfolded = tree.reveal(url("/Users/me/Docs/Work"), roots: roots)

        #expect(unfolded == [url("/Users/me"), url("/Users/me/Docs")])
        #expect(tree.expanded == [node("/Users/me", "/Users/me"), node("/Users/me", "/Users/me/Docs")])
    }

    @Test func revealingARootOrAnOutsideFolderUnfoldsNothing() {
        var tree = FolderTree()
        #expect(tree.reveal(url("/Users/me"), roots: [url("/Users/me")]).isEmpty)
        #expect(tree.reveal(url("/opt/tools"), roots: [url("/Users/me")]).isEmpty)
        #expect(tree.expanded.isEmpty)
    }
}
