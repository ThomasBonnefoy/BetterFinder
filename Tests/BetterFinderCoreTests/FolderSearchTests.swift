import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FolderSearchTests {
    private let files = FileManager.default
    private let root: URL

    /// root/Rapport.txt, root/Docs/Rapport annuel.pdf, root/Docs/été.txt,
    /// root/.caché-rapport, root/App.app/Contents/rapport.txt
    init() throws {
        root = files.temporaryDirectory
            .appending(path: "BetterFinderSearchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Docs"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "App.app/Contents"), withIntermediateDirectories: true)
        for path in ["Rapport.txt", "Docs/Rapport annuel.pdf", "Docs/été.txt", ".caché-rapport"] {
            try Data("x".utf8).write(to: root.appending(path: path))
        }
        try Data("x".utf8).write(to: root.appending(path: "App.app/Contents/rapport.txt"))
        // Makes the folder a package, like a real app bundle.
        try Data("x".utf8).write(to: root.appending(path: "App.app/Contents/Info.plist"))
    }

    private func search(_ query: String, showHidden: Bool = false) async -> [String] {
        var names: [String] = []
        for await batch in FolderSearch.results(in: root, query: query, showHidden: showHidden) {
            names += batch.map(\.url.lastPathComponent)
        }
        return names.sorted()
    }

    @Test func matchesIgnoreCaseAndAccents() {
        #expect(FolderSearch.matches("Été 2024.txt", terms: ["ete"]))
        #expect(FolderSearch.matches("RAPPORT.txt", terms: ["rapport"]))
        #expect(!FolderSearch.matches("notes.txt", terms: ["rapport"]))
        #expect(!FolderSearch.matches("notes.txt", terms: []))
    }

    @Test func everyWordMustMatch() {
        #expect(FolderSearch.matches("Rapport annuel.pdf", terms: ["annuel", "rapport"]))
        #expect(!FolderSearch.matches("Rapport.txt", terms: ["annuel", "rapport"]))
        #expect(FolderSearch.terms(from: "  a   b ") == ["a", "b"])
    }

    @Test func findsItemsInSubfolders() async {
        #expect(await search("rapport") == ["Rapport annuel.pdf", "Rapport.txt"])
    }

    @Test func ignoresAccents() async {
        #expect(await search("ete") == ["été.txt"])
    }

    @Test func hiddenItemsOnlyWhenAsked() async {
        #expect(await search("caché").isEmpty)
        #expect(await search("caché", showHidden: true) == [".caché-rapport"])
    }

    @Test func doesNotLookInsidePackages() async {
        let names = await search("rapport", showHidden: true)
        #expect(names.filter { $0 == "rapport.txt" }.isEmpty)
    }

    @Test func emptyQueryFindsNothing() async {
        #expect(await search("   ").isEmpty)
    }
}
