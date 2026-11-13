import Foundation

/// The buttons the user chose for the toolbar, in order.
///
/// BetterFinder keeps this itself rather than leaving it to the toolbar
/// customization of macOS: on macOS 26, SwiftUI's customizable toolbar
/// shuffles the saved layout at launch and can quit the app while doing so.
public struct ToolbarLayout: Equatable, Sendable {
    /// Identifiers of the items shown, from left to right.
    public private(set) var items: [String]

    /// Every identifier that exists. They must never change: saved layouts
    /// refer to them.
    public static let known: [String] = [
        "back", "forward", "up", "address", "viewMode", "reload", "newTab", "newFile", "search",
        "hiddenFiles", "computer", "home", "addFavorite", "reveal", "terminal",
        "newFolder", "cut", "copy", "paste", "rename", "trash", "copyPath",
        "compress", "properties", "previewPane",
    ]

    /// A gap between buttons. Unlike buttons, spaces can be added many
    /// times: each one has its own identifier, "space.fixed.1",
    /// "space.flexible.2"…
    public enum SpaceKind: Sendable {
        /// A small gap, which splits the buttons into groups.
        case fixed
        /// A gap that takes all the room left, pushing what follows to the
        /// right edge.
        case flexible
    }

    public static func spaceKind(of item: String) -> SpaceKind? {
        for (kind, prefix) in [(SpaceKind.fixed, "space.fixed."), (.flexible, "space.flexible.")]
        where item.hasPrefix(prefix) && item.count > prefix.count {
            return kind
        }
        return nil
    }

    public static func isSpace(_ item: String) -> Bool { spaceKind(of: item) != nil }

    /// What a new user sees.
    public static let standardItems: [String] = [
        "back", "forward", "up", "address", "viewMode", "reload", "newTab", "newFile", "search",
    ]

    public static let standard = ToolbarLayout(items: standardItems)

    /// Unknown identifiers and repetitions are dropped: a saved layout may
    /// come from another version.
    public init(items: [String]) {
        var seen = Set<String>()
        self.items = items.filter {
            (Self.known.contains($0) || Self.isSpace($0)) && seen.insert($0).inserted
        }
    }

    /// Known items that are not in the toolbar, in their standard order.
    public var available: [String] {
        Self.known.filter { !items.contains($0) }
    }

    public func contains(_ item: String) -> Bool { items.contains(item) }

    /// Adds an item at the end, or at `index`. Does nothing for an unknown
    /// item or one that is already there.
    public mutating func add(_ item: String, at index: Int? = nil) {
        guard Self.known.contains(item), !items.contains(item) else { return }
        let position = min(max(index ?? items.count, 0), items.count)
        items.insert(item, at: position)
    }

    /// Adds a space at the end, or at `index`, under a fresh identifier.
    @discardableResult
    public mutating func addSpace(_ kind: SpaceKind, at index: Int? = nil) -> String {
        let word = kind == .fixed ? "fixed" : "flexible"
        var number = 1
        while items.contains("space.\(word).\(number)") { number += 1 }
        let id = "space.\(word).\(number)"
        let position = min(max(index ?? items.count, 0), items.count)
        items.insert(id, at: position)
        return id
    }

    /// Puts an item right before `target`, or last when `target` is `nil` or
    /// not in the toolbar. An item already in the toolbar is moved; a known
    /// button that is not yet there is added. This is what dropping an item
    /// in the toolbar does. Returns false when nothing was done.
    @discardableResult
    public mutating func place(_ item: String, before target: String?) -> Bool {
        guard Self.known.contains(item) || Self.isSpace(item), item != target else { return false }
        let wasThere = items.contains(item)
        let original = items
        items.removeAll { $0 == item }
        let index = target.flatMap { items.firstIndex(of: $0) } ?? items.count
        items.insert(item, at: index)
        return !wasThere || items != original
    }

    /// Adds a new space right before `target`, or last.
    @discardableResult
    public mutating func addSpace(_ kind: SpaceKind, before target: String?) -> String {
        let id = addSpace(kind)
        place(id, before: target)
        return id
    }

    public mutating func remove(_ item: String) {
        items.removeAll { $0 == item }
    }

    /// Moves items the way a list does when rows are dragged.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filter { items.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moved = valid.map { items[$0] }
        let target = min(max(destination, 0), items.count)
        let shift = valid.filter { $0 < target }.count
        for index in valid.reversed() { items.remove(at: index) }
        items.insert(contentsOf: moved, at: target - shift)
    }

    public func canMoveUp(_ item: String) -> Bool {
        (items.firstIndex(of: item) ?? 0) > 0
    }

    public func canMoveDown(_ item: String) -> Bool {
        guard let index = items.firstIndex(of: item) else { return false }
        return index < items.count - 1
    }

    public mutating func moveUp(_ item: String) {
        guard canMoveUp(item), let index = items.firstIndex(of: item) else { return }
        items.swapAt(index, index - 1)
    }

    public mutating func moveDown(_ item: String) {
        guard canMoveDown(item), let index = items.firstIndex(of: item) else { return }
        items.swapAt(index, index + 1)
    }
}
