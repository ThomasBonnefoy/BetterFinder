import Foundation

/// One line of the system mount table.
public struct MountEntry: Hashable, Sendable {
    /// What is mounted, e.g. `//user@server/share` for SMB.
    public let source: String
    /// Where it is mounted, e.g. `/Volumes/share`.
    public let mountPoint: String
    /// File system name: `smbfs`, `afpfs`, `nfs`, `webdav`, `apfs`…
    public let fileSystem: String

    public init(source: String, mountPoint: String, fileSystem: String) {
        self.source = source
        self.mountPoint = mountPoint
        self.fileSystem = fileSystem
    }
}

/// Where a network drive is mounted.
public struct MountMatch: Equatable, Sendable {
    /// Root of the mounted volume: what gets unmounted.
    public let volume: URL
    /// Folder the drive opens: the volume itself, or a folder inside it when
    /// the drive's address points below the share.
    public let folder: URL

    public init(volume: URL, folder: URL) {
        self.volume = volume
        self.folder = folder
    }
}

/// `statfs` names both a C struct and a C function: this picks the struct.
private typealias FileSystemStats = statfs

public enum MountTable {
    /// Reads the mount table from the kernel's cache. `MNT_NOWAIT` means no
    /// file system is contacted, so this never stalls on a dead network share.
    public static func current() -> [MountEntry] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }

        var buffer = [FileSystemStats](repeating: FileSystemStats(), count: Int(count) + 8)
        let size = Int32(MemoryLayout<FileSystemStats>.stride * buffer.count)
        let filled = getfsstat(&buffer, size, MNT_NOWAIT)
        guard filled > 0 else { return [] }

        return buffer.prefix(Int(filled)).map { entry in
            var entry = entry
            return MountEntry(
                source: string(from: &entry.f_mntfromname),
                mountPoint: string(from: &entry.f_mntonname),
                fileSystem: string(from: &entry.f_fstypename)
            )
        }
    }

    private static func string<T>(from tuple: inout T) -> String {
        withUnsafePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }

    /// Finds where a drive is mounted, if it is.
    public static func match(for drive: NetworkDrive, in entries: [MountEntry]) -> MountMatch? {
        let wantedPath = drive.sharePath.lowercased()
        guard !drive.host.isEmpty, !wantedPath.isEmpty else { return nil }

        var shareOnlyMatch: MountMatch?
        for entry in entries {
            guard fileSystems(for: drive.scheme).contains(entry.fileSystem),
                  let remote = RemoteSource(entry: entry),
                  remote.host == drive.host
            else { continue }

            let volume = URL(filePath: entry.mountPoint, directoryHint: .isDirectory)
            let mountedPath = remote.path.lowercased()
            if mountedPath == wantedPath {
                return MountMatch(volume: volume, folder: volume)
            }
            // The whole share is mounted and the drive points inside it.
            if wantedPath.hasPrefix(mountedPath + "/") {
                let rest = String(drive.sharePath.dropFirst(mountedPath.count + 1))
                shareOnlyMatch = MountMatch(
                    volume: volume,
                    folder: volume.appending(path: rest, directoryHint: .isDirectory)
                )
            }
        }
        return shareOnlyMatch
    }

    private static func fileSystems(for scheme: String) -> Set<String> {
        switch scheme {
        case "smb", "cifs": ["smbfs"]
        case "afp": ["afpfs"]
        case "nfs": ["nfs"]
        case "http", "https": ["webdav"]
        case "ftp": ["ftp"]
        default: []
        }
    }
}

/// Server and path read from the "mounted from" field of a mount entry.
struct RemoteSource: Equatable {
    let host: String
    let path: String

    init?(entry: MountEntry) {
        let source = entry.source
        if source.hasPrefix("//") {
            // SMB and AFP: //[domain;]user[:password]@server[:port]/share/sub
            let body = source.dropFirst(2)
            guard let slash = body.firstIndex(of: "/") else { return nil }
            var authority = String(body[..<slash])
            if let at = authority.lastIndex(of: "@") {
                authority = String(authority[authority.index(after: at)...])
            }
            self.host = Self.cleanHost(authority)
            self.path = Self.cleanPath(String(body[slash...]))
        } else if let url = URL(string: source), let scheme = url.scheme, scheme.hasPrefix("http"),
                  let host = url.host() {
            // WebDAV: http://server/path/
            self.host = host.lowercased()
            self.path = Self.cleanPath(url.path(percentEncoded: false))
        } else if let colon = source.firstIndex(of: ":"), source[source.index(after: colon)...].hasPrefix("/") {
            // NFS: server:/export/path
            self.host = Self.cleanHost(String(source[..<colon]))
            self.path = Self.cleanPath(String(source[source.index(after: colon)...]))
        } else {
            return nil
        }
        guard !host.isEmpty, !path.isEmpty else { return nil }
    }

    private static func cleanHost(_ authority: String) -> String {
        var host = authority.removingPercentEncoding ?? authority
        // Drop a trailing ":port" (but leave IPv6 literals alone).
        if !host.hasPrefix("["), let colon = host.lastIndex(of: ":"),
           host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        return host.lowercased()
    }

    private static func cleanPath(_ path: String) -> String {
        (path.removingPercentEncoding ?? path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
