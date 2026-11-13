import Foundation

/// The commit HEAD is on.
public struct GitCommit: Sendable, Equatable {
    /// Abbreviated id.
    public var id: String
    /// First line of the message.
    public var subject: String
    public var author: String
    public var date: Date

    public init(id: String, subject: String, author: String, date: Date) {
        self.id = id
        self.subject = subject
        self.author = author
        self.date = date
    }

    /// Reads the output of `git log -1 --format=%h%x00%s%x00%an%x00%ct`.
    public init?(log data: Data) {
        let fields = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .newlines)
            .split(separator: "\0", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count == 4, !fields[0].isEmpty, let seconds = TimeInterval(fields[3]) else { return nil }
        self.init(id: fields[0], subject: fields[1], author: fields[2], date: Date(timeIntervalSince1970: seconds))
    }
}

/// The branches of a repository.
public struct GitBranches: Sendable, Equatable {
    /// Local branches, in alphabetical order.
    public var local: [String] = []
    /// Branches of the remotes that have no local branch of the same name
    /// yet, written "origin/name".
    public var remoteOnly: [String] = []

    public init(local: [String] = [], remoteOnly: [String] = []) {
        self.local = local
        self.remoteOnly = remoteOnly
    }

    /// Reads the output of
    /// `git for-each-ref --format=%(refname) refs/heads refs/remotes`.
    public init(refs data: Data) {
        var remote: [String] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            if line.hasPrefix("refs/heads/") {
                local.append(String(line.dropFirst("refs/heads/".count)))
            } else if line.hasPrefix("refs/remotes/"), !line.hasSuffix("/HEAD") {
                remote.append(String(line.dropFirst("refs/remotes/".count)))
            }
        }
        local.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        let known = Set(local)
        remoteOnly = remote
            .filter { !known.contains(Self.localName(of: $0)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// "origin/feat/x" → "feat/x".
    public static func localName(of remoteBranch: String) -> String {
        guard let slash = remoteBranch.firstIndex(of: "/") else { return remoteBranch }
        return String(remoteBranch[remoteBranch.index(after: slash)...])
    }
}

/// What Git says about the working tree a folder belongs to.
public struct GitInfo: Sendable, Equatable {
    /// Top folder of the working tree (the one holding `.git`).
    public let root: URL
    public let status: GitStatus
    /// State of the changed files and of the folders holding them, by path.
    public let states: [String: GitFileState]
    /// The commit HEAD is on, or `nil` before the first one.
    public let lastCommit: GitCommit?
    public let branches: GitBranches

    public init(root: URL, status: GitStatus, lastCommit: GitCommit? = nil, branches: GitBranches = GitBranches()) {
        self.root = root
        self.status = status
        self.lastCommit = lastCommit
        self.branches = branches
        states = status.states(under: root)
    }

    public func state(of url: URL) -> GitFileState? {
        states[url.path]
    }
}

/// Asks the `git` command about a folder, away from the main thread.
public enum GitReader {
    private static let queue = DispatchQueue(
        label: "betterfinder.git-reader",
        qos: .utility,
        attributes: .concurrent
    )

    /// Where `git` may be. `/usr/bin/git` is left out on purpose: without
    /// the developer tools it is a stub that asks to install them.
    static let candidates = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    /// The `git` command of this Mac, or `nil` when there is none.
    public static let executable: URL? = candidates
        .first { FileManager.default.isExecutableFile(atPath: $0) }
        .map { URL(filePath: $0) }

    /// Top of the working tree `folder` is in: the closest folder, going up,
    /// that holds a `.git` (a folder, or a file in a linked working tree or
    /// a submodule). Only looks at names: Git is not run.
    public static func root(containing folder: URL) -> URL? {
        var current = folder.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appending(path: ".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == "/" { return nil }
            current = parent
        }
    }

    /// State of the working tree `folder` is in, or `nil` when it is not in
    /// one, when there is no `git` command or when Git fails.
    public static func read(_ folder: URL) async -> GitInfo? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: readNow(folder))
            }
        }
    }

    static func readNow(_ folder: URL) -> GitInfo? {
        guard let executable, let root = root(containing: folder) else { return nil }
        guard let output = run(executable, in: root, arguments: [
            "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=normal",
        ]) else { return nil }
        let commit = run(executable, in: root, arguments: ["log", "-1", "--format=%h%x00%s%x00%an%x00%ct"])
            .flatMap(GitCommit.init(log:))
        let branches = run(executable, in: root, arguments: [
            "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes",
        ]).map(GitBranches.init(refs:)) ?? GitBranches()
        return GitInfo(root: root, status: GitStatus(porcelain: output), lastCommit: commit, branches: branches)
    }

    /// Switches the working tree at `root` to another branch. `remoteBranch`
    /// ("origin/name") creates the local branch that follows it. Returns
    /// what Git answered when it refused, `nil` when it is done.
    ///
    /// Git itself refuses a switch that would lose local changes.
    public static func switchBranch(in root: URL, to branch: String, remoteBranch: Bool = false) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let executable else {
                    continuation.resume(returning: "La commande git est introuvable.")
                    return
                }
                let arguments = remoteBranch ? ["switch", "--track", branch] : ["switch", branch]
                let result = launch(executable, in: root, arguments: arguments, capturingErrors: true, timeout: 120)
                if result.succeeded {
                    continuation.resume(returning: nil)
                } else {
                    let message = String(decoding: result.output, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: message.isEmpty ? "Git a refusé de changer de branche." : message)
                }
            }
        }
    }

    /// Runs Git and returns what it printed, or `nil` if it failed or took
    /// more than `timeout` seconds.
    private static func run(_ executable: URL, in folder: URL, arguments: [String], timeout: TimeInterval = 15) -> Data? {
        let result = launch(executable, in: folder, arguments: arguments, capturingErrors: false, timeout: timeout)
        return result.succeeded ? result.output : nil
    }

    /// Runs Git. `output` is what it printed, or its error messages when
    /// `capturingErrors` is set. A read never takes the lock of the index.
    private static func launch(
        _ executable: URL,
        in folder: URL,
        arguments: [String],
        capturingErrors: Bool,
        timeout: TimeInterval
    ) -> (succeeded: Bool, output: Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-C", folder.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Only read: never take the lock of the index to refresh it, which
        // would get in the way of a Git command the user is running.
        if !capturingErrors { environment["GIT_OPTIONAL_LOCKS"] = "0" }
        environment["LC_ALL"] = "C"
        // Never wait for an answer at a prompt nobody sees.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = capturingErrors ? FileHandle.nullDevice : output
        process.standardError = capturingErrors ? output : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (false, Data())
        }
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus == 0, data)
    }
}
