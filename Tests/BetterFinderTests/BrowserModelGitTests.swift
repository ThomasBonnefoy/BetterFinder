import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite(.serialized) struct BrowserModelGitTests {
    private func git(_ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = try #require(GitReader.executable)
        process.arguments = ["-C", folder.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// Temporary tree: root/plain, and a repository root/repo with one
    /// commit holding repo/Sources/kept.txt and repo/readme.txt.
    private func makeTree() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderGitModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repo = root.appending(path: "repo")
        try files.createDirectory(at: root.appending(path: "plain"), withIntermediateDirectories: true)
        try files.createDirectory(at: repo.appending(path: "Sources"), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: repo.appending(path: "Sources/kept.txt"))
        try Data("one".utf8).write(to: repo.appending(path: "readme.txt"))
        try git(["init", "-q", "-b", "main"], in: repo)
        try git(["add", "."], in: repo)
        try git([
            "-c", "user.name=Test", "-c", "user.email=test@example.com",
            "-c", "commit.gpgsign=false", "commit", "-q", "-m", "first",
        ], in: repo)
        return BrowserModel.normalized(root)
    }

    /// Waits until the folder is listed and Git has answered.
    private func settled(_ model: BrowserModel) async throws {
        for _ in 0..<500 {
            if model.state != .loading, model.pendingLoads == 0, model.pendingGitReads == 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The folder did not settle")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The expected state never came")
    }

    @Test func showsTheBranchInsideARepositoryOnly() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BrowserModel(start: root.appending(path: "repo"))
        model.start()
        try await settled(model)

        let info = try #require(model.gitInfo)
        #expect(info.status.branch == "main")
        #expect(info.status.isClean)
        #expect(info.root.path == root.appending(path: "repo").path)

        // A sub-folder belongs to the same working tree.
        model.navigate(to: root.appending(path: "repo/Sources"))
        #expect(model.gitInfo != nil)
        try await settled(model)
        #expect(model.gitInfo?.status.branch == "main")

        // Out of the repository, nothing is shown.
        model.navigate(to: root.appending(path: "plain"))
        #expect(model.gitInfo == nil)
        try await settled(model)
        #expect(model.gitInfo == nil)
    }

    @Test func marksChangedFilesAndTheFoldersHoldingThem() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appending(path: "repo")
        try Data("two".utf8).write(to: repo.appending(path: "Sources/kept.txt"))
        try Data("new".utf8).write(to: repo.appending(path: "new.txt"))

        let model = BrowserModel(start: repo)
        model.start()
        try await settled(model)

        let info = try #require(model.gitInfo)
        #expect(info.state(of: repo.appending(path: "Sources")) == .modified)
        #expect(info.state(of: repo.appending(path: "new.txt")) == .untracked)
        #expect(info.state(of: repo.appending(path: "readme.txt")) == nil)
        // The paths are the ones of the listed items.
        let sources = try #require(model.items.first { $0.name == "Sources" })
        #expect(info.states[sources.url.path] == .modified)
    }

    @Test func followsWhatGitDoesElsewhere() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appending(path: "repo")
        let model = BrowserModel(start: repo.appending(path: "Sources"))
        model.start()
        try await settled(model)
        #expect(model.gitInfo?.status.branch == "main")

        // A checkout only touches `.git`, not the folder shown.
        try git(["checkout", "-q", "-b", "feature"], in: repo)
        try await waitFor { model.gitInfo?.status.branch == "feature" }
        #expect(model.gitInfo?.status.branch == "feature")
    }

    @Test func switchingBranchUpdatesTheFolder() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appending(path: "repo")
        // "feature" has one more folder, with a file in it.
        try git(["checkout", "-q", "-b", "feature"], in: repo)
        try FileManager.default.createDirectory(at: repo.appending(path: "Extra"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: repo.appending(path: "Extra/file.txt"))
        try git(["add", "."], in: repo)
        try git([
            "-c", "user.name=Test", "-c", "user.email=test@example.com",
            "-c", "commit.gpgsign=false", "commit", "-q", "-m", "second",
        ], in: repo)

        let model = BrowserModel(start: repo.appending(path: "Extra"))
        model.start()
        try await settled(model)
        #expect(model.gitInfo?.status.branch == "feature")
        #expect(model.gitInfo?.lastCommit?.subject == "second")
        #expect(model.gitInfo?.branches.local == ["feature", "main"])

        // "Extra" does not exist on main: the window goes up to the repository.
        model.switchBranch(to: "main")
        try await waitFor { model.gitInfo?.status.branch == "main" && model.currentURL?.path == repo.path }
        try await settled(model)
        #expect(model.currentURL?.path == repo.path)
        #expect(model.gitInfo?.lastCommit?.subject == "first")
        #expect(model.alert == nil)
        #expect(model.activity == nil)

        model.switchBranch(to: "missing")
        try await waitFor { model.alert != nil }
        #expect(model.alert?.title == "Impossible de changer de branche")
        #expect(model.gitInfo?.status.branch == "main")
    }

    @Test func canBeTurnedOffInTheSettings() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        UserDefaults.standard.set(false, forKey: AppSettings.showsGitInfoKey)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.showsGitInfoKey) }

        let model = BrowserModel(start: root.appending(path: "repo"))
        model.start()
        try await settled(model)
        #expect(model.gitInfo == nil)

        UserDefaults.standard.removeObject(forKey: AppSettings.showsGitInfoKey)
        model.refreshGit()
        try await settled(model)
        #expect(model.gitInfo?.status.branch == "main")
    }

    @Test func writesTheStateInFrench() {
        var status = GitStatus()
        #expect(GitText.head(status) == "aucun commit")
        #expect(GitText.changes(status) == "aucune modification")
        #expect(GitText.sync(status) == nil)

        status.commit = "0123456"
        #expect(GitText.head(status) == "détaché à 0123456")
        status.branch = "main"
        status.ahead = 2
        status.behind = 1
        status.staged = 1
        status.unstaged = 3
        status.untracked = 1
        status.conflicted = 2
        #expect(GitText.head(status) == "main")
        #expect(GitText.sync(status) == "↑2 ↓1")
        #expect(GitText.changes(status) == "2 en conflit · 1 indexé · 3 modifiés · 1 non suivi")
    }
}
