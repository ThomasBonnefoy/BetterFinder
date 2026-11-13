import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct ThumbnailPolicyTests {
    private func wants(_ name: String, directory: Bool = false) -> Bool {
        ThumbnailPolicy.wantsThumbnail(for: URL(filePath: "/tmp/\(name)"), isDirectory: directory)
    }

    @Test func imagesVideosAndPDFsShowTheirContent() {
        for name in ["a.png", "a.JPG", "a.jpeg", "a.heic", "a.gif", "a.webp", "a.mov", "a.mp4", "a.pdf"] {
            #expect(wants(name), "\(name) should have a thumbnail")
        }
    }

    @Test func otherFilesKeepTheirIcon() {
        for name in ["a.txt", "a.zip", "a.swift", "a.docx", "Makefile", "a.app", ".gitignore"] {
            #expect(!wants(name), "\(name) should keep its icon")
        }
    }

    @Test func aFolderNeverGetsAThumbnail() {
        #expect(!wants("photos.png", directory: true))
    }
}
