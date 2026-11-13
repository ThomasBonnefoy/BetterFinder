import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct GitStatusTests {
    /// Records as `git status --porcelain=v2 --branch -z` writes them.
    private func porcelain(_ records: [String]) -> Data {
        Data(records.map { $0 + "\0" }.joined().utf8)
    }

    private let zeros = "N... 100644 100644 100644 1111111 2222222"

    @Test func readsTheBranchAndItsUpstream() {
        let status = GitStatus(porcelain: porcelain([
            "# branch.oid 0123456789abcdef0123456789abcdef01234567",
            "# branch.head feat/git",
            "# branch.upstream origin/feat/git",
            "# branch.ab +2 -1",
        ]))
        #expect(status.branch == "feat/git")
        #expect(status.commit == "0123456")
        #expect(status.upstream == "origin/feat/git")
        #expect(status.ahead == 2)
        #expect(status.behind == 1)
        #expect(status.isClean)
    }

    @Test func aDetachedHeadHasNoBranch() {
        let status = GitStatus(porcelain: porcelain([
            "# branch.oid 0123456789abcdef0123456789abcdef01234567",
            "# branch.head (detached)",
        ]))
        #expect(status.branch == nil)
        #expect(status.commit == "0123456")
    }

    @Test func aNewRepositoryHasNoCommit() {
        let status = GitStatus(porcelain: porcelain([
            "# branch.oid (initial)",
            "# branch.head main",
        ]))
        #expect(status.branch == "main")
        #expect(status.commit == nil)
        #expect(status.upstream == nil)
    }

    @Test func readsTheStateOfEachFile() {
        let status = GitStatus(porcelain: porcelain([
            "# branch.head main",
            "1 .M \(zeros) Sources/changed.swift",
            "1 M. \(zeros) staged.swift",
            "1 MM \(zeros) both.swift",
            "1 A. \(zeros) new file.swift",
            "1 .D \(zeros) gone.swift",
            "2 R. \(zeros) R100 renamed.swift",
            "old name.swift",
            "u UU N... 100644 100644 100644 100644 1111111 2222222 3333333 fight.swift",
            "? notes.txt",
            "? build/",
            "! ignored.log",
        ]))
        #expect(status.entries == [
            "Sources/changed.swift": .modified,
            "staged.swift": .modified,
            "both.swift": .modified,
            "new file.swift": .added,
            "gone.swift": .deleted,
            "renamed.swift": .renamed,
            "fight.swift": .conflicted,
            "notes.txt": .untracked,
            "build": .untracked,
        ])
        #expect(status.staged == 4) // staged, both, new file, renamed
        #expect(status.unstaged == 3) // changed, both, gone
        #expect(status.untracked == 2)
        #expect(status.conflicted == 1)
        #expect(!status.isClean)
    }

    @Test func foldersTakeTheStateOfWhatTheyHold() {
        let status = GitStatus(porcelain: porcelain([
            "1 .M \(zeros) a/b/changed.swift",
            "? a/b/new.txt",
            "? c/new.txt",
            "1 .D \(zeros) d/gone.swift",
            "u UU N... 100644 100644 100644 100644 1111111 2222222 3333333 a/fight.swift",
        ]))
        let states = status.states(under: URL(filePath: "/repo"))
        #expect(states["/repo/a/b/changed.swift"] == .modified)
        #expect(states["/repo/a/b/new.txt"] == .untracked)
        #expect(states["/repo/a/b"] == .modified)
        #expect(states["/repo/a"] == .conflicted)
        #expect(states["/repo/c"] == .untracked)
        #expect(states["/repo/d"] == .modified)
        #expect(states["/repo"] == nil)
    }

    @Test func anEmptyOutputIsACleanTree() {
        let status = GitStatus(porcelain: Data())
        #expect(status.isClean)
        #expect(status.entries.isEmpty)
    }
}

@Suite struct GitReaderTests {
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

    private func makeRepository() throws -> URL {
        let files = FileManager.default
        let root = files.temporaryDirectory
            .appending(path: "BetterFinderGitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: root.appending(path: "Sources/kept.txt"))
        try Data("one".utf8).write(to: root.appending(path: "readme.txt"))
        try git(["init", "-q", "-b", "main"], in: root)
        try git(["add", "."], in: root)
        try git([
            "-c", "user.name=Test", "-c", "user.email=test@example.com",
            "-c", "commit.gpgsign=false", "commit", "-q", "-m", "first",
        ], in: root)
        return root.standardizedFileURL
    }

    @Test func findsTheTopOfTheWorkingTree() throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GitReader.root(containing: root.appending(path: "Sources"))?.path == root.path)
        #expect(GitReader.root(containing: root)?.path == root.path)
    }

    @Test func aFolderOutsideARepositoryHasNoInfo() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "BetterFinderGitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The temporary folder itself must not be in a repository.
        try #require(GitReader.root(containing: folder) == nil)
        #expect(await GitReader.read(folder) == nil)
    }

    @Test func readsTheLastCommit() {
        let commit = GitCommit(log: Data("0123456\0fix: a thing\0Ada Lovelace\01700000000\n".utf8))
        #expect(commit == GitCommit(
            id: "0123456", subject: "fix: a thing", author: "Ada Lovelace",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        #expect(GitCommit(log: Data()) == nil)
    }

    @Test func sortsTheBranchesAndKeepsRemoteOnlyOnes() {
        let branches = GitBranches(refs: Data("""
        refs/heads/main
        refs/heads/dev
        refs/heads/feat/git
        refs/remotes/origin/HEAD
        refs/remotes/origin/main
        refs/remotes/origin/feat/other
        refs/remotes/origin/dev

        """.utf8))
        #expect(branches.local == ["dev", "feat/git", "main"])
        #expect(branches.remoteOnly == ["origin/feat/other"])
        #expect(GitBranches.localName(of: "origin/feat/other") == "feat/other")
    }

    @Test func switchesToAnotherBranch() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["branch", "other"], in: root)

        let before = try #require(await GitReader.read(root))
        #expect(before.branches.local == ["main", "other"])
        #expect(before.lastCommit?.subject == "first")
        #expect(before.lastCommit?.author == "Test")

        #expect(await GitReader.switchBranch(in: root, to: "other") == nil)
        #expect(await GitReader.read(root)?.status.branch == "other")

        // Git says why when it refuses.
        let failure = await GitReader.switchBranch(in: root, to: "missing")
        #expect(failure?.isEmpty == false)
        #expect(await GitReader.read(root)?.status.branch == "other")
    }

    @Test func readsARealRepository() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let clean = try #require(await GitReader.read(root.appending(path: "Sources")))
        #expect(clean.root.path == root.path)
        #expect(clean.status.branch == "main")
        #expect(clean.status.commit != nil)
        #expect(clean.status.isClean)

        try Data("two".utf8).write(to: root.appending(path: "Sources/kept.txt"))
        try Data("new".utf8).write(to: root.appending(path: "new file.txt"))

        let info = try #require(await GitReader.read(root))
        #expect(info.status.unstaged == 1)
        #expect(info.status.untracked == 1)
        #expect(info.state(of: root.appending(path: "Sources/kept.txt")) == .modified)
        #expect(info.state(of: root.appending(path: "Sources")) == .modified)
        #expect(info.state(of: root.appending(path: "new file.txt")) == .untracked)
        #expect(info.state(of: root.appending(path: "readme.txt")) == nil)
    }
}
