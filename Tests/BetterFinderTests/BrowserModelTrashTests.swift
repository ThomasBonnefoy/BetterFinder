import AppKit
import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite(.serialized) struct BrowserModelTrashTests {
    private let files = FileManager.default
    private let root: URL
    private let pasteboard: NSPasteboard
    private let clipboard: FileClipboard
    private let undoManager = UndoManager()

    /// root/Folder/{a.txt, b.txt}, and root/FakeTrash/{old.txt, .DS_Store}
    /// standing for the Trash.
    init() throws {
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderTrashModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base.appending(path: "Folder"), withIntermediateDirectories: true)
        try files.createDirectory(at: base.appending(path: "FakeTrash"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: base.appending(path: "Folder/a.txt"))
        try Data("b".utf8).write(to: base.appending(path: "Folder/b.txt"))
        try Data("old".utf8).write(to: base.appending(path: "FakeTrash/old.txt"))
        try Data().write(to: base.appending(path: "FakeTrash/.DS_Store"))
        root = BrowserModel.normalized(base)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("betterfinder-trash-tests-\(UUID().uuidString)"))
        clipboard = FileClipboard(pasteboard: pasteboard)
    }

    private var folder: URL { root.appending(path: "Folder") }
    private var fakeTrash: URL { root.appending(path: "FakeTrash") }

    private func cleanUp() {
        try? files.removeItem(at: root)
        pasteboard.releaseGlobally()
    }

    private func model(at start: URL) async throws -> BrowserModel {
        let model = BrowserModel(start: start, clipboard: clipboard, trash: fakeTrash)
        model.undoManager = undoManager
        model.start()
        for _ in 0..<500 {
            if model.state != .loading, model.pendingLoads == 0 { return model }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not finish loading")
        return model
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The expected state never came")
    }

    @Test func knowsWhenItIsInTheTrash() async throws {
        defer { cleanUp() }
        let model = try await model(at: fakeTrash)
        #expect(model.isOnTrash)
        #expect(model.isInTrash)
        #expect(model.title == "Corbeille")

        let other = try await self.model(at: folder)
        #expect(!other.isOnTrash)
        #expect(!other.isInTrash)
        other.showTrash()
        #expect(other.isOnTrash)
        #expect(other.title == "Corbeille")
    }

    @Test func nothingIsPastedOrCreatedInTheTrash() async throws {
        defer { cleanUp() }
        clipboard.copy([folder.appending(path: "a.txt")])
        let model = try await model(at: fakeTrash)
        #expect(!model.canPaste)
        model.paste()
        model.newFolder()
        model.newTextFile()
        try await Task.sleep(for: .milliseconds(200))
        let names = ((try? files.contentsOfDirectory(atPath: fakeTrash.path)) ?? []).sorted()
        #expect(names == [".DS_Store", "old.txt"])
    }

    @Test func deletingInTheTrashAsksForConfirmationInsteadOfTrashingAgain() async throws {
        defer { cleanUp() }
        let model = try await model(at: fakeTrash)
        let old = try #require(model.items.first { $0.name == "old.txt" })
        model.selection = [old.url]
        model.trashSelection()
        #expect(model.deleteConfirmation?.urls == [old.url])
        #expect(model.deleteConfirmation?.emptiesTrash == false)
        // Still there: nothing was moved.
        #expect(files.fileExists(atPath: old.url.path))
    }

    @Test func emptyingTheTrashAsksThenDeletesEverythingButTheStoreFile() async throws {
        defer { cleanUp() }
        let model = try await model(at: folder)
        model.askToEmptyTrash()
        try await waitFor { model.deleteConfirmation != nil }
        let confirmation = try #require(model.deleteConfirmation)
        #expect(confirmation.emptiesTrash)
        #expect(confirmation.urls.map(\.lastPathComponent) == ["old.txt"])
        #expect(files.fileExists(atPath: fakeTrash.appending(path: "old.txt").path))

        model.deletePermanently(confirmation.urls)
        try await waitFor { !files.fileExists(atPath: fakeTrash.appending(path: "old.txt").path) }
        #expect(!files.fileExists(atPath: fakeTrash.appending(path: "old.txt").path))
    }

    @Test func emptyingAnEmptyTrashSaysSo() async throws {
        defer { cleanUp() }
        try files.removeItem(at: fakeTrash.appending(path: "old.txt"))
        let model = try await model(at: folder)
        model.askToEmptyTrash()
        try await waitFor { model.alert != nil }
        #expect(model.alert?.title == "La corbeille est vide")
        #expect(model.deleteConfirmation == nil)
    }

    @Test func anUnreadableTrashIsReportedNotIgnored() async throws {
        defer { cleanUp() }
        try files.removeItem(at: fakeTrash)
        let model = try await model(at: folder)
        model.askToEmptyTrash()
        try await waitFor { model.alert != nil }
        #expect(model.alert?.title == "La corbeille est illisible")
    }

    @Test func droppingOnTheTrashPutsFilesInIt() async throws {
        defer { cleanUp() }
        let model = try await model(at: folder)
        let a = folder.appending(path: "a.txt")
        // Only a drop on the Trash itself goes to it.
        #expect(model.drop([a], into: fakeTrash, mode: .move))
        try await waitFor { !files.fileExists(atPath: a.path) }
        #expect(!files.fileExists(atPath: a.path))
        // The Trash is the real one here (the fake one is not on the Trash
        // volume's rules): put the file back with Undo.
        undoManager.undo()
        try await waitFor { files.fileExists(atPath: a.path) }
        #expect(files.fileExists(atPath: a.path))
    }

    @Test func whatIsAlreadyInTheTrashIsNotDroppedOnIt() async throws {
        defer { cleanUp() }
        let model = try await model(at: folder)
        let old = fakeTrash.appending(path: "old.txt")
        #expect(!model.drop([old], into: fakeTrash, mode: .move))
        #expect(files.fileExists(atPath: old.path))
    }
}
