import Foundation

/// Saves the list of network drives as a JSON file.
public struct NetworkDriveStore: Sendable {
    public let fileURL: URL

    /// `~/Library/Application Support/BetterFinder/drives.json`
    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "BetterFinder/drives.json")
    }

    public init(fileURL: URL = NetworkDriveStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    private struct Document: Codable {
        var version = 1
        var drives: [NetworkDrive]
    }

    /// Returns the saved drives. A missing file means no drive yet.
    public func load() throws -> [NetworkDrive] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Document.self, from: data).drives
    }

    public func save(_ drives: [NetworkDrive]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Document(drives: drives))
        try data.write(to: fileURL, options: .atomic)
    }
}
