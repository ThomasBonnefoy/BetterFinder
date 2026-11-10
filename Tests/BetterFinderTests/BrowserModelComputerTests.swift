import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct BrowserModelComputerTests {
    /// Temporary tree:  root/Alpha, root/notes.txt
    private func makeTree() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderComputerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Alpha"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appending(path: "notes.txt"))
        return BrowserModel.normalized(root)
    }

    private func loaded(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            if model.state != .loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not finish loading")
    }

    private func startedModel(at url: URL) async throws -> BrowserModel {
        let model = BrowserModel(start: url)
        model.start()
        try await loaded(model)
        return model
    }

    @Test func showingTheComputerLeavesTheFolder() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)
        model.selection = [root.appending(path: "Alpha")]

        model.showComputer()

        #expect(model.location == .computer)
        #expect(model.isOnComputer)
        #expect(model.currentURL == nil)
        #expect(model.displayedDriveID == nil)
        #expect(model.title == "Ce Mac")
        #expect(model.addressText == "Ce Mac")
        #expect(model.items.isEmpty)
        #expect(model.selection.isEmpty)
        #expect(!model.canGoUp)
        #expect(model.canGoBack)
    }

    @Test func goingBackFromTheComputerReturnsToTheFolder() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        model.showComputer()
        model.goBack()
        try await loaded(model)

        #expect(model.currentURL == root)
        #expect(model.items.map(\.name) == ["Alpha", "notes.txt"])
        #expect(model.canGoForward)

        model.goForward()
        #expect(model.isOnComputer)
    }

    @Test func showingTheComputerTwiceAddsOneHistoryStep() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        model.showComputer()
        model.showComputer()
        model.goBack()
        try await loaded(model)

        #expect(model.currentURL == root)
        #expect(!model.canGoBack)
    }

    @Test func goingUpFromADiskLeadsToTheComputer() async throws {
        let model = try await startedModel(at: URL(filePath: "/"))
        #expect(model.canGoUp)

        model.goUp()
        #expect(model.isOnComputer)

        model.goBack()
        try await loaded(model)
        #expect(model.currentURL == URL(filePath: "/", directoryHint: .notDirectory))
    }

    @Test func goingUpFromAFolderStillLeadsToItsParent() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root.appending(path: "Alpha"))

        model.goUp()
        try await loaded(model)
        #expect(model.currentURL == root)
    }

    @Test func addressBarAcceptsTheComputerName() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        model.beginEditingAddress()
        #expect(model.submitAddress("  ce mac "))
        #expect(model.isOnComputer)
        #expect(!model.isEditingAddress)

        // And a path typed from there is still understood.
        #expect(model.submitAddress(root.path))
        try await loaded(model)
        #expect(model.currentURL == root)
    }

    @Test func fileCommandsDoNothingOnTheComputer() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = FileClipboard(pasteboard: .withUniqueName())
        let model = BrowserModel(start: root, clipboard: clipboard)
        model.start()
        try await loaded(model)
        clipboard.copy([root.appending(path: "notes.txt")])
        #expect(model.canPaste)

        model.showComputer()
        #expect(!model.canPaste)
        model.newFolder()
        model.paste()
        #expect(model.activity == nil)
    }

    @Test func reloadRefreshesTheOverview() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)
        model.showComputer()

        let before = model.computerRefreshes
        model.reload()
        #expect(model.computerRefreshes == before + 1)
        #expect(model.isOnComputer)
    }

    @Test func windowCanStartOnTheComputer() async throws {
        let model = BrowserModel(start: FileManager.default.homeDirectoryForCurrentUser)
        model.start(onComputer: true)

        #expect(model.isOnComputer)
        #expect(!model.canGoBack)
        #expect(model.state == .loaded)
    }

    @Test func capacityWording() {
        let disk = VolumeInfo(
            url: URL(filePath: "/"), name: "Macintosh HD", isLocal: true, isEjectable: false,
            totalCapacity: 500_000_000_000, availableCapacity: 120_000_000_000
        )
        let text = ComputerView.capacityText(for: disk)
        #expect(text?.contains("libres sur") == true)
        #expect(text?.hasPrefix("120") == true)

        let unknown = VolumeInfo(url: URL(filePath: "/Volumes/x"), name: "x", isLocal: false, isEjectable: false)
        #expect(ComputerView.capacityText(for: unknown) == nil)
    }
}
