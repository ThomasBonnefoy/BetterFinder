import Foundation

/// Puts items back where they were before they went to the Trash.
///
/// macOS has no public function for this: the "Put Back" of the Finder reads
/// the original place, which only the Finder knows. So the Finder is asked,
/// through a script, to put the items away. The first time, macOS asks the
/// user whether BetterFinder may control the Finder.
public enum TrashPutBack {
    public enum Failure: Error, Equatable, Sendable {
        /// The user (or macOS) refused to let the app control the Finder.
        case notAllowed
        /// The Finder could not do it; the text is its own explanation (for
        /// example when it does not know where the item came from).
        case failed(String)
    }

    /// What running the script gave.
    public struct ScriptResult: Equatable, Sendable {
        public var status: Int32
        public var message: String

        public init(status: Int32, message: String) {
            self.status = status
            self.message = message
        }
    }

    /// Runs the script on the given paths. A parameter so that tests do not
    /// need the Finder.
    public typealias Runner = @Sendable ([String]) -> ScriptResult

    /// The AppleScript: one `put away` per path, which arrive as arguments
    /// (never pasted into the script, so no quoting can go wrong).
    static let scriptLines = [
        "on run argv",
        "tell application \"Finder\"",
        "repeat with p in argv",
        "put away (POSIX file (contents of p) as alias)",
        "end repeat",
        "end tell",
        "end run",
    ]

    /// Arguments of `osascript` for these paths.
    static func arguments(for paths: [String]) -> [String] {
        scriptLines.flatMap { ["-e", $0] } + paths
    }

    public static let osascript: Runner = { paths in
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = arguments(for: paths)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return ScriptResult(status: -1, message: error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptResult(status: process.terminationStatus, message: String(decoding: data, as: UTF8.self))
    }

    /// Puts `urls` back. Returns `nil` on success.
    public static func restore(_ urls: [URL], runner: @escaping Runner = osascript) async -> Failure? {
        guard !urls.isEmpty else { return nil }
        let paths = urls.map(\.path)
        return await Task.detached(priority: .userInitiated) {
            failure(from: runner(paths))
        }.value
    }

    static func failure(from result: ScriptResult) -> Failure? {
        guard result.status != 0 else { return nil }
        let text = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
        // -1743: "not authorized to send Apple events".
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not authorized") {
            return .notAllowed
        }
        return .failed(text.isEmpty ? "Le Finder n'a pas pu remettre l'élément." : text)
    }
}
