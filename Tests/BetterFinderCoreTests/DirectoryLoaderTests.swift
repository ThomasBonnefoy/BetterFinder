import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct DirectoryLoaderTests {
    /// Creates an empty temporary folder, removed when the closure returns.
    private func withTemporaryFolder(_ body: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "BetterFinderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await body(folder)
    }

    @Test func listsFilesAndFolders() async throws {
        try await withTemporaryFolder { folder in
            try Data("hello".utf8).write(to: folder.appending(path: "note.txt"))
            try FileManager.default.createDirectory(
                at: folder.appending(path: "Sub"), withIntermediateDirectories: false)

            let listing = try await DirectoryLoader.load(folder)
            #expect(listing.isLocalVolume)
            #expect(listing.items.count == 2)

            let note = try #require(listing.items.first { $0.name == "note.txt" })
            #expect(!note.isDirectory)
            #expect(note.size == 5)
            #expect(note.modificationDate != nil)

            let sub = try #require(listing.items.first { $0.name == "Sub" })
            #expect(sub.isDirectory)
            #expect(sub.isBrowsable)
            #expect(sub.size == nil)
        }
    }

    @Test func reportsHiddenFiles() async throws {
        try await withTemporaryFolder { folder in
            try Data().write(to: folder.appending(path: ".secret"))
            try Data().write(to: folder.appending(path: "visible"))

            let listing = try await DirectoryLoader.load(folder)
            #expect(listing.items.first { $0.name == ".secret" }?.isHidden == true)
            #expect(listing.items.first { $0.name == "visible" }?.isHidden == false)
        }
    }

    @Test func linkToFolderIsBrowsable() async throws {
        try await withTemporaryFolder { folder in
            let target = folder.appending(path: "Target", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(
                at: folder.appending(path: "Link"), withDestinationURL: target)

            let listing = try await DirectoryLoader.load(folder)
            let link = try #require(listing.items.first { $0.name == "Link" })
            #expect(link.isBrowsable)
        }
    }

    @Test func missingFolderThrows() async {
        let missing = URL(filePath: "/nonexistent-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            _ = try await DirectoryLoader.load(missing)
        }
    }
}
