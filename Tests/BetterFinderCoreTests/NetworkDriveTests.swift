import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct NetworkDriveTests {
    @Test func addressFormsAllGiveAnSMBURL() {
        #expect(NetworkDrive.url(fromAddress: "smb://nas/share") == URL(string: "smb://nas/share"))
        #expect(NetworkDrive.url(fromAddress: #"\\nas\share"#) == URL(string: "smb://nas/share"))
        #expect(NetworkDrive.url(fromAddress: "  nas/share  ") == URL(string: "smb://nas/share"))
        #expect(NetworkDrive.url(fromAddress: "nas.example.org/Data/Team") == URL(string: "smb://nas.example.org/Data/Team"))
    }

    @Test func otherProtocolsAreKept() {
        #expect(NetworkDrive.url(fromAddress: "afp://server/Volume") == URL(string: "afp://server/Volume"))
        #expect(NetworkDrive.url(fromAddress: "nfs://server/export/data") == URL(string: "nfs://server/export/data"))
    }

    @Test func addressWithoutAShareIsRejected() {
        #expect(NetworkDrive.url(fromAddress: "") == nil)
        #expect(NetworkDrive.url(fromAddress: "smb://nas") == nil)
        #expect(NetworkDrive.url(fromAddress: "smb://nas/") == nil)
        #expect(NetworkDrive.url(fromAddress: "nas") == nil)
        #expect(NetworkDrive.url(fromAddress: "/Users/someone") == nil)
        #expect(NetworkDrive.url(fromAddress: "~/Documents") == nil)
    }

    @Test func hostPortAndSharePath() {
        let drive = NetworkDrive(name: "Team", url: URL(string: "smb://NAS.Example.org/Data/Team%20A/")!)
        #expect(drive.host == "nas.example.org")
        #expect(drive.port == 445)
        #expect(drive.sharePath == "Data/Team A")

        #expect(NetworkDrive(name: "x", url: URL(string: "afp://s/v")!).port == 548)
        #expect(NetworkDrive(name: "x", url: URL(string: "nfs://s/v")!).port == 2049)
        #expect(NetworkDrive(name: "x", url: URL(string: "smb://s:4455/v")!).port == 4455)
    }

    @Test func suggestedNameIsTheLastFolder() {
        #expect(NetworkDrive.suggestedName(for: URL(string: "smb://nas/share")!) == "share")
        #expect(NetworkDrive.suggestedName(for: URL(string: "smb://nas/Data/Team%20A")!) == "Team A")
    }
}

@Suite struct NetworkDriveStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "BetterFinderStoreTests-\(UUID().uuidString)/nested/drives.json")
    }

    @Test func missingFileMeansNoDrive() throws {
        #expect(try NetworkDriveStore(fileURL: temporaryFile()).load().isEmpty)
    }

    @Test func savedDrivesAreReadBack() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = NetworkDriveStore(fileURL: file)
        let drives = [
            NetworkDrive(name: "Commun", url: URL(string: "smb://nas/commun")!, username: "someone", reconnectAutomatically: true),
            NetworkDrive(name: "Perso", url: URL(string: "smb://nas/home/someone")!),
        ]

        try store.save(drives)
        #expect(try store.load() == drives)
    }

    @Test func noPasswordFieldIsEverWritten() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = NetworkDriveStore(fileURL: file)
        try store.save([NetworkDrive(name: "A", url: URL(string: "smb://nas/a")!, username: "someone")])

        let text = try String(contentsOf: file, encoding: .utf8).lowercased()
        #expect(!text.contains("password"))
        #expect(text.contains("smb://nas/a"))
    }

    @Test func corruptedFileThrows() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(throws: (any Error).self) {
            _ = try NetworkDriveStore(fileURL: file).load()
        }
    }
}
