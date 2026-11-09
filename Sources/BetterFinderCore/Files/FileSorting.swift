import Foundation

public enum SortKey: String, Sendable, CaseIterable {
    case name
    case dateModified
    case kind
    case size
}

public struct FileSort: Equatable, Sendable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }
}

extension Sequence where Element == FileItem {
    /// Sorts like Windows Explorer: folders always come first, names compare
    /// naturally ("file2" before "file10"), ties fall back to the name.
    public func sorted(by sort: FileSort) -> [FileItem] {
        sorted { lhs, rhs in
            if lhs.isBrowsable != rhs.isBrowsable {
                return lhs.isBrowsable
            }
            let order = FileSort.compare(lhs, rhs, by: sort.key)
            if order != .orderedSame {
                return sort.ascending ? order == .orderedAscending : order == .orderedDescending
            }
            // Keep ties in a stable, readable order whatever the direction.
            let byName = lhs.name.localizedStandardCompare(rhs.name)
            if byName != .orderedSame {
                return byName == .orderedAscending
            }
            return lhs.url.path < rhs.url.path
        }
    }
}

extension FileSort {
    static func compare(_ lhs: FileItem, _ rhs: FileItem, by key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .dateModified:
            return compare(lhs.modificationDate, rhs.modificationDate)
        case .kind:
            return lhs.kind.localizedStandardCompare(rhs.kind)
        case .size:
            return compare(lhs.size, rhs.size)
        }
    }

    /// Missing values sort before present ones.
    private static func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (l?, r?):
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
            return .orderedSame
        }
    }
}
