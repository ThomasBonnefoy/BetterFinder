import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct FileSortingTests {
    private func file(_ name: String, size: Int64 = 0, date: TimeInterval = 0, kind: String = "") -> FileItem {
        FileItem(
            url: URL(filePath: "/tmp/\(name)"),
            name: name,
            isDirectory: false,
            size: size,
            modificationDate: Date(timeIntervalSince1970: date),
            kind: kind
        )
    }

    private func folder(_ name: String, date: TimeInterval = 0) -> FileItem {
        FileItem(
            url: URL(filePath: "/tmp/\(name)"),
            name: name,
            isDirectory: true,
            modificationDate: Date(timeIntervalSince1970: date),
            kind: "Dossier"
        )
    }

    @Test func foldersComeFirstInBothDirections() {
        let items = [file("a.txt"), folder("zeta"), file("b.txt"), folder("alpha")]

        let ascending = items.sorted(by: FileSort(key: .name, ascending: true)).map(\.name)
        #expect(ascending == ["alpha", "zeta", "a.txt", "b.txt"])

        let descending = items.sorted(by: FileSort(key: .name, ascending: false)).map(\.name)
        #expect(descending == ["zeta", "alpha", "b.txt", "a.txt"])
    }

    @Test func namesSortNaturally() {
        let items = [file("file10.txt"), file("file2.txt"), file("File1.txt")]
        let sorted = items.sorted(by: FileSort(key: .name, ascending: true)).map(\.name)
        #expect(sorted == ["File1.txt", "file2.txt", "file10.txt"])
    }

    @Test func sortsBySize() {
        let items = [file("big", size: 300), file("small", size: 1), file("medium", size: 20)]
        #expect(items.sorted(by: FileSort(key: .size, ascending: true)).map(\.name) == ["small", "medium", "big"])
        #expect(items.sorted(by: FileSort(key: .size, ascending: false)).map(\.name) == ["big", "medium", "small"])
    }

    @Test func sortsByDate() {
        let items = [file("new", date: 300), file("old", date: 1), folder("dir", date: 999)]
        let sorted = items.sorted(by: FileSort(key: .dateModified, ascending: false)).map(\.name)
        #expect(sorted == ["dir", "new", "old"])
    }

    @Test func tiesFallBackToNameWhateverTheDirection() {
        let items = [file("b.png", kind: "Image"), file("a.png", kind: "Image"), file("c.txt", kind: "Texte")]
        #expect(items.sorted(by: FileSort(key: .kind, ascending: true)).map(\.name) == ["a.png", "b.png", "c.txt"])
        #expect(items.sorted(by: FileSort(key: .kind, ascending: false)).map(\.name) == ["c.txt", "a.png", "b.png"])
    }

    @Test func packagesSortWithFiles() {
        let app = FileItem(url: URL(filePath: "/tmp/App.app"), name: "App.app", isDirectory: true, isPackage: true)
        let items = [file("zzz.txt"), app, folder("mmm")]
        let sorted = items.sorted(by: FileSort(key: .name, ascending: true)).map(\.name)
        #expect(sorted == ["mmm", "App.app", "zzz.txt"])
    }
}
