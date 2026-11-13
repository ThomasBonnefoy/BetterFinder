import Foundation

/// Renames several items at once: works out the new names and checks that
/// they can all be used, before anything touches the disk.
public enum BatchRename {
    /// How the new names are made. The extension is always kept.
    public enum Rule: Equatable, Sendable {
        /// "Name (1).jpg", "Name (2).jpg"… in the order of the items.
        case sequence(name: String, start: Int, digits: Int)
        /// Replaces text in the names.
        case replace(find: String, with: String, caseSensitive: Bool)
        /// Puts text before and after the names.
        case affix(prefix: String, suffix: String)
    }

    /// Why a new name cannot be used.
    public enum Problem: Equatable, Sendable {
        case invalidName(FileNaming.Problem)
        /// Two items would get the same name.
        case duplicate
        /// Another item that is not renamed already has that name.
        case taken
    }

    public struct Entry: Equatable, Sendable {
        public let url: URL
        public let oldName: String
        public let newName: String
        public let problem: Problem?
        public var isChanged: Bool { oldName != newName }
    }

    public struct Plan: Equatable, Sendable {
        public let entries: [Entry]

        /// True when every new name can be used.
        public var isValid: Bool { entries.allSatisfy { $0.problem == nil } }
        /// True when at least one item gets a different name.
        public var changesSomething: Bool { entries.contains(where: \.isChanged) }
        /// The renames to carry out: the items whose name changes.
        public var moves: [FileMove] {
            entries.filter(\.isChanged).map {
                FileMove(from: $0.url, to: $0.url.deletingLastPathComponent().appending(path: $0.newName))
            }
        }
    }

    /// Works out the renames.
    ///
    /// - Parameters:
    ///   - items: what to rename, in order (this order numbers a sequence).
    ///   - namesInFolder: every name already in the folder, selected items
    ///     included: those that are not renamed can block a new name.
    public static func plan(
        for items: [(url: URL, isDirectory: Bool)],
        rule: Rule,
        namesInFolder: [String]
    ) -> Plan {
        var newNames: [String] = []
        for (index, item) in items.enumerated() {
            newNames.append(newName(for: item.url.lastPathComponent, isDirectory: item.isDirectory, index: index, rule: rule))
        }

        let renamed = Set(items.map { $0.url.lastPathComponent.lowercased() })
        let others = Set(namesInFolder.map { $0.lowercased() }).subtracting(renamed)
        var counts: [String: Int] = [:]
        for name in newNames { counts[name.lowercased(), default: 0] += 1 }

        let entries = zip(items, newNames).map { item, name -> Entry in
            let old = item.url.lastPathComponent
            var problem: Problem?
            if name == old {
                problem = nil
            } else if let invalid = FileNaming.problem(with: name) {
                problem = .invalidName(invalid)
            } else if counts[name.lowercased(), default: 0] > 1 {
                problem = .duplicate
            } else if others.contains(name.lowercased()) {
                problem = .taken
            }
            return Entry(url: item.url, oldName: old, newName: name, problem: problem)
        }
        return Plan(entries: entries)
    }

    static func newName(for name: String, isDirectory: Bool, index: Int, rule: Rule) -> String {
        let (base, ext) = FileNaming.split(name, isDirectory: isDirectory)
        let newBase: String
        switch rule {
        case .sequence(let text, let start, let digits):
            let number = String(start + index)
            let padded = String(repeating: "0", count: max(0, digits - number.count)) + number
            newBase = "\(text) (\(padded))"
        case .replace(let find, let replacement, let caseSensitive):
            newBase = find.isEmpty
                ? base
                : base.replacingOccurrences(
                    of: find, with: replacement, options: caseSensitive ? [] : [.caseInsensitive]
                )
        case .affix(let prefix, let suffix):
            newBase = prefix + base + suffix
        }
        return ext.isEmpty ? newBase : "\(newBase).\(ext)"
    }
}
