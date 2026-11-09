import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct PathParserTests {
    private let base = URL(filePath: "/Users/someone/Documents", directoryHint: .isDirectory)
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    private func parse(_ text: String) -> ParsedPath {
        PathParser.parse(text, relativeTo: base, home: home)
    }

    private func localPath(_ text: String) -> String? {
        if case .local(let url) = parse(text) { return url.path }
        return nil
    }

    @Test func absolutePath() {
        #expect(localPath("/Applications") == "/Applications")
        #expect(localPath("  /Applications/Utilities/  ") == "/Applications/Utilities")
    }

    @Test func tildeExpandsToHome() {
        #expect(localPath("~") == "/Users/someone")
        #expect(localPath("~/Downloads") == "/Users/someone/Downloads")
    }

    @Test func relativePathUsesTheCurrentFolder() {
        #expect(localPath("Work/2026") == "/Users/someone/Documents/Work/2026")
        #expect(localPath("..") == "/Users/someone")
        #expect(localPath("../Desktop") == "/Users/someone/Desktop")
    }

    @Test func dotSegmentsAreResolved() {
        #expect(localPath("/Users/someone/./Documents/../Music") == "/Users/someone/Music")
    }

    @Test func quotesAreStripped() {
        #expect(localPath("\"/Applications\"") == "/Applications")
        #expect(localPath("'~/My Folder'") == "/Users/someone/My Folder")
    }

    @Test func fileURL() {
        #expect(localPath("file:///Applications/Safari.app") == "/Applications/Safari.app")
    }

    @Test func networkURLIsRemote() {
        #expect(parse("smb://nas.local/share") == .remote(URL(string: "smb://nas.local/share")!))
        #expect(parse("SMB://nas.local/share") == .remote(URL(string: "SMB://nas.local/share")!))
        #expect(parse("afp://server/volume") == .remote(URL(string: "afp://server/volume")!))
    }

    @Test func windowsUNCPathBecomesSMB() {
        #expect(parse(#"\\nas\share"#) == .remote(URL(string: "smb://nas/share")!))
        #expect(parse(#"\\nas\share\Folder\Sub"#) == .remote(URL(string: "smb://nas/share/Folder/Sub")!))
    }

    @Test func invalidInput() {
        #expect(parse("") == .invalid)
        #expect(parse("   ") == .invalid)
        #expect(parse(#"\\server"#) == .invalid)
        #expect(parse("smb://") == .invalid)
        #expect(parse("gopher://host/x") == .invalid)
    }
}
