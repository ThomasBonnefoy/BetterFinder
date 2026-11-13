import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FolderSizeTests {
    private let files = FileManager.default
    private let root: URL

    /// root/{a.txt (3 bytes), Folder/{b.txt (5 bytes), Inner/c.txt (7 bytes), .hidden (2 bytes)}, Empty/}
    init() throws {
        root = files.temporaryDirectory
            .appending(path: "BetterFinderFolderSizeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Folder/Inner"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "Empty"), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: root.appending(path: "a.txt"))
        try Data("12345".utf8).write(to: root.appending(path: "Folder/b.txt"))
        try Data("1234567".utf8).write(to: root.appending(path: "Folder/Inner/c.txt"))
        try Data("hh".utf8).write(to: root.appending(path: "Folder/.hidden"))
    }

    @Test func addsUpAFolderRecursivelyHiddenFilesIncluded() async throws {
        defer { try? files.removeItem(at: root) }
        let measure = try #require(await FolderSize.measure([root.appending(path: "Folder")]))
        #expect(measure.bytes == 14)
        #expect(measure.files == 3)
        #expect(measure.folders == 1)
        #expect(measure.unreadable == 0)
    }

    @Test func allocatedSizeIsAtLeastTheSize() async throws {
        defer { try? files.removeItem(at: root) }
        let measure = try #require(await FolderSize.measure([root]))
        #expect(measure.allocatedBytes >= measure.bytes)
    }

    @Test func aFileCountsAsOneFileOfItsSize() async throws {
        defer { try? files.removeItem(at: root) }
        let measure = try #require(await FolderSize.measure([root.appending(path: "a.txt")]))
        #expect(measure == FolderMeasure(bytes: 3, allocatedBytes: measure.allocatedBytes, files: 1, folders: 0))
    }

    @Test func severalItemsAreAddedTogether() async throws {
        defer { try? files.removeItem(at: root) }
        let measure = try #require(await FolderSize.measure([root.appending(path: "a.txt"), root.appending(path: "Folder")]))
        #expect(measure.bytes == 17)
        #expect(measure.files == 4)
    }

    @Test func anEmptyFolderIsZero() async throws {
        defer { try? files.removeItem(at: root) }
        let measure = try #require(await FolderSize.measure([root.appending(path: "Empty")]))
        #expect(measure.bytes == 0)
        #expect(measure.files == 0)
        #expect(measure.folders == 0)
    }

    @Test func aSymbolicLinkIsNotFollowed() async throws {
        defer { try? files.removeItem(at: root) }
        try files.createSymbolicLink(at: root.appending(path: "Empty/link"), withDestinationURL: root.appending(path: "Folder"))
        let measure = try #require(await FolderSize.measure([root.appending(path: "Empty")]))
        #expect(measure.files == 1)
        #expect(measure.folders == 0)
    }

    @Test func aMissingItemIsReportedUnreadable() async {
        let measure = await FolderSize.measure([root.appending(path: "nope")])
        #expect(measure?.unreadable == 1)
    }
}

@Suite struct ItemInfoTests {
    @Test func readsAFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "BetterFinderInfo-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try #require(ItemInfo.read(url))
        #expect(info.name == url.lastPathComponent)
        #expect(info.fileSize == 5)
        #expect(!info.isFolder)
        #expect(!info.needsMeasuring)
        #expect(info.modified != nil)
    }

    @Test func aFolderNeedsMeasuring() throws {
        let url = FileManager.default.temporaryDirectory
        let info = try #require(ItemInfo.read(url))
        #expect(info.isFolder)
        #expect(info.needsMeasuring)
    }

    @Test func aMissingItemHasNoInfo() {
        #expect(ItemInfo.read(URL(filePath: "/nonexistent-\(UUID().uuidString)")) == nil)
    }
}
