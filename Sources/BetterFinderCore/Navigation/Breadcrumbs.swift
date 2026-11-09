import Foundation

/// One clickable step of the address bar.
public struct Breadcrumb: Identifiable, Hashable, Sendable {
    public let url: URL
    /// Folder name. The startup disk's root is named "/".
    public let name: String

    public var id: URL { url }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

public enum Breadcrumbs {
    /// Splits a folder path into its ancestors, from the volume down to the
    /// folder itself. A path inside `/Volumes/Name` starts at that volume.
    public static func make(for url: URL) -> [Breadcrumb] {
        let components = url.standardizedFileURL.pathComponents
        guard components.first == "/" else { return [] }

        var crumbs: [Breadcrumb] = []
        var current = URL(filePath: "/", directoryHint: .isDirectory)
        var rest = Array(components.dropFirst())

        if rest.count >= 2, rest[0] == "Volumes" {
            current = current.appending(path: "Volumes", directoryHint: .isDirectory)
                .appending(path: rest[1], directoryHint: .isDirectory)
            crumbs.append(Breadcrumb(url: current, name: rest[1]))
            rest.removeFirst(2)
        } else {
            crumbs.append(Breadcrumb(url: current, name: "/"))
        }

        for component in rest {
            current = current.appending(path: component, directoryHint: .isDirectory)
            crumbs.append(Breadcrumb(url: current, name: component))
        }
        return crumbs
    }
}
