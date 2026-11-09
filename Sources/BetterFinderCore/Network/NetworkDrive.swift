import Foundation

/// A network share the user wants to keep in the sidebar, whether or not it
/// is reachable right now.
///
/// No password is ever stored here: macOS keeps credentials in the Keychain.
public struct NetworkDrive: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// Name shown in the sidebar.
    public var name: String
    /// Address of the share, such as `smb://server/share`.
    public var url: URL
    /// Account to connect with. `nil` lets macOS decide (Keychain, prompt).
    public var username: String?
    /// Mount the share again by itself whenever its server becomes reachable.
    public var reconnectAutomatically: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        username: String? = nil,
        reconnectAutomatically: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.reconnectAutomatically = reconnectAutomatically
    }

    public var scheme: String { url.scheme?.lowercased() ?? "" }
    public var host: String { url.host()?.lowercased() ?? "" }

    /// TCP port used to check that the server answers.
    public var port: Int {
        url.port ?? Self.defaultPorts[scheme] ?? 445
    }

    /// Path of the share on the server, without leading or trailing slash.
    public var sharePath: String {
        url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static let defaultPorts: [String: Int] = [
        "smb": 445, "cifs": 445, "afp": 548, "nfs": 2049,
        "ftp": 21, "http": 80, "https": 443,
    ]

    /// Turns what the user typed into a share address. Accepts network URLs,
    /// Windows UNC paths (`\\server\share`) and a bare `server/share`, which
    /// is taken as SMB. Returns `nil` when no server and share can be read.
    public static func url(fromAddress text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.hasPrefix("\\\\") || trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return nil
        } else {
            candidate = "smb://" + trimmed
        }

        let base = URL(filePath: "/")
        guard case .remote(let url) = PathParser.parse(candidate, relativeTo: base) else { return nil }
        // A server alone is not a drive: a share (or export) is needed.
        let share = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !share.isEmpty else { return nil }
        return url
    }

    /// Default sidebar name for an address: the last folder of the share.
    public static func suggestedName(for url: URL) -> String {
        let last = url.path(percentEncoded: false)
            .split(separator: "/", omittingEmptySubsequences: true)
            .last.map(String.init)
        return last ?? url.host() ?? ""
    }
}
