import AppKit
import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct BrowserModelFileOperationTests {
    private let files = FileManager.default
    private let root: URL
    private let pasteboard: NSPasteboard
    private let clipboard: FileClipboard
    private let undoManager = UndoManager()

    /// root/Source/{a.txt, b.txt}, root/Target/
    init() throws {
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderModelOpsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base.appending(path: "Source"), withIntermediateDirectories: true)
        try files.createDirectory(at: base.appending(path: "Target"), withIntermediateDirectories: true)
        try Data("aaa".utf8).write(to: base.appending(path: "Source/a.txt"))
        try Data("bbb".utf8).write(to: base.appending(path: "Source/b.txt"))
        root = BrowserModel.normalized(base)

        // A private pasteboard: the tests must not touch the user's clipboard.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("betterfinder-tests-\(UUID().uuidString)"))
        clipboard = FileClipboard(pasteboard: pasteboard)
    }

    private var source: URL { root.appending(path: "Source") }
    private var target: URL { root.appending(path: "Target") }

    private func cleanUp() {
        try? files.removeItem(at: root)
        pasteboard.releaseGlobally()
    }

    private func names(in folder: URL) -> [String] {
        ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private func settled(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            try await Task.sleep(for: .milliseconds(10))
            if model.state != .loading, model.activity == nil, model.pendingLoads == 0 { return }
        }
        Issue.record("The model did not settle")
    }

    private func model(at folder: URL) async throws -> BrowserModel {
        let model = BrowserModel(start: folder, clipboard: clipboard)
        model.undoManager = undoManager
        model.start()
        try await settled(model)
        return model
    }

    private func select(_ names: String..., in model: BrowserModel) {
        model.selection = Set(model.items.filter { names.contains($0.name) }.map(\.url))
    }

    // MARK: - Drag and drop

    @Test func droppingFilesOnAFolderMovesThem() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)

        let urls = [source.appending(path: "a.txt")]
        #expect(model.drop(urls, into: target, mode: .move))
        try await settled(model)

        #expect(names(in: target) == ["a.txt"])
        #expect(names(in: source) == ["b.txt"])
        #expect(model.items.map(\.name) == ["b.txt"])
    }

    @Test func droppingWithACopyKeepsTheOriginals() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)

        let urls = [source.appending(path: "a.txt"), source.appending(path: "b.txt")]
        #expect(model.drop(urls, into: target, mode: .copy))
        try await settled(model)

        #expect(names(in: target) == ["a.txt", "b.txt"])
        #expect(names(in: source) == ["a.txt", "b.txt"])
    }

    @Test func aDropCanBeUndone() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)

        model.drop([source.appending(path: "a.txt")], into: target, mode: .move)
        try await settled(model)
        undoManager.undo()
        try await settled(model)

        #expect(names(in: source) == ["a.txt", "b.txt"])
        #expect(names(in: target) == [])
    }

    // MARK: - Search

    private func searched(_ model: BrowserModel, for text: String) async throws {
        model.searchText = text
        for _ in 0..<500 {
            try await Task.sleep(for: .milliseconds(10))
            if !model.isSearchRunning { return }
        }
        Issue.record("The search did not finish")
    }

    @Test func searchFindsItemsInSubfolders() async throws {
        defer { cleanUp() }
        let model = try await model(at: root)

        try await searched(model, for: "a.t")
        #expect(model.isSearching)
        #expect(model.items.map(\.url) == [source.appending(path: "a.txt")])

        // Emptying the field brings the folder back.
        model.searchText = ""
        #expect(!model.isSearching)
        #expect(model.items.map(\.name) == ["Source", "Target"])
    }

    @Test func searchEndsWhenWentElsewhere() async throws {
        defer { cleanUp() }
        let model = try await model(at: root)

        try await searched(model, for: "txt")
        #expect(model.items.count == 2)
        model.navigate(to: target)
        try await settled(model)

        #expect(model.searchText.isEmpty)
        #expect(!model.isSearching)
    }

    @Test func showingAResultsFolderLeavesTheSearch() async throws {
        defer { cleanUp() }
        let model = try await model(at: root)

        try await searched(model, for: "b.txt")
        model.selection = [source.appending(path: "b.txt")]
        model.showSelectionInItsFolder()
        try await settled(model)

        #expect(model.currentURL == source)
        #expect(!model.isSearching)
        #expect(model.selection == [source.appending(path: "b.txt")])
    }

    // MARK: - Copy, cut, paste

    @Test func copyThenPasteInAnotherFolder() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", "b.txt", in: model)

        model.copySelection()
        #expect(model.canPaste)
        model.navigate(to: target)
        try await settled(model)
        model.paste()
        try await settled(model)

        #expect(names(in: target) == ["a.txt", "b.txt"])
        #expect(names(in: source) == ["a.txt", "b.txt"])
        #expect(model.items.map(\.name) == ["a.txt", "b.txt"])
        #expect(model.selection == [target.appending(path: "a.txt"), target.appending(path: "b.txt")])
        #expect(model.alert == nil)

        // Pasting again keeps both, like Explorer.
        model.paste()
        try await settled(model)
        #expect(names(in: target) == ["a (2).txt", "a.txt", "b (2).txt", "b.txt"])
    }

    @Test func pasteNextToTheOriginalMakesACopie() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)

        model.copySelection()
        model.paste()
        try await settled(model)

        #expect(names(in: source) == ["a - Copie.txt", "a.txt", "b.txt"])
        #expect(model.selection == [source.appending(path: "a - Copie.txt")])
    }

    @Test func cutThenPasteMovesOnce() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)

        model.cutSelection()
        #expect(clipboard.cutURLs == [source.appending(path: "a.txt")])
        model.navigate(to: target)
        try await settled(model)
        model.paste()
        try await settled(model)

        #expect(names(in: target) == ["a.txt"])
        #expect(names(in: source) == ["b.txt"])
        #expect(clipboard.cutURLs.isEmpty)
        #expect(!model.canPaste)        // a cut can only be pasted once
    }

    @Test func copyingSomethingElseCancelsTheCut() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)
        model.cutSelection()
        select("b.txt", in: model)
        model.copySelection()

        #expect(clipboard.cutURLs.isEmpty)
        #expect(clipboard.contents().isCut == false)
        #expect(clipboard.contents().urls == [source.appending(path: "b.txt")])
    }

    // MARK: - Undo

    @Test func undoAndRedoAMove() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)
        model.cutSelection()
        model.navigate(to: target)
        try await settled(model)
        model.paste()
        try await settled(model)
        #expect(undoManager.canUndo)
        #expect(undoManager.undoActionName == "le déplacement")

        undoManager.undo()
        try await settled(model)
        #expect(names(in: target).isEmpty)
        #expect(names(in: source) == ["a.txt", "b.txt"])
        #expect(undoManager.canRedo)

        undoManager.redo()
        try await settled(model)
        #expect(names(in: target) == ["a.txt"])
        #expect(names(in: source) == ["b.txt"])
        #expect(undoManager.canUndo)
    }

    @Test func undoATrashPutsTheFileBack() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)

        model.trashSelection()
        try await settled(model)
        #expect(names(in: source) == ["b.txt"])
        #expect(model.items.map(\.name) == ["b.txt"])

        undoManager.undo()
        try await settled(model)
        #expect(names(in: source) == ["a.txt", "b.txt"])
        #expect(model.selection == [source.appending(path: "a.txt")])
    }

    @Test func aFailedOperationLeavesNothingToUndo() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)

        model.rename(source.appending(path: "a.txt"), to: "b.txt")
        try await settled(model)

        #expect(model.alert?.title == "Ce nom est déjà utilisé")
        #expect(!undoManager.canUndo)
        #expect(names(in: source) == ["a.txt", "b.txt"])
    }

    // MARK: - Rename and create

    @Test func renameSelectsTheRenamedItem() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)

        model.rename(source.appending(path: "a.txt"), to: "rapport.txt")
        try await settled(model)

        #expect(names(in: source) == ["b.txt", "rapport.txt"])
        #expect(model.selection == [source.appending(path: "rapport.txt")])

        undoManager.undo()
        try await settled(model)
        #expect(names(in: source) == ["a.txt", "b.txt"])
    }

    @Test func invalidNameShowsAnExplanation() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)

        model.rename(source.appending(path: "a.txt"), to: "a/b")
        try await settled(model)

        #expect(model.alert?.title == "Nom impossible")
        #expect(names(in: source) == ["a.txt", "b.txt"])
    }

    @Test func newFolderIsSelectedAndReadyToBeRenamed() async throws {
        defer { cleanUp() }
        let model = try await model(at: target)

        model.newFolder()
        try await settled(model)
        let created = target.appending(path: "Nouveau dossier")

        #expect(names(in: target) == ["Nouveau dossier"])
        #expect(model.selection == [created])
        #expect(model.renameRequest?.url == created)

        model.newFolder()
        try await settled(model)
        #expect(names(in: target) == ["Nouveau dossier", "Nouveau dossier (2)"])
        #expect(model.renameRequest?.url == target.appending(path: "Nouveau dossier (2)"))
    }

    @Test func newTextFile() async throws {
        defer { cleanUp() }
        let model = try await model(at: target)

        model.newTextFile()
        try await settled(model)

        #expect(names(in: target) == ["Nouveau document texte.txt"])
        #expect(model.renameRequest?.url == target.appending(path: "Nouveau document texte.txt"))
    }

    // MARK: - Delete

    @Test func permanentDeletionAsksFirst() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)

        model.askToDeleteSelection()
        #expect(model.deleteConfirmation?.urls == [source.appending(path: "a.txt")])
        #expect(model.deleteConfirmation?.becauseNoTrash == false)
        #expect(names(in: source) == ["a.txt", "b.txt"])      // nothing deleted yet

        model.deletePermanently([source.appending(path: "a.txt")])
        try await settled(model)
        #expect(names(in: source) == ["b.txt"])
        #expect(!undoManager.canUndo)
    }

    @Test func copyAsPath() async throws {
        defer { cleanUp() }
        let model = try await model(at: source)
        select("a.txt", in: model)

        model.copyPathOfSelection()

        #expect(pasteboard.string(forType: .string) == source.appending(path: "a.txt").path)
    }
}
