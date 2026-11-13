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

@Suite struct CompressTests {
    private let files = FileManager.default
    private let executor = FileOperationExecutor()
    private let root: URL

    /// root/{a.txt, b.txt, Dir/inner.txt}
    init() throws {
        root = files.temporaryDirectory
            .appending(path: "BetterFinderZipTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Dir"), withIntermediateDirectories: true)
        try Data("aaa".utf8).write(to: root.appending(path: "a.txt"))
        try Data("bbb".utf8).write(to: root.appending(path: "b.txt"))
        try Data("inner".utf8).write(to: root.appending(path: "Dir/inner.txt"))
    }

    private func cleanUp() { try? files.removeItem(at: root) }

    /// Paths inside an archive, listed with the system `unzip`.
    private func entries(of archive: URL) -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        let output = Pipe()
        process.standardOutput = output
        try? process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
    }

    @Test func packsOneFileIntoAZipNextToIt() {
        defer { cleanUp() }
        let outcome = executor.execute(.compress([root.appending(path: "a.txt")], in: root, name: "a.txt.zip"))

        #expect(outcome.failure == nil)
        #expect(outcome.affected == [root.appending(path: "a.txt.zip")])
        #expect(entries(of: root.appending(path: "a.txt.zip")) == ["a.txt"])
        #expect(files.fileExists(atPath: root.appending(path: "a.txt").path))
    }

    @Test func aFolderKeepsItsNameAtTheTopOfTheArchive() {
        defer { cleanUp() }
        _ = executor.execute(.compress([root.appending(path: "Dir")], in: root, name: "Dir.zip"))
        #expect(entries(of: root.appending(path: "Dir.zip")) == ["Dir/", "Dir/inner.txt"])
    }

    @Test func severalItemsShareOneArchive() {
        defer { cleanUp() }
        let outcome = executor.execute(.compress(
            [root.appending(path: "a.txt"), root.appending(path: "b.txt")], in: root, name: "Archive.zip"))
        #expect(outcome.failure == nil)
        #expect(entries(of: root.appending(path: "Archive.zip")) == ["a.txt", "b.txt"])
    }

    @Test func itemsFromDifferentFoldersAreRefused() {
        defer { cleanUp() }
        let outcome = executor.execute(.compress(
            [root.appending(path: "a.txt"), root.appending(path: "Dir/inner.txt")], in: root, name: "x.zip"))
        #expect(outcome.failure?.reason == .differentFolders)
        #expect(!files.fileExists(atPath: root.appending(path: "x.zip").path))
    }

    @Test func neverOverwritesAnExistingArchive() throws {
        defer { cleanUp() }
        try Data("old".utf8).write(to: root.appending(path: "a.txt.zip"))
        let outcome = executor.execute(.compress([root.appending(path: "a.txt")], in: root, name: "a.txt.zip"))

        #expect(outcome.affected == [root.appending(path: "a.txt (2).zip")])
        #expect(try String(contentsOf: root.appending(path: "a.txt.zip"), encoding: .utf8) == "old")
    }

    @Test func undoPutsTheArchiveInTheTrash() {
        defer { cleanUp() }
        let outcome = executor.execute(.compress([root.appending(path: "a.txt")], in: root, name: "a.txt.zip"))
        #expect(outcome.undo == .trash([root.appending(path: "a.txt.zip")]))
    }

    @Test func aMissingSourceFailsAndLeavesNoArchive() {
        defer { cleanUp() }
        let outcome = executor.execute(.compress([root.appending(path: "nope.txt")], in: root, name: "nope.txt.zip"))

        #expect(outcome.failure != nil)
        #expect(outcome.undo == nil)
        #expect(!files.fileExists(atPath: root.appending(path: "nope.txt.zip").path))
    }

    @Test func archiveNamesFollowTheFinder() {
        #expect(FileNaming.archiveName(for: ["photo.png"]) == "photo.png.zip")
        #expect(FileNaming.archiveName(for: ["a", "b"]) == "Archive.zip")
    }
}

@Suite struct RenameManyTests {
    private let files = FileManager.default
    private let executor = FileOperationExecutor()
    private let root: URL

    /// root/{a.txt ("A"), b.txt ("B"), c.txt ("C")}
    init() throws {
        root = files.temporaryDirectory
            .appending(path: "BetterFinderRenameManyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a", "b", "c"] {
            try Data(name.uppercased().utf8).write(to: root.appending(path: "\(name).txt"))
        }
    }

    private func cleanUp() { try? files.removeItem(at: root) }
    private func url(_ name: String) -> URL { root.appending(path: name) }
    private func text(_ name: String) -> String? { try? String(contentsOf: url(name), encoding: .utf8) }
    private func names() -> [String] { ((try? files.contentsOfDirectory(atPath: root.path)) ?? []).sorted() }

    @Test func renamesSeveralItems() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("x.txt")),
            FileMove(from: url("b.txt"), to: url("y.txt")),
        ]))
        #expect(outcome.failure == nil)
        #expect(names() == ["c.txt", "x.txt", "y.txt"])
        #expect(text("x.txt") == "A")
        #expect(outcome.affected == [url("x.txt"), url("y.txt")])
    }

    @Test func twoItemsCanSwapNames() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("b.txt")),
            FileMove(from: url("b.txt"), to: url("a.txt")),
        ]))
        #expect(outcome.failure == nil)
        #expect(text("a.txt") == "B")
        #expect(text("b.txt") == "A")
        #expect(names() == ["a.txt", "b.txt", "c.txt"])
    }

    @Test func aChainShiftsNames() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("b.txt")),
            FileMove(from: url("b.txt"), to: url("c.txt")),
            FileMove(from: url("c.txt"), to: url("d.txt")),
        ]))
        #expect(outcome.failure == nil)
        #expect(names() == ["b.txt", "c.txt", "d.txt"])
        #expect(text("b.txt") == "A")
        #expect(text("d.txt") == "C")
    }

    @Test func undoGivesTheOriginalNamesBack() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("b.txt")),
            FileMove(from: url("b.txt"), to: url("a.txt")),
        ]))
        let undo = try? #require(outcome.undo)
        _ = executor.execute(undo ?? .renameMany([]))
        #expect(text("a.txt") == "A")
        #expect(text("b.txt") == "B")
    }

    @Test func aNameTakenByAnItemLeftAloneChangesNothing() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("x.txt")),
            FileMove(from: url("b.txt"), to: url("c.txt")),
        ]))
        #expect(outcome.failure?.reason == .nameTaken)
        #expect(outcome.undo == nil)
        #expect(names() == ["a.txt", "b.txt", "c.txt"])
        #expect(text("a.txt") == "A")
    }

    @Test func twoItemsGoingToTheSameNameChangeNothing() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("x.txt")),
            FileMove(from: url("b.txt"), to: url("X.txt")),
        ]))
        #expect(outcome.failure?.reason == .nameTaken)
        #expect(names() == ["a.txt", "b.txt", "c.txt"])
    }

    @Test func anInvalidNameChangesNothing() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("ok.txt")),
            FileMove(from: url("b.txt"), to: root.appending(path: "bad:name.txt")),
        ]))
        #expect(outcome.failure?.reason == .invalidName(.forbiddenCharacter))
        #expect(names() == ["a.txt", "b.txt", "c.txt"])
    }

    @Test func aMissingItemPutsEverythingBack() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([
            FileMove(from: url("a.txt"), to: url("x.txt")),
            FileMove(from: url("ghost.txt"), to: url("y.txt")),
        ]))
        #expect(outcome.failure != nil)
        #expect(names() == ["a.txt", "b.txt", "c.txt"])
        #expect(text("a.txt") == "A")
    }

    @Test func changingOnlyTheCaseIsAllowed() {
        defer { cleanUp() }
        let outcome = executor.execute(.renameMany([FileMove(from: url("a.txt"), to: url("A.txt"))]))
        #expect(outcome.failure == nil)
        #expect(names().contains("A.txt"))
    }
}
