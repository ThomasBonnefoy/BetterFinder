import Foundation

/// What dropping files on a folder does.
public enum TransferMode: Equatable, Sendable {
    case copy
    case move
}

public enum DropPlan {
    /// Decides whether files dropped on `destination` are copied or moved, or
    /// `nil` when the drop must be refused.
    ///
    /// Like Explorer: items are moved within a volume and copied to another
    /// one. Option forces a copy, Command forces a move.
    public static func mode(
        for sources: [URL],
        into destination: URL,
        copyRequested: Bool = false,
        moveRequested: Bool = false
    ) -> TransferMode? {
        guard !sources.isEmpty else { return nil }
        // A folder cannot go into itself or into one of its own sub-folders.
        guard !sources.contains(where: { contains($0, destination) }) else { return nil }

        let mode: TransferMode
        if copyRequested {
            mode = .copy
        } else if moveRequested {
            mode = .move
        } else {
            mode = sources.allSatisfy { sameVolume($0, destination) } ? .move : .copy
        }
        // Moving things where they already are does nothing.
        if mode == .move, sources.allSatisfy({ parent(of: $0) == path(of: destination) }) {
            return nil
        }
        return mode
    }

    /// Whether `folder` is `item` or lies inside it.
    static func contains(_ item: URL, _ folder: URL) -> Bool {
        let item = path(of: item)
        let folder = path(of: folder)
        return folder == item || folder.hasPrefix(item.hasSuffix("/") ? item : item + "/")
    }

    private static func path(of url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func parent(of url: URL) -> String {
        path(of: url.deletingLastPathComponent())
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let first = try? a.resourceValues(forKeys: key).volumeIdentifier,
              let second = try? b.resourceValues(forKeys: key).volumeIdentifier
        else { return false }
        return first.isEqual(second)
    }
}
