import Foundation
import Network
import Testing
@testable import BetterFinderCore

@Suite struct ReachabilityProbeTests {
    /// Starts a TCP listener on a free local port and returns it once ready.
    private func startListener() async throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        return listener
    }

    @Test func aListeningServerIsReachable() async throws {
        let listener = try await startListener()
        defer { listener.cancel() }
        let port = try #require(listener.port)

        let reachable = await TCPReachabilityProbe().isReachable(host: "127.0.0.1", port: Int(port.rawValue))
        #expect(reachable)
    }

    @Test func aClosedPortIsNotReachable() async throws {
        // Take a free port, then close it: nothing listens there any more.
        let listener = try await startListener()
        let port = try #require(listener.port)
        listener.cancel()
        try await Task.sleep(for: .milliseconds(100))

        let reachable = await TCPReachabilityProbe().isReachable(host: "127.0.0.1", port: Int(port.rawValue))
        #expect(!reachable)
    }

    @Test func anUnknownNameAnswersNoWithoutWaitingForever() async {
        let clock = ContinuousClock()
        let start = clock.now
        let reachable = await TCPReachabilityProbe(timeout: 2)
            .isReachable(host: "betterfinder-no-such-host.invalid", port: 445)
        #expect(!reachable)
        #expect(clock.now - start < .seconds(4))
    }

    @Test func anEmptyHostIsNotReachable() async {
        #expect(await TCPReachabilityProbe().isReachable(host: "", port: 445) == false)
    }
}
