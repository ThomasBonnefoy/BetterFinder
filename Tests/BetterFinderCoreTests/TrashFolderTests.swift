import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct TrashFolderTests {
    private let trash = URL(filePath: "/Users/test/.Trash")

    @Test func theTrashIsInTheHomeFolder() {
        #expect(TrashFolder.url.lastPathComponent == ".Trash")
        #expect(TrashFolder.url.deletingLastPathComponent().path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path)
    }

    @Test func tellsTheTrashFromWhatLiesInIt() {
        #expect(TrashFolder.isTrash(trash, trash: trash))
        #expect(TrashFolder.isTrash(URL(filePath: "/Users/test/.Trash/"), trash: trash))
        #expect(!TrashFolder.isTrash(URL(filePath: "/Users/test/.Trash/a"), trash: trash))
        #expect(TrashFolder.contains(trash, trash: trash))
        #expect(TrashFolder.contains(URL(filePath: "/Users/test/.Trash/a/b.txt"), trash: trash))
        // A sibling whose name starts the same is not in the Trash.
        #expect(!TrashFolder.contains(URL(filePath: "/Users/test/.Trash2/a"), trash: trash))
        #expect(!TrashFolder.contains(URL(filePath: "/Users/test/Documents"), trash: trash))
    }

    @Test func recognizesAMissingPermission() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        #expect(TrashFolder.isPermissionDenied(denied))
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        #expect(TrashFolder.isPermissionDenied(posix))
        // Hidden behind another error, as Cocoa reports it.
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSUnderlyingErrorKey: posix])
        #expect(TrashFolder.isPermissionDenied(wrapped))
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        #expect(!TrashFolder.isPermissionDenied(missing))
    }

    @Test func listsWhatEmptyingWouldDelete() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "BetterFinderTrashTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "Folder"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appending(path: "a.txt"))
        try Data("b".utf8).write(to: folder.appending(path: ".hidden"))
        try Data().write(to: folder.appending(path: ".DS_Store"))
        defer { try? FileManager.default.removeItem(at: folder) }

        let names = try await TrashFolder.contents(of: folder).map(\.lastPathComponent).sorted()
        #expect(names == [".hidden", "Folder", "a.txt"])
    }

    @Test func anUnreadableTrashThrows() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) { try await TrashFolder.contents(of: missing) }
    }
}
