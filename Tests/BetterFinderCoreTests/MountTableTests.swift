import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct MountTableTests {
    private func drive(_ address: String) -> NetworkDrive {
        NetworkDrive(name: "Test", url: URL(string: address)!)
    }

    private func smb(_ source: String, at mountPoint: String) -> MountEntry {
        MountEntry(source: source, mountPoint: mountPoint, fileSystem: "smbfs")
    }

    private let localDisk = MountEntry(source: "/dev/disk3s1s1", mountPoint: "/", fileSystem: "apfs")

    @Test func readsTheRealMountTable() {
        let entries = MountTable.current()
        #expect(entries.contains { $0.mountPoint == "/" })
        #expect(entries.allSatisfy { !$0.fileSystem.isEmpty })
    }

    @Test func findsAnSMBShare() {
        let entries = [localDisk, smb("//someone@nas/commun", at: "/Volumes/commun")]
        let match = MountTable.match(for: drive("smb://nas/commun"), in: entries)
        #expect(match?.volume.path == "/Volumes/commun")
        #expect(match?.folder.path == "/Volumes/commun")
    }

    @Test func ignoresCaseUserDomainAndPort() {
        let entries = [smb("//CORP;Some.One:secret@NAS.Example.org:445/Commun", at: "/Volumes/Commun")]
        #expect(MountTable.match(for: drive("smb://nas.example.org/commun"), in: entries)?.volume.path == "/Volumes/Commun")
    }

    @Test func decodesPercentEscapes() {
        let entries = [smb("//someone@nas/Team%20A", at: "/Volumes/Team A")]
        #expect(MountTable.match(for: drive("smb://nas/Team%20A"), in: entries)?.volume.path == "/Volumes/Team A")
    }

    @Test func driveInsideAMountedShareOpensItsFolder() {
        let entries = [smb("//someone@nas/data", at: "/Volumes/data")]
        let match = MountTable.match(for: drive("smb://nas/data/Projects/2026"), in: entries)
        #expect(match?.volume.path == "/Volumes/data")
        #expect(match?.folder.path == "/Volumes/data/Projects/2026")
    }

    @Test func otherServersSharesAndFileSystemsDoNotMatch() {
        let wanted = drive("smb://nas/commun")
        #expect(MountTable.match(for: wanted, in: [localDisk]) == nil)
        #expect(MountTable.match(for: wanted, in: [smb("//someone@other/commun", at: "/Volumes/commun")]) == nil)
        #expect(MountTable.match(for: wanted, in: [smb("//someone@nas/commun2", at: "/Volumes/commun2")]) == nil)
        #expect(MountTable.match(for: wanted, in: [smb("//someone@nas/com", at: "/Volumes/com")]) == nil)
        let afp = MountEntry(source: "//someone@nas/commun", mountPoint: "/Volumes/commun", fileSystem: "afpfs")
        #expect(MountTable.match(for: wanted, in: [afp]) == nil)
    }

    @Test func findsAnNFSExport() {
        let entries = [MountEntry(source: "server:/export/data", mountPoint: "/Volumes/data", fileSystem: "nfs")]
        #expect(MountTable.match(for: drive("nfs://server/export/data"), in: entries)?.volume.path == "/Volumes/data")
    }
}
