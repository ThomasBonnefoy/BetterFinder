import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct BreadcrumbsTests {
    @Test func rootHasASingleCrumb() {
        let crumbs = Breadcrumbs.make(for: URL(filePath: "/"))
        #expect(crumbs.map(\.name) == ["/"])
        #expect(crumbs.map(\.url.path) == ["/"])
    }

    @Test func pathOnTheStartupDisk() {
        let crumbs = Breadcrumbs.make(for: URL(filePath: "/Users/someone/Documents"))
        #expect(crumbs.map(\.name) == ["/", "Users", "someone", "Documents"])
        #expect(crumbs.map(\.url.path) == ["/", "/Users", "/Users/someone", "/Users/someone/Documents"])
    }

    @Test func pathOnAnotherVolumeStartsAtTheVolume() {
        let crumbs = Breadcrumbs.make(for: URL(filePath: "/Volumes/Backup/Photos/2026"))
        #expect(crumbs.map(\.name) == ["Backup", "Photos", "2026"])
        #expect(crumbs.first?.url.path == "/Volumes/Backup")
        #expect(crumbs.last?.url.path == "/Volumes/Backup/Photos/2026")
    }

    @Test func volumesFolderItselfIsAPlainFolder() {
        let crumbs = Breadcrumbs.make(for: URL(filePath: "/Volumes"))
        #expect(crumbs.map(\.name) == ["/", "Volumes"])
    }
}
