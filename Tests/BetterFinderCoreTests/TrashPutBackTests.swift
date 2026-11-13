import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct TrashPutBackTests {
    @Test func pathsTravelAsArgumentsAfterTheScript() {
        let arguments = TrashPutBack.arguments(for: ["/a b/it's \"x\".txt", "/c"])
        #expect(arguments.suffix(2) == ["/a b/it's \"x\".txt", "/c"])
        #expect(arguments.prefix(2) == ["-e", "on run argv"])
        // The script itself never contains a path.
        #expect(!TrashPutBack.scriptLines.joined().contains("/c"))
    }

    @Test func successGivesNoFailure() async {
        let failure = await TrashPutBack.restore([URL(filePath: "/x")]) { _ in .init(status: 0, message: "") }
        #expect(failure == nil)
    }

    @Test func theRunnerReceivesThePaths() async {
        final class Box: @unchecked Sendable { var paths: [String] = [] }
        let box = Box()
        _ = await TrashPutBack.restore([URL(filePath: "/x"), URL(filePath: "/y")]) { paths in
            box.paths = paths
            return .init(status: 0, message: "")
        }
        #expect(box.paths == ["/x", "/y"])
    }

    @Test func nothingToRestoreRunsNothing() async {
        let failure = await TrashPutBack.restore([]) { _ in
            Issue.record("The script must not run")
            return .init(status: 0, message: "")
        }
        #expect(failure == nil)
    }

    @Test func aRefusedAutomationIsRecognised() {
        let message = "execution error: Not authorized to send Apple events to Finder. (-1743)"
        #expect(TrashPutBack.failure(from: .init(status: 1, message: message)) == .notAllowed)
    }

    @Test func anyOtherErrorKeepsTheFinderMessage() {
        #expect(TrashPutBack.failure(from: .init(status: 1, message: "  Finder got an error\n")) == .failed("Finder got an error"))
        #expect(TrashPutBack.failure(from: .init(status: 1, message: "")) == .failed("Le Finder n'a pas pu remettre l'élément."))
    }
}
