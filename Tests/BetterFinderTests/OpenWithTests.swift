import AppKit
import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct OpenWithTests {
    private let files = FileManager.default
    private let root: URL

    /// root/{a.txt, b.txt, Folder/}
    init() throws {
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderOpenWithTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base.appending(path: "Folder"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: base.appending(path: "a.txt"))
        try Data("b".utf8).write(to: base.appending(path: "b.txt"))
        root = BrowserModel.normalized(base)
    }

    private func loadedModel() async throws -> BrowserModel {
        let model = BrowserModel(start: root, clipboard: FileClipboard(pasteboard: NSPasteboard(name: .init("bf-tests-\(UUID().uuidString)"))))
        model.start()
        for _ in 0..<500 {
            try await Task.sleep(for: .milliseconds(10))
            if model.state != .loading, model.pendingLoads == 0 { break }
        }
        return model
    }

    @Test func listsTheApplicationsOfTheFirstFile() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        let editor = OpenWithApp(url: URL(filePath: "/Applications/Edit.app"), name: "Edit", isDefault: true)
        var asked: [URL] = []
        model.openWith = OpenWith(applications: { asked.append($0); return [editor] }, open: { _, _ in })

        model.selection = Set(model.items.filter { $0.name == "a.txt" || $0.name == "b.txt" }.map(\.url))
        let apps = model.applicationsForSelection()

        #expect(apps == [editor])
        #expect(asked.count == 1)
    }

    @Test func opensEverySelectedFileWithTheChosenApplication() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        var opened: ([URL], URL)?
        model.openWith = OpenWith(applications: { _ in [] }, open: { opened = ($0, $1) })

        model.selection = Set(model.items.filter { $0.name.hasSuffix(".txt") }.map(\.url))
        let app = URL(filePath: "/Applications/Edit.app")
        model.openSelection(with: app)

        #expect(opened?.1 == app)
        #expect(Set(opened?.0 ?? []) == model.selection)
    }

    @Test func aFolderCannotBeOpenedWithAnApplication() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        var calls = 0
        model.openWith = OpenWith(applications: { _ in calls += 1; return [] }, open: { _, _ in calls += 1 })

        model.selection = Set(model.items.map(\.url))  // files and a folder together
        #expect(model.filesToOpenWith.isEmpty)
        model.openSelection(with: URL(filePath: "/Applications/Edit.app"))

        #expect(calls == 0)
    }
}

@MainActor
@Suite struct PropertiesRequestTests {
    private let files = FileManager.default
    private let root: URL

    init() throws {
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderPropertiesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: base.appending(path: "a.txt"))
        root = BrowserModel.normalized(base)
    }

    private func loadedModel() async throws -> BrowserModel {
        let model = BrowserModel(start: root, clipboard: FileClipboard(pasteboard: NSPasteboard(name: .init("bf-tests-\(UUID().uuidString)"))))
        model.start()
        for _ in 0..<500 {
            try await Task.sleep(for: .milliseconds(10))
            if model.state != .loading, model.pendingLoads == 0 { break }
        }
        return model
    }

    @Test func withNothingSelectedItDescribesTheFolderShown() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.showProperties()
        #expect(model.propertiesRequest?.urls == [root])
    }

    @Test func withASelectionItDescribesTheSelection() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.selection = Set(model.items.map(\.url))
        model.showProperties()
        #expect(model.propertiesRequest?.urls == model.items.map(\.url))
    }

    @Test func theComputerOverviewHasNoProperties() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.showComputer()
        model.showProperties()
        #expect(model.propertiesRequest == nil)
    }

    @Test func bigSizesAlsoGiveTheExactByteCount() {
        // The exact count is in parentheses; a small size has nothing to add.
        #expect(PropertiesView.sizeDescription(2_000_000).contains("("))
        #expect(!PropertiesView.sizeDescription(500).contains("("))
    }

    @Test func spaceOnDiskIsMentionedOnlyWhenItDiffers() {
        #expect(PropertiesView.sizeDescription(5000, allocated: 8192).contains("sur le disque"))
        #expect(!PropertiesView.sizeDescription(5000, allocated: 5000).contains("sur le disque"))
    }

    @Test func countsAreWrittenInThePlural() {
        #expect(PropertiesView.plural(1, "fichier") == "1 fichier")
        #expect(PropertiesView.plural(3, "dossier") == "3 dossiers")
    }
}
