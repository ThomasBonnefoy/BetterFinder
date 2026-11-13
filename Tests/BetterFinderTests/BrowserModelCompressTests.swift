import AppKit
import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct BrowserModelCompressTests {
    private let files = FileManager.default
    private let root: URL

    init() throws {
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderModelZipTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: base.appending(path: "a.txt"))
        try Data("b".utf8).write(to: base.appending(path: "b.txt"))
        root = BrowserModel.normalized(base)
    }

    private func settled(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            try await Task.sleep(for: .milliseconds(10))
            if model.state != .loading, model.activity == nil, model.pendingLoads == 0 { return }
        }
        Issue.record("The model did not settle")
    }

    private func loadedModel() async throws -> BrowserModel {
        let model = BrowserModel(start: root, clipboard: FileClipboard(pasteboard: NSPasteboard(name: .init("bf-tests-\(UUID().uuidString)"))))
        model.undoManager = UndoManager()
        model.start()
        try await settled(model)
        return model
    }

    @Test func compressingTheSelectionCreatesAndSelectsAnArchive() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.selection = Set(model.items.map(\.url))
        #expect(model.canCompressSelection)

        model.compressSelection()
        try await settled(model)

        #expect(files.fileExists(atPath: root.appending(path: "Archive.zip").path))
        #expect(model.selection == [root.appending(path: "Archive.zip")])
    }

    @Test func nothingSelectedMeansNothingToCompress() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        #expect(!model.canCompressSelection)
        model.compressSelection()
        try await settled(model)
        #expect(model.items.count == 2)
    }

    @Test func undoingPutsTheArchiveInTheTrash() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.selection = Set(model.items.filter { $0.name == "a.txt" }.map(\.url))
        model.compressSelection()
        try await settled(model)
        #expect(files.fileExists(atPath: root.appending(path: "a.txt.zip").path))

        model.undoManager?.undo()
        try await settled(model)

        #expect(!files.fileExists(atPath: root.appending(path: "a.txt.zip").path))
    }
}
