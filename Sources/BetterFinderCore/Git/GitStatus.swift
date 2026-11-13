import Foundation

/// What Git says about one file or folder of a working tree.
public enum GitFileState: Sendable, Equatable {
    /// Not known to Git yet.
    case untracked
    /// New, and added to the index.
    case added
    /// Changed since the last commit, staged or not.
    case modified
    case renamed
    case deleted
    /// Left unmerged by a merge, a rebase or a cherry-pick.
    case conflicted

    /// The state a folder takes from what it contains: the most pressing one
    /// wins. A deleted or renamed file makes its folder "modified".
    var inherited: GitFileState {
        switch self {
        case .renamed, .deleted: .modified
        default: self
        }
    }

    var weight: Int {
        switch self {
        case .untracked: 1
        case .added: 2
        case .modified, .renamed, .deleted: 3
        case .conflicted: 4
        }
    }
}

/// State of a Git working tree, as told by
/// `git status --porcelain=v2 --branch -z`.
public struct GitStatus: Sendable, Equatable {
    /// Current branch, or `nil` when HEAD is detached.
    public var branch: String?
    /// Abbreviated id of the current commit, or `nil` before the first one.
    public var commit: String?
    /// Branch followed on the remote ("origin/main"), if any.
    public var upstream: String?
    /// Commits the branch has that its upstream does not, and the reverse.
    public var ahead = 0
    public var behind = 0

    /// Files with changes added to the index.
    public var staged = 0
    /// Files with changes not added to the index yet.
    public var unstaged = 0
    public var untracked = 0
    public var conflicted = 0

    /// Changed files, by path relative to the top of the working tree. An
    /// untracked folder is listed once, without what it contains.
    public var entries: [String: GitFileState] = [:]

    public init() {}

    public var isClean: Bool {
        staged == 0 && unstaged == 0 && untracked == 0 && conflicted == 0
    }

    /// Reads the output of `git status --porcelain=v2 --branch -z`.
    public init(porcelain data: Data) {
        // With -z every record ends with a NUL, and paths are written as
        // they are (no quoting). A rename is followed by its former path.
        let records = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            guard let kind = record.first else { continue }
            switch kind {
            case "#":
                readHeader(record)
            case "1":
                readChange(record, fieldsBeforePath: 8, renamed: false)
            case "2":
                readChange(record, fieldsBeforePath: 9, renamed: true)
                index += 1 // the former path
            case "u":
                if let path = Self.path(of: record, after: 10) {
                    conflicted += 1
                    entries[path] = .conflicted
                }
            case "?":
                let path = Self.withoutTrailingSlash(String(record.dropFirst(2)))
                if !path.isEmpty {
                    untracked += 1
                    entries[path] = .untracked
                }
            default:
                break // "!" (ignored) and anything newer
            }
        }
    }

    private mutating func readHeader(_ record: String) {
        let parts = record.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return }
        switch parts[1] {
        case "branch.oid":
            commit = parts[2] == "(initial)" ? nil : String(parts[2].prefix(7))
        case "branch.head":
            branch = parts[2] == "(detached)" ? nil : parts[2]
        case "branch.upstream":
            upstream = parts[2]
        case "branch.ab":
            // "+2 -1"
            for value in parts[2].split(separator: " ") {
                if value.hasPrefix("+") { ahead = Int(value.dropFirst()) ?? 0 }
                if value.hasPrefix("-") { behind = Int(value.dropFirst()) ?? 0 }
            }
        default:
            break
        }
    }

    /// An ordinary ("1") or renamed ("2") entry: `<kind> <XY> … <path>`,
    /// where X is the state of the index and Y the one of the working tree.
    private mutating func readChange(_ record: String, fieldsBeforePath: Int, renamed: Bool) {
        guard let path = Self.path(of: record, after: fieldsBeforePath) else { return }
        let fields = record.split(separator: " ", maxSplits: 2)
        guard fields.count >= 2, fields[1].count == 2,
              let x = fields[1].first, let y = fields[1].last
        else { return }
        if x != "." { staged += 1 }
        if y != "." { unstaged += 1 }

        let state: GitFileState
        if y == "D" || x == "D" {
            state = .deleted
        } else if x == "A" {
            state = .added
        } else if renamed || x == "R" {
            state = .renamed
        } else {
            state = .modified
        }
        entries[path] = state
    }

    /// The path ending a record, after `count` space-separated fields. The
    /// path itself may hold spaces.
    private static func path(of record: String, after count: Int) -> String? {
        let fields = record.split(separator: " ", maxSplits: count, omittingEmptySubsequences: false)
        guard fields.count == count + 1, !fields[count].isEmpty else { return nil }
        return String(fields[count])
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// State of every changed file and of every folder holding one, by full
    /// path, for a working tree whose top is `root`.
    public func states(under root: URL) -> [String: GitFileState] {
        let base = root.path == "/" ? "" : root.path
        var result: [String: GitFileState] = [:]
        for (path, state) in entries {
            var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { continue }
            result[base + "/" + components.joined(separator: "/")] = state
            // Folders above the file, up to the top (excluded).
            let inherited = state.inherited
            components.removeLast()
            while !components.isEmpty {
                let folder = base + "/" + components.joined(separator: "/")
                if (result[folder]?.weight ?? 0) < inherited.weight {
                    result[folder] = inherited
                }
                components.removeLast()
            }
        }
        return result
    }
}
