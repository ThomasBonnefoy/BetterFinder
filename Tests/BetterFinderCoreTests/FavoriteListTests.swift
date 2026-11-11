import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FavoriteListTests {
    private func url(_ name: String) -> URL { URL(filePath: "/tmp/\(name)") }
    private func names(_ list: FavoriteList) -> [String] { list.urls.map(\.lastPathComponent) }

    private func list(_ names: String...) -> FavoriteList {
        FavoriteList(names.map(url))
    }

    @Test func addsAtTheEndWithoutDuplicates() {
        var favorites = list("a", "b")
        let added = favorites.add(url("c"))
        let duplicate = favorites.add(url("a"))
        let sameWithSlash = favorites.add(URL(filePath: "/tmp/a/"))
        #expect(added)
        #expect(!duplicate)
        #expect(!sameWithSlash)
        #expect(names(favorites) == ["a", "b", "c"])
    }

    @Test func insertsAtAPosition() {
        var favorites = list("a", "b")
        favorites.insert(url("x"), at: 1)
        favorites.insert(url("y"), at: 99)
        favorites.insert(url("z"), at: -4)
        #expect(names(favorites) == ["z", "a", "x", "b", "y"])
    }

    @Test func removes() {
        var favorites = list("a", "b", "c")
        favorites.remove(url("b"))
        favorites.remove(url("nope"))
        #expect(names(favorites) == ["a", "c"])
        #expect(!favorites.contains(url("b")))
    }

    @Test func movesDown() {
        var favorites = list("a", "b", "c", "d")
        favorites.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(names(favorites) == ["b", "c", "a", "d"])
    }

    @Test func movesUp() {
        var favorites = list("a", "b", "c", "d")
        favorites.move(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        #expect(names(favorites) == ["a", "d", "b", "c"])
    }

    @Test func movesToTheEndAndTheStart() {
        var favorites = list("a", "b", "c")
        favorites.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(names(favorites) == ["b", "c", "a"])
        favorites.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(names(favorites) == ["a", "b", "c"])
    }

    @Test func movesSeveralAtOnce() {
        var favorites = list("a", "b", "c", "d", "e")
        favorites.move(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        #expect(names(favorites) == ["b", "d", "e", "a", "c"])
    }

    @Test func movesNextToAnotherFavorite() {
        var favorites = list("a", "b", "c", "d")
        favorites.move(url("d"), relativeTo: url("b"), after: false)
        #expect(names(favorites) == ["a", "d", "b", "c"])
        favorites.move(url("a"), relativeTo: url("c"), after: true)
        #expect(names(favorites) == ["d", "b", "c", "a"])
        favorites.move(url("b"), relativeTo: url("b"), after: true)
        favorites.move(url("zzz"), relativeTo: url("b"), after: true)
        favorites.move(url("b"), relativeTo: url("zzz"), after: true)
        #expect(names(favorites) == ["d", "b", "c", "a"])
    }

    @Test func moveByOneStep() {
        var favorites = list("a", "b", "c")
        favorites.moveDown(url("a"))
        #expect(names(favorites) == ["b", "a", "c"])
        favorites.moveUp(url("c"))
        #expect(names(favorites) == ["b", "c", "a"])
        #expect(!favorites.canMoveUp(url("b")))
        #expect(!favorites.canMoveDown(url("a")))
        favorites.moveUp(url("b"))
        favorites.moveDown(url("a"))
        #expect(names(favorites) == ["b", "c", "a"])
    }

    @Test func standardListStartsAtHome() {
        let standard = FavoriteList.standard()
        #expect(standard.urls.first?.path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)
        #expect(standard.urls.count == 5)
    }

    @Test func fileRoundTripAndReset() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "BetterFinderFavoritesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = FavoriteFile(fileURL: folder.appending(path: "favorites.json"))

        #expect(try file.load() == nil)
        let favorites = list("b", "a")
        try file.save(favorites)
        #expect(try file.load() == favorites)
        try file.reset()
        #expect(try file.load() == nil)
    }
}
