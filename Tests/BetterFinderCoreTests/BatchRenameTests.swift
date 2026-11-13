import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct BatchRenameTests {
    private let folder = URL(filePath: "/tmp/batch", directoryHint: .isDirectory)

    private func items(_ names: String...) -> [(url: URL, isDirectory: Bool)] {
        names.map { (folder.appending(path: $0), false) }
    }

    private func newNames(_ plan: BatchRename.Plan) -> [String] { plan.entries.map(\.newName) }

    // MARK: - Rules

    @Test func aSequenceNumbersTheItemsAndKeepsTheirExtensions() {
        let plan = BatchRename.plan(
            for: items("IMG_1.jpg", "IMG_2.png", "notes"),
            rule: .sequence(name: "Vacances", start: 1, digits: 1),
            namesInFolder: ["IMG_1.jpg", "IMG_2.png", "notes"]
        )
        #expect(newNames(plan) == ["Vacances (1).jpg", "Vacances (2).png", "Vacances (3)"])
        #expect(plan.isValid)
    }

    @Test func aSequenceCanStartLaterAndBePadded() {
        let plan = BatchRename.plan(
            for: items("a.txt", "b.txt"),
            rule: .sequence(name: "Page", start: 9, digits: 3),
            namesInFolder: ["a.txt", "b.txt"]
        )
        #expect(newNames(plan) == ["Page (009).txt", "Page (010).txt"])
    }

    @Test func replaceActsOnTheBaseNameOnly() {
        let plan = BatchRename.plan(
            for: items("photo.photo", "photo_2.jpg"),
            rule: .replace(find: "photo", with: "pic", caseSensitive: true),
            namesInFolder: []
        )
        // "photo.photo" has the extension "photo": only the base changes.
        #expect(newNames(plan) == ["pic.photo", "pic_2.jpg"])
    }

    @Test func replaceIgnoresCaseUnlessAsked() {
        let insensitive = BatchRename.plan(
            for: items("Foo.txt"), rule: .replace(find: "foo", with: "bar", caseSensitive: false), namesInFolder: [])
        let sensitive = BatchRename.plan(
            for: items("Foo.txt"), rule: .replace(find: "foo", with: "bar", caseSensitive: true), namesInFolder: [])
        #expect(newNames(insensitive) == ["bar.txt"])
        #expect(newNames(sensitive) == ["Foo.txt"])
        #expect(!sensitive.changesSomething)
    }

    @Test func anEmptySearchChangesNothing() {
        let plan = BatchRename.plan(
            for: items("a.txt"), rule: .replace(find: "", with: "x", caseSensitive: false), namesInFolder: [])
        #expect(!plan.changesSomething)
    }

    @Test func affixAddsTextAroundTheBaseName() {
        let plan = BatchRename.plan(
            for: items("a.txt", "b"), rule: .affix(prefix: "2026-", suffix: "_v2"), namesInFolder: [])
        #expect(newNames(plan) == ["2026-a_v2.txt", "2026-b_v2"])
    }

    @Test func foldersHaveNoExtensionToKeep() {
        let plan = BatchRename.plan(
            for: [(folder.appending(path: "v1.2"), true)],
            rule: .affix(prefix: "", suffix: "-old"), namesInFolder: [])
        #expect(newNames(plan) == ["v1.2-old"])
    }

    // MARK: - Checks

    @Test func twoItemsCannotGetTheSameName() {
        // Removing the "a" turns both "ab.txt" and "ba.txt" into "b.txt".
        let plan = BatchRename.plan(
            for: items("ab.txt", "ba.txt"),
            rule: .replace(find: "a", with: "", caseSensitive: true),
            namesInFolder: ["ab.txt", "ba.txt"]
        )
        #expect(plan.entries.map(\.problem) == [.duplicate, .duplicate])
        #expect(!plan.isValid)
    }

    @Test func aNameUsedByAnItemLeftAloneIsRefused() {
        let plan = BatchRename.plan(
            for: items("a.txt"),
            rule: .affix(prefix: "", suffix: "2"),
            namesInFolder: ["a.txt", "a2.txt"]
        )
        #expect(plan.entries[0].problem == .taken)
    }

    @Test func takingTheNameOfAnotherRenamedItemIsFine() {
        // "a.txt" becomes "aa.txt", the current name of the next item, which
        // itself becomes "aaa.txt": a chain, not a clash.
        let plan = BatchRename.plan(
            for: items("a.txt", "aa.txt"),
            rule: .affix(prefix: "a", suffix: ""),
            namesInFolder: ["a.txt", "aa.txt"]
        )
        #expect(newNames(plan) == ["aa.txt", "aaa.txt"])
        #expect(plan.isValid)
    }

    @Test func anEmptyResultIsRefused() {
        let plan = BatchRename.plan(
            for: items("a"), rule: .replace(find: "a", with: "", caseSensitive: true), namesInFolder: [])
        #expect(plan.entries[0].problem == .invalidName(.empty))
    }

    @Test func forbiddenCharactersAreRefused() {
        let plan = BatchRename.plan(
            for: items("a.txt"), rule: .affix(prefix: "x/", suffix: ""), namesInFolder: [])
        #expect(plan.entries[0].problem == .invalidName(.forbiddenCharacter))
    }

    @Test func onlyChangedItemsAreMoved() {
        let plan = BatchRename.plan(
            for: items("keep.txt", "a.txt"),
            rule: .replace(find: "a", with: "z", caseSensitive: true),
            namesInFolder: [])
        #expect(plan.moves == [FileMove(from: folder.appending(path: "a.txt"), to: folder.appending(path: "z.txt"))])
    }
}
