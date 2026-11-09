import Foundation
import Network

/// Tells whether a server answers, without touching any mounted volume.
public protocol ReachabilityProbing: Sendable {
    func isReachable(host: String, port: Int) async -> Bool
}

/// Opens a TCP connection to the server's port. With the VPN off, the name
/// does not resolve or there is no route, and the answer comes back at once.
public struct TCPReachabilityProbe: ReachabilityProbing {
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    public func isReachable(host: String, port: Int) async -> Bool {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return false
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "betterfinder.reachability")
        let once = Once()

        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ reachable: Bool) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: reachable)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .waiting, .cancelled:
                    // .waiting means "no route or no name yet": for a status
                    // check that is a no, not something to wait for.
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}

/// Lets exactly one caller through.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
