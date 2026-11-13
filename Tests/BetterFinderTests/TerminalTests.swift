import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct TerminalLauncherTests {
    private func launcher(installed: Set<String>, preferred: String? = nil) -> TerminalLauncher {
        TerminalLauncher(
            locate: { id in installed.contains(id) ? URL(filePath: "/Applications/\(id).app") : nil },
            preferred: { preferred }
        )
    }

    @Test func automaticPicksTheFirstInstalledInOrder() {
        let terminal = launcher(installed: ["com.apple.Terminal", "dev.warp.Warp-Stable", "com.mitchellh.ghostty"])
        #expect(terminal.application()?.lastPathComponent == "com.mitchellh.ghostty.app")
        #expect(terminal.installed.map(\.name) == ["Ghostty", "Warp", "Terminal"])
    }

    @Test func theChosenTerminalWins() {
        let terminal = launcher(
            installed: ["com.apple.Terminal", "com.mitchellh.ghostty"],
            preferred: "com.apple.Terminal"
        )
        #expect(terminal.application()?.lastPathComponent == "com.apple.Terminal.app")
    }

    @Test func aChosenTerminalThatIsGoneFallsBackToAutomatic() {
        let terminal = launcher(installed: ["com.apple.Terminal"], preferred: "com.googlecode.iterm2")
        #expect(terminal.application()?.lastPathComponent == "com.apple.Terminal.app")
    }

    @Test func anEmptyChoiceIsAutomatic() {
        let terminal = launcher(installed: ["com.googlecode.iterm2"], preferred: "")
        #expect(terminal.application()?.lastPathComponent == "com.googlecode.iterm2.app")
    }

    @Test func noTerminalAtAll() {
        #expect(launcher(installed: []).application() == nil)
    }
}

@MainActor
@Suite struct BrowserModelTerminalTests {
    /// Temporary tree:  root/Alpha, root/notes.txt
    private func makeTree() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderTerminalTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Alpha"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appending(path: "notes.txt"))
        return BrowserModel.normalized(root)
    }

    private func startedModel(at url: URL) async throws -> BrowserModel {
        let model = BrowserModel(start: url)
        model.start()
        for _ in 0..<500 {
            if model.state != .loading { return model }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not finish loading")
        return model
    }

    @Test func withoutSelectionTheFolderShownIsUsed() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        #expect(model.terminalFolder == root)
        #expect(model.terminalFolderHere == root)
    }

    @Test func aSelectedFolderIsUsed() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)
        let alpha = root.appending(path: "Alpha")
        model.selection = [alpha]

        #expect(model.terminalFolder?.standardizedFileURL.path == alpha.standardizedFileURL.path)
        #expect(model.terminalFolderHere == root)
    }

    @Test func aSelectedFileGivesNoFolder() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)
        model.selection = [root.appending(path: "notes.txt")]

        #expect(model.terminalFolder == nil)
    }

    @Test func noTerminalOnTheComputersOverview() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await startedModel(at: root)

        model.showComputer()

        #expect(model.terminalFolder == nil)
        #expect(model.terminalFolderHere == nil)
    }
}
