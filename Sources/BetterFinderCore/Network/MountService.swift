import Foundation
import NetFS

/// Why a drive could not be connected or disconnected.
public enum MountError: Error, Equatable, Sendable {
    /// The user closed the system login window.
    case cancelled
    case authenticationFailed
    /// The server did not answer.
    case serverUnreachable
    /// The server answered but has no such share.
    case shareNotFound
    /// The volume is in use and could not be disconnected.
    case busy
    case other(code: Int32)

    init(status: Int32) {
        switch status {
        case ECANCELED, -128: self = .cancelled
        case EAUTH, EACCES, EPERM: self = .authenticationFailed
        case ENOENT, -6003: self = .shareNotFound
        case EHOSTUNREACH, EHOSTDOWN, ENETUNREACH, ENETDOWN, ETIMEDOUT, ECONNREFUSED, -6602:
            self = .serverUnreachable
        case EBUSY: self = .busy
        default: self = .other(code: status)
        }
    }
}

/// Connects and disconnects network shares.
public protocol DriveMounting: Sendable {
    /// Mounts the drive and returns its mount point. `allowUI` lets macOS
    /// show its login window when the Keychain has no usable password.
    func mount(_ drive: NetworkDrive, allowUI: Bool) async throws -> URL
    /// Unmounts a volume. `force` disconnects even when files are in use or
    /// the server is gone.
    func unmount(_ mountPoint: URL, force: Bool) async throws
}

/// Mounts through NetFS, the framework behind the Finder's "Connect to
/// Server": volumes land in /Volumes and passwords stay in the Keychain.
public struct NetFSMountService: DriveMounting {
    private static let queue = DispatchQueue(label: "betterfinder.mount", attributes: .concurrent)

    public init() {}

    public func mount(_ drive: NetworkDrive, allowUI: Bool) async throws -> URL {
        // String values of the NetFS option keys (C macros Swift cannot see).
        let openOptions = NSMutableDictionary(dictionary: [
            "UIOption": allowUI ? "AllowUI" : "NoUI",
        ])
        // A soft mount returns errors instead of hanging forever when the
        // server disappears, which is exactly what happens when a VPN drops.
        let mountOptions = NSMutableDictionary(dictionary: [
            "SoftMount": true,
        ])
        let user = drive.username.flatMap { $0.isEmpty ? nil : $0 }

        return try await withCheckedThrowingContinuation { continuation in
            var requestID: AsyncRequestID?
            let status = NetFSMountURLAsync(
                drive.url as CFURL,
                nil,
                user as CFString?,
                nil,
                openOptions,
                mountOptions,
                &requestID,
                Self.queue
            ) { status, _, mountPoints in
                let paths = mountPoints as? [String] ?? []
                // EEXIST: the share was already mounted, which is fine.
                if status == 0 || status == EEXIST, let path = paths.first {
                    continuation.resume(returning: URL(filePath: path, directoryHint: .isDirectory))
                } else if status == 0 || status == EEXIST {
                    continuation.resume(throwing: MountError.other(code: status))
                } else {
                    continuation.resume(throwing: MountError(status: status))
                }
            }
            // A non-zero result means the request never started: the block
            // above will not be called.
            if status != 0 {
                continuation.resume(throwing: MountError(status: status))
            }
        }
    }

    public func unmount(_ mountPoint: URL, force: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.queue.async {
                if Darwin.unmount(mountPoint.path, force ? MNT_FORCE : 0) == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MountError(status: errno))
                }
            }
        }
    }
}
