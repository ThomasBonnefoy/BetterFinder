import Foundation

/// What the text typed in the address bar points to.
public enum ParsedPath: Equatable, Sendable {
    /// A file or folder on this Mac (it may not exist).
    case local(URL)
    /// A network share, such as `smb://server/share`.
    case remote(URL)
    case invalid
}

public enum PathParser {
    /// URL schemes that macOS can mount as a network volume.
    public static let remoteSchemes: Set<String> = ["smb", "cifs", "afp", "nfs", "ftp", "http", "https"]

    /// Understands absolute paths, `~`, paths relative to `base`, `file://`
    /// URLs, network URLs and Windows UNC paths (`\\server\share`).
    public static func parse(
        _ input: String,
        relativeTo base: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ParsedPath {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Paths copied from a terminal or from Windows often come quoted.
        if text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" {
            text = String(text.dropFirst().dropLast())
        }
        guard !text.isEmpty else { return .invalid }

        if text.hasPrefix("\\\\") {
            return parseUNC(text)
        }

        if let schemeEnd = text.range(of: "://") {
            let scheme = text[..<schemeEnd.lowerBound].lowercased()
            if scheme == "file" {
                guard let url = URL(string: text), url.isFileURL else { return .invalid }
                return .local(url.standardizedFileURL)
            }
            guard remoteSchemes.contains(scheme),
                  let url = URL(string: text),
                  let host = url.host(), !host.isEmpty
            else { return .invalid }
            return .remote(url)
        }

        if text == "~" {
            return .local(home.standardizedFileURL)
        }
        if text.hasPrefix("~/") {
            return .local(home.appending(path: String(text.dropFirst(2))).standardizedFileURL)
        }
        if text.hasPrefix("/") {
            return .local(URL(filePath: text).standardizedFileURL)
        }
        return .local(base.appending(path: text).standardizedFileURL)
    }

    /// `\\server\share\folder` becomes `smb://server/share/folder`.
    private static func parseUNC(_ text: String) -> ParsedPath {
        let parts = text.split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return .invalid }
        var components = URLComponents()
        components.scheme = "smb"
        components.host = parts[0]
        components.path = "/" + parts.dropFirst().joined(separator: "/")
        guard let url = components.url else { return .invalid }
        return .remote(url)
    }
}
