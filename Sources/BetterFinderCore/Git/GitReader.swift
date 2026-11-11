import Foundation

/// What Git says about the working tree a folder belongs to.
public struct GitInfo: Sendable, Equatable {
    /// Top folder of the working tree (the one holding `.git`).
    public let root: URL
    public let status: GitStatus
    /// State of the changed files and of the folders holding them, by path.
    public let states: [String: GitFileState]

    public init(root: URL, status: GitStatus) {
        self.root = root
        self.status = status
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
        return GitInfo(root: root, status: GitStatus(porcelain: output))
    }

    /// Runs Git and returns what it printed, or `nil` if it failed or took
    /// more than `timeout` seconds.
    private static func run(_ executable: URL, in folder: URL, arguments: [String], timeout: TimeInterval = 15) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-C", folder.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Only read: never take the lock of the index to refresh it, which
        // would get in the way of a Git command the user is running.
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "C"
        // Never wait for an answer at a prompt nobody sees.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}
