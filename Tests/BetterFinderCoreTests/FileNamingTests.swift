import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FileNamingTests {
    private let folder = URL(filePath: "/tmp/naming", directoryHint: .isDirectory)

    private func taken(_ names: String...) -> (URL) -> Bool {
        let set = Set(names)
        return { set.contains($0.lastPathComponent) }
    }

    @Test func invalidNames() {
        #expect(FileNaming.problem(with: "") == .empty)
        #expect(FileNaming.problem(with: "   ") == .empty)
        #expect(FileNaming.problem(with: ".") == .reserved)
        #expect(FileNaming.problem(with: "..") == .reserved)
        #expect(FileNaming.problem(with: "a/b") == .forbiddenCharacter)
        #expect(FileNaming.problem(with: "a:b") == .forbiddenCharacter)
        #expect(FileNaming.problem(with: "rapport final.txt") == nil)
        #expect(FileNaming.problem(with: ".gitignore") == nil)
    }

    @Test func splitsNameAndExtension() {
        #expect(FileNaming.split("photo.final.png", isDirectory: false) == ("photo.final", "png"))
        #expect(FileNaming.split("README", isDirectory: false) == ("README", ""))
        #expect(FileNaming.split(".gitignore", isDirectory: false) == (".gitignore", ""))
        #expect(FileNaming.split("Dossier v1.2", isDirectory: true) == ("Dossier v1.2", ""))
    }

    @Test func freeNameIsKept() {
        let url = FileNaming.availableURL(for: "a.txt", in: folder, isDirectory: false, exists: taken())
        #expect(url.lastPathComponent == "a.txt")
    }

    @Test func takenNameGetsANumberBeforeTheExtension() {
        let second = FileNaming.availableURL(for: "a.txt", in: folder, isDirectory: false, exists: taken("a.txt"))
        #expect(second.lastPathComponent == "a (2).txt")

        let third = FileNaming.availableURL(
            for: "a.txt", in: folder, isDirectory: false, exists: taken("a.txt", "a (2).txt"))
        #expect(third.lastPathComponent == "a (3).txt")

        let directory = FileNaming.availableURL(
            for: "Nouveau dossier", in: folder, isDirectory: true, exists: taken("Nouveau dossier"))
        #expect(directory.lastPathComponent == "Nouveau dossier (2)")
    }

    @Test func copyNextToTheOriginalIsNamedLikeExplorer() {
        let first = FileNaming.copyURL(
            for: "a.txt", in: folder, isDirectory: false, suffix: " - Copie", exists: taken("a.txt"))
        #expect(first.lastPathComponent == "a - Copie.txt")

        let second = FileNaming.copyURL(
            for: "a.txt", in: folder, isDirectory: false, suffix: " - Copie", exists: taken("a.txt", "a - Copie.txt"))
        #expect(second.lastPathComponent == "a - Copie (2).txt")

        let directory = FileNaming.copyURL(
            for: "Photos", in: folder, isDirectory: true, suffix: " - Copie", exists: taken("Photos"))
        #expect(directory.lastPathComponent == "Photos - Copie")
    }
}
