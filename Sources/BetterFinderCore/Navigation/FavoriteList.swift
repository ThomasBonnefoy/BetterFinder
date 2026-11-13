import Foundation

/// The folders pinned at the top of the sidebar, in the order the user wants.
public struct FavoriteList: Equatable, Sendable {
    public private(set) var urls: [URL]

    public init(_ urls: [URL] = []) {
        self.urls = []
        for url in urls { add(url) }
    }

    /// The favorites of a fresh install: home, Desktop, Documents, Downloads
    /// and Applications.
    public static func standard(files: FileManager = .default) -> FavoriteList {
        let candidates: [URL?] = [
            files.homeDirectoryForCurrentUser,
            files.urls(for: .desktopDirectory, in: .userDomainMask).first,
            files.urls(for: .documentDirectory, in: .userDomainMask).first,
            files.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            files.urls(for: .applicationDirectory, in: .localDomainMask).first,
        ]
        return FavoriteList(candidates.compactMap { $0 })
    }

    /// One spelling per folder, so that the same folder is never added twice.
    static func normalized(_ url: URL) -> URL {
        URL(filePath: url.standardizedFileURL.path, directoryHint: .notDirectory)
    }

    public func contains(_ url: URL) -> Bool {
        urls.contains(Self.normalized(url))
    }

    /// Adds a folder at the end. Returns false when it is already there.
    @discardableResult
    public mutating func add(_ url: URL) -> Bool {
        let url = Self.normalized(url)
        guard !urls.contains(url) else { return false }
        urls.append(url)
        return true
    }

    /// Adds a folder at a position (clamped to the list).
    @discardableResult
    public mutating func insert(_ url: URL, at index: Int) -> Bool {
        let url = Self.normalized(url)
        guard !urls.contains(url) else { return false }
        urls.insert(url, at: min(max(index, 0), urls.count))
        return true
    }

    public mutating func remove(_ url: URL) {
        let url = Self.normalized(url)
        urls.removeAll { $0 == url }
    }

    /// Moves the items at `offsets` so that they end up before the item that
    /// is at `destination` now (`destination == count` means the end). Same
    /// meaning as SwiftUI's `onMove`.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filter { urls.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moved = valid.map { urls[$0] }
        let before = valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) { urls.remove(at: index) }
        let target = min(max(destination - before, 0), urls.count)
        urls.insert(contentsOf: moved, at: target)
    }

    /// Puts `url` just before or just after `target`. Does nothing when
    /// either is not in the list or when they are the same.
    public mutating func move(_ url: URL, relativeTo target: URL, after: Bool) {
        let url = Self.normalized(url)
        let target = Self.normalized(target)
        guard url != target,
              let from = urls.firstIndex(of: url),
              urls.contains(target)
        else { return }
        urls.remove(at: from)
        let index = urls.firstIndex(of: target) ?? urls.count
        urls.insert(url, at: after ? index + 1 : index)
    }

    public func canMoveUp(_ url: URL) -> Bool {
        (urls.firstIndex(of: Self.normalized(url)) ?? 0) > 0
    }

    public func canMoveDown(_ url: URL) -> Bool {
        guard let index = urls.firstIndex(of: Self.normalized(url)) else { return false }
        return index < urls.count - 1
    }

    public mutating func moveUp(_ url: URL) {
        guard canMoveUp(url), let index = urls.firstIndex(of: Self.normalized(url)) else { return }
        move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
    }

    public mutating func moveDown(_ url: URL) {
        guard canMoveDown(url), let index = urls.firstIndex(of: Self.normalized(url)) else { return }
        move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
    }
}

/// Saves the favorites as a JSON file.
public struct FavoriteFile: Sendable {
    public let fileURL: URL

    /// `~/Library/Application Support/BetterFinder/favorites.json`
    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "BetterFinder/favorites.json")
    }

    public init(fileURL: URL = FavoriteFile.defaultFileURL) {
        self.fileURL = fileURL
    }

    private struct Document: Codable {
        var version = 1
        var favorites: [String]
    }

    /// The saved favorites, or `nil` when nothing was saved yet (the
    /// standard list applies).
    public func load() throws -> FavoriteList? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(Document.self, from: data)
        return FavoriteList(document.favorites.map { URL(filePath: $0) })
    }

    public func save(_ list: FavoriteList) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Document(favorites: list.urls.map(\.path)))
        try data.write(to: fileURL, options: .atomic)
    }

    /// Forgets the choices: the standard list applies again.
    public func reset() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
