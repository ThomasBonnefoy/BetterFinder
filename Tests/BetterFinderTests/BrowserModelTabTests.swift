import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct BrowserModelTabTests {
    /// Temporary tree:  root/Alpha, root/Beta, root/notes.txt
    private func makeTree() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderTabTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Alpha"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "Beta"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appending(path: "notes.txt"))
        return BrowserModel.normalized(root)
    }

    private func loaded(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            if model.state != .loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not finish loading")
    }

    /// A model whose new tabs are recorded instead of opened.
    private func startedModel(at url: URL) async throws -> (BrowserModel, () -> [BrowserLocation]) {
        let model = BrowserModel(start: url)
        var opened: [BrowserLocation] = []
        model.tabOpener = { opened.append($0) }
        model.start()
        try await loaded(model)
        return (model, { opened })
    }

    @Test func newTabOpensTheComputerOverview() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, opened) = try await startedModel(at: root)

        model.newTab()

        #expect(opened() == [.computer])
        // The current tab does not move.
        #expect(model.currentURL == root)
    }

    @Test func selectedFoldersOpenInOneTabEach() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, opened) = try await startedModel(at: root)

        model.selection = [root.appending(path: "Alpha"), root.appending(path: "Beta")]
        #expect(model.canOpenSelectionInNewTabs)
        model.openSelectionInNewTabs()

        #expect(opened() == [.folder(root.appending(path: "Alpha")), .folder(root.appending(path: "Beta"))])
        #expect(model.currentURL == root)
    }

    @Test func filesDoNotOpenInTabs() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, opened) = try await startedModel(at: root)

        #expect(!model.canOpenSelectionInNewTabs)

        model.selection = [root.appending(path: "Alpha"), root.appending(path: "notes.txt")]
        #expect(!model.canOpenSelectionInNewTabs)
        model.openSelectionInNewTabs()
        #expect(opened().isEmpty)
    }

    @Test func tabStartsInTheFolderItWasOpenedFor() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        // The window is created before it knows what to show.
        let model = BrowserModel(start: root)

        model.start(at: root.appending(path: "Alpha"))
        try await loaded(model)

        #expect(model.currentURL == root.appending(path: "Alpha"))
        #expect(!model.canGoBack)
    }

    @Test func tabsShareTheSidebarTree() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = SidebarTreeModel()
        let first = BrowserModel(start: root, sidebarTree: tree)
        let second = BrowserModel(start: root.appending(path: "Alpha"), sidebarTree: tree)
        first.start()
        second.start()
        try await loaded(first)
        try await loaded(second)

        tree.setExpanded(FolderTreeNode(root: root, url: root), true)
        #expect(second.sidebarTree.isExpanded(FolderTreeNode(root: root, url: root)))
        #expect(tree.subfolders(of: root, showHidden: false)?.map(\.name) == ["Alpha", "Beta"])
        #expect(tree.isLeaf(root.appending(path: "Alpha"), showHidden: false))
    }

    @Test func pendingTabRequestsAreServedInOrder() {
        let a = BrowserLocation.folder(URL(filePath: "/tmp/a"))
        #expect(WindowTabs.takeLocation() == nil)
        WindowTabs.request(a, in: nil)
        WindowTabs.request(.computer, in: nil)
        #expect(WindowTabs.takeLocation() == a)
        #expect(WindowTabs.takeLocation() == .computer)
        #expect(WindowTabs.takeLocation() == nil)
    }
}
