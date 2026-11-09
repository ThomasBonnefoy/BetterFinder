import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct BrowserModelTests {
    /// Temporary tree:  root/Alpha/Inner, root/Beta, root/notes.txt, root/.hidden
    private func makeTree() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Alpha/Inner"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "Beta"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appending(path: "notes.txt"))
        try Data().write(to: root.appending(path: ".hidden"))
        return BrowserModel.normalized(root)
    }

    private func loaded(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            if model.state != .loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not finish loading")
    }

    private func startedModel(at url: URL) async throws -> BrowserModel {
        let model = BrowserModel(start: url)
        model.start()
        try await loaded(model)
        return model
    }

    @Test func listsFoldersFirstAndHidesHiddenFiles() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        #expect(model.state == .loaded)
        #expect(model.items.map(\.name) == ["Alpha", "Beta", "notes.txt"])

        model.setShowHidden(true)
        #expect(model.items.map(\.name) == ["Alpha", "Beta", ".hidden", "notes.txt"])
    }

    @Test func sortingReordersTheList() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        model.setSort(FileSort(key: .name, ascending: false))
        #expect(model.items.map(\.name) == ["Beta", "Alpha", "notes.txt"])
    }

    @Test func openingAFolderThenGoingBackSelectsIt() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)
        let alpha = try #require(model.items.first { $0.name == "Alpha" })

        model.open([alpha])
        try await loaded(model)
        #expect(model.currentURL == alpha.url)
        #expect(model.items.map(\.name) == ["Inner"])
        #expect(model.canGoBack)

        model.goBack()
        try await loaded(model)
        #expect(model.currentURL == root)
        #expect(model.selection == [alpha.url])
        #expect(model.canGoForward)

        model.goForward()
        try await loaded(model)
        #expect(model.currentURL == alpha.url)
    }

    @Test func goingUpSelectsTheFolderWeCameFrom() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = root.appending(path: "Alpha/Inner")
        let model = try await startedModel(at: inner)

        model.goUp()
        try await loaded(model)
        #expect(model.currentURL == root.appending(path: "Alpha"))
        #expect(model.selection == [BrowserModel.normalized(inner)])
    }

    @Test func addressBarAcceptsFoldersFilesAndRelativePaths() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        model.beginEditingAddress()
        #expect(model.submitAddress("Alpha"))
        try await loaded(model)
        #expect(model.currentURL == root.appending(path: "Alpha"))
        #expect(!model.isEditingAddress)

        #expect(model.submitAddress(root.appending(path: "notes.txt").path))
        try await loaded(model)
        #expect(model.currentURL == root)
        #expect(model.selection == [root.appending(path: "notes.txt")])

        #expect(!model.submitAddress("/definitely/not/here"))
        #expect(model.currentURL == root)
    }

    @Test func unreadableFolderReportsAFailure() async throws {
        let model = try await startedModel(at: URL(filePath: "/nonexistent-\(UUID().uuidString)"))
        guard case .failed = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(model.items.isEmpty)
    }

    @Test func statusBarTexts() {
        #expect(StatusBar.countText(0) == "0 élément")
        #expect(StatusBar.countText(1) == "1 élément")
        #expect(StatusBar.countText(12) == "12 éléments")
    }
}
