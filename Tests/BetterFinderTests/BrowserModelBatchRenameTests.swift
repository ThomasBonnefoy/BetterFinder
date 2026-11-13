import AppKit
import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct BrowserModelBatchRenameTests {
    private let files = FileManager.default
    private let root: URL

    /// root/{a.txt, b.txt, c.png, keep.md}
    init() throws {
        let base = files.temporaryDirectory
            .appending(path: "BetterFinderModelBatchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: base, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.png", "keep.md"] {
            try Data(name.utf8).write(to: base.appending(path: name))
        }
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

    private func names() -> [String] { ((try? files.contentsOfDirectory(atPath: root.path)) ?? []).sorted() }

    @Test func severalSelectedItemsOpenTheBatchSheetInsteadOfInPlaceRenaming() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.selection = Set(model.items.filter { $0.name.hasSuffix(".txt") }.map(\.url))

        #expect(model.canBatchRename)
        model.renameSelection()

        #expect(model.renameRequest == nil)
        let request = try #require(model.batchRenameRequest)
        #expect(request.items.map(\.url.lastPathComponent) == ["a.txt", "b.txt"])
        #expect(request.namesInFolder.sorted() == ["a.txt", "b.txt", "c.png", "keep.md"])
    }

    @Test func oneSelectedItemStillRenamesInPlace() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.selection = [root.appending(path: "a.txt")]
        #expect(!model.canBatchRename)
        model.renameSelection()
        #expect(model.renameRequest?.url == root.appending(path: "a.txt"))
        #expect(model.batchRenameRequest == nil)
    }

    @Test func applyingTheSheetRenamesAndCanBeUndone() async throws {
        defer { try? files.removeItem(at: root) }
        let model = try await loadedModel()
        model.selection = Set(model.items.filter { $0.name != "keep.md" }.map(\.url))
        model.beginBatchRename()
        let request = try #require(model.batchRenameRequest)

        let plan = BatchRename.plan(
            for: request.items.map { ($0.url, $0.isDirectory) },
            rule: .sequence(name: "Photo", start: 1, digits: 2),
            namesInFolder: request.namesInFolder
        )
        #expect(plan.isValid)
        model.renameMany(plan.moves)
        try await settled(model)

        #expect(names() == ["Photo (01).txt", "Photo (02).txt", "Photo (03).png", "keep.md"])
        #expect(model.batchRenameRequest == nil)

        model.undoManager?.undo()
        try await settled(model)
        #expect(names() == ["a.txt", "b.txt", "c.png", "keep.md"])
    }
}
