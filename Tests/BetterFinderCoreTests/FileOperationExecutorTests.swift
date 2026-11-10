import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FileOperationExecutorTests {
    private let files = FileManager.default
    private let executor = FileOperationExecutor()
    private let root: URL

    /// root/Source/{a.txt, b.txt, Dir/inner.txt}, root/Target/
    init() throws {
        root = files.temporaryDirectory
            .appending(path: "BetterFinderOpsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Source/Dir"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "Target"), withIntermediateDirectories: true)
        try Data("aaa".utf8).write(to: root.appending(path: "Source/a.txt"))
        try Data("bbb".utf8).write(to: root.appending(path: "Source/b.txt"))
        try Data("inner".utf8).write(to: root.appending(path: "Source/Dir/inner.txt"))
    }

    private var source: URL { root.appending(path: "Source") }
    private var target: URL { root.appending(path: "Target") }
    private func cleanUp() { try? files.removeItem(at: root) }
    private func exists(_ path: String) -> Bool { files.fileExists(atPath: root.appending(path: path).path) }
    private func names(in folder: URL) -> [String] {
        ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }
    private func text(_ path: String) -> String? {
        try? String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    // MARK: - Copy

    @Test func copiesFilesAndFoldersIntoAnotherFolder() {
        defer { cleanUp() }
        let outcome = executor.execute(.copy(
            sources: [source.appending(path: "a.txt"), source.appending(path: "Dir")], to: target))

        #expect(outcome.failure == nil)
        #expect(names(in: target) == ["Dir", "a.txt"])
        #expect(text("Target/Dir/inner.txt") == "inner")
        #expect(exists("Source/a.txt"))
        #expect(outcome.affected.map(\.lastPathComponent) == ["a.txt", "Dir"])
    }

    @Test func copyInTheSameFolderMakesACopieFile() {
        defer { cleanUp() }
        let a = source.appending(path: "a.txt")
        _ = executor.execute(.copy(sources: [a], to: source))
        let second = executor.execute(.copy(sources: [a], to: source))

        #expect(exists("Source/a - Copie.txt"))
        #expect(exists("Source/a - Copie (2).txt"))
        #expect(second.affected.map(\.lastPathComponent) == ["a - Copie (2).txt"])
        #expect(text("Source/a.txt") == "aaa")
    }

    @Test func copyNeverOverwrites() throws {
        defer { cleanUp() }
        try Data("already here".utf8).write(to: target.appending(path: "a.txt"))

        let outcome = executor.execute(.copy(sources: [source.appending(path: "a.txt")], to: target))

        #expect(outcome.failure == nil)
        #expect(text("Target/a.txt") == "already here")
        #expect(text("Target/a (2).txt") == "aaa")
    }

    @Test func aFolderCannotBeCopiedIntoItself() {
        defer { cleanUp() }
        let dir = source.appending(path: "Dir")
        let outcome = executor.execute(.copy(sources: [dir], to: dir))

        #expect(outcome.failure?.reason == .intoItself)
        #expect(outcome.undo == nil)
        #expect(names(in: dir) == ["inner.txt"])
    }

    @Test func aFailedCopyKeepsWhatWasDoneAndSaysWhatIsLeft() {
        defer { cleanUp() }
        let a = source.appending(path: "a.txt")
        let missing = source.appending(path: "missing.txt")
        let b = source.appending(path: "b.txt")

        let outcome = executor.execute(.copy(sources: [a, missing, b], to: target))

        #expect(names(in: target) == ["a.txt"])
        #expect(outcome.failure?.url == missing)
        #expect(outcome.failure?.remaining == [missing, b])
        #expect(outcome.undo == .trash([target.appending(path: "a.txt")]))
    }

    // MARK: - Move

    @Test func movesThenUndoesTheMove() {
        defer { cleanUp() }
        let outcome = executor.execute(.move(
            sources: [source.appending(path: "a.txt"), source.appending(path: "Dir")], to: target))

        #expect(outcome.failure == nil)
        #expect(names(in: target) == ["Dir", "a.txt"])
        #expect(names(in: source) == ["b.txt"])

        let undo = executor.execute(try! #require(outcome.undo))
        #expect(undo.failure == nil)
        #expect(names(in: target).isEmpty)
        #expect(names(in: source) == ["Dir", "a.txt", "b.txt"])

        // Undoing the undo is the move again.
        let redo = executor.execute(try! #require(undo.undo))
        #expect(redo.failure == nil)
        #expect(names(in: target) == ["Dir", "a.txt"])
    }

    @Test func movingWhereItAlreadyIsDoesNothing() {
        defer { cleanUp() }
        let outcome = executor.execute(.move(sources: [source.appending(path: "a.txt")], to: source))

        #expect(outcome == FileOperationOutcome())
        #expect(names(in: source) == ["Dir", "a.txt", "b.txt"])
    }

    @Test func moveNeverOverwrites() throws {
        defer { cleanUp() }
        try Data("already here".utf8).write(to: target.appending(path: "a.txt"))

        let outcome = executor.execute(.move(sources: [source.appending(path: "a.txt")], to: target))

        #expect(text("Target/a.txt") == "already here")
        #expect(text("Target/a (2).txt") == "aaa")
        #expect(outcome.affected.map(\.lastPathComponent) == ["a (2).txt"])
    }

    @Test func undoingAMoveRefusesToOverwrite() throws {
        defer { cleanUp() }
        let a = source.appending(path: "a.txt")
        let outcome = executor.execute(.move(sources: [a], to: target))
        try Data("new file with the old name".utf8).write(to: a)

        let undo = executor.execute(try #require(outcome.undo))

        #expect(undo.failure?.reason == .nameTaken)
        #expect(text("Source/a.txt") == "new file with the old name")
        #expect(text("Target/a.txt") == "aaa")
    }

    // MARK: - Rename

    @Test func renamesThenUndoes() throws {
        defer { cleanUp() }
        let outcome = executor.execute(.rename(source.appending(path: "a.txt"), to: "rapport.txt"))

        #expect(outcome.failure == nil)
        #expect(names(in: source) == ["Dir", "b.txt", "rapport.txt"])
        #expect(outcome.affected == [source.appending(path: "rapport.txt")])

        _ = executor.execute(try #require(outcome.undo))
        #expect(names(in: source) == ["Dir", "a.txt", "b.txt"])
    }

    @Test func renameRejectsBadAndTakenNames() {
        defer { cleanUp() }
        let a = source.appending(path: "a.txt")

        #expect(executor.execute(.rename(a, to: "")).failure?.reason == .invalidName(.empty))
        #expect(executor.execute(.rename(a, to: "x/y")).failure?.reason == .invalidName(.forbiddenCharacter))
        #expect(executor.execute(.rename(a, to: "b.txt")).failure?.reason == .nameTaken)
        #expect(names(in: source) == ["Dir", "a.txt", "b.txt"])
    }

    @Test func renamingToTheSameNameChangesNothing() {
        defer { cleanUp() }
        let a = source.appending(path: "a.txt")
        let outcome = executor.execute(.rename(a, to: "a.txt"))

        #expect(outcome.failure == nil)
        #expect(outcome.undo == nil)
    }

    @Test func renameCanChangeOnlyTheLetterCase() {
        defer { cleanUp() }
        let outcome = executor.execute(.rename(source.appending(path: "a.txt"), to: "A.TXT"))

        #expect(outcome.failure == nil)
        #expect(names(in: source).contains("A.TXT"))
    }

    // MARK: - Create

    @Test func createsFoldersAndFilesWithFreeNames() {
        defer { cleanUp() }
        let first = executor.execute(.createFolder(in: target, name: "Nouveau dossier"))
        let second = executor.execute(.createFolder(in: target, name: "Nouveau dossier"))
        let file = executor.execute(.createFile(in: target, name: "Nouveau document texte.txt"))

        #expect(first.failure == nil && second.failure == nil && file.failure == nil)
        #expect(names(in: target) == ["Nouveau document texte.txt", "Nouveau dossier", "Nouveau dossier (2)"])
        #expect(second.affected.map(\.lastPathComponent) == ["Nouveau dossier (2)"])
        #expect(first.undo == .trash(first.affected))
    }

    // MARK: - Delete

    @Test func deletesForGoodWithoutUndo() {
        defer { cleanUp() }
        let outcome = executor.execute(.delete([source.appending(path: "a.txt"), source.appending(path: "Dir")]))

        #expect(outcome.failure == nil)
        #expect(outcome.undo == nil)
        #expect(names(in: source) == ["b.txt"])
    }

    // MARK: - Trash

    @Test func trashesThenPutsBack() throws {
        defer { cleanUp() }
        let a = source.appending(path: "a.txt")
        let dir = source.appending(path: "Dir")

        let outcome = executor.execute(.trash([a, dir]))
        #expect(outcome.failure == nil)
        #expect(names(in: source) == ["b.txt"])
        let undo = try #require(outcome.undo)

        let restored = executor.execute(undo)
        #expect(restored.failure == nil)
        #expect(names(in: source) == ["Dir", "a.txt", "b.txt"])
        #expect(text("Source/Dir/inner.txt") == "inner")
    }

    @Test func runsAwayFromTheCallingThread() async {
        defer { cleanUp() }
        let outcome = await executor.run(.createFolder(in: target, name: "Async"))
        #expect(outcome.failure == nil)
        #expect(exists("Target/Async"))
    }
}
