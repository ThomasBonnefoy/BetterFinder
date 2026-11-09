import Foundation
import Network
import Testing
@testable import BetterFinderCore

@Suite struct MountServiceTests {
    @Test func statusCodesBecomeReadableErrors() {
        #expect(MountError(status: ECANCELED) == .cancelled)
        #expect(MountError(status: -128) == .cancelled)
        #expect(MountError(status: EAUTH) == .authenticationFailed)
        #expect(MountError(status: ENOENT) == .shareNotFound)
        #expect(MountError(status: EHOSTUNREACH) == .serverUnreachable)
        #expect(MountError(status: ETIMEDOUT) == .serverUnreachable)
        #expect(MountError(status: EBUSY) == .busy)
        #expect(MountError(status: 12345) == .other(code: 12345))
    }

    /// Calls the real NetFS mount against a local port where nothing speaks
    /// SMB: it must fail with an error, without any window and without
    /// hanging.
    @Test(.timeLimit(.minutes(1)))
    func mountingAServerThatIsNotAFileServerFails() async throws {
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
        defer { listener.cancel() }
        let port = try #require(listener.port)
        let drive = NetworkDrive(name: "Fake", url: URL(string: "smb://127.0.0.1:\(port.rawValue)/share")!)

        await #expect(throws: MountError.self) {
            _ = try await NetFSMountService().mount(drive, allowUI: false)
        }
    }

    @Test func unmountingSomethingThatIsNotMountedFails() async {
        let notAVolume = FileManager.default.temporaryDirectory
        await #expect(throws: MountError.self) {
            try await NetFSMountService().unmount(notAVolume, force: false)
        }
    }
}
