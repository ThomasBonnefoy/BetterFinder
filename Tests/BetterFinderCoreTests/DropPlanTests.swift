import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct DropPlanTests {
    private let files = FileManager.default
    private let root: URL

    /// root/A/file.txt, root/B/, root/A/Sub/
    init() throws {
        root = files.temporaryDirectory
            .appending(path: "BetterFinderDropTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: root.appending(path: "A/Sub"), withIntermediateDirectories: true)
        try files.createDirectory(at: root.appending(path: "B"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appending(path: "A/file.txt"))
    }

    private var a: URL { root.appending(path: "A") }
    private var b: URL { root.appending(path: "B") }
    private var file: URL { root.appending(path: "A/file.txt") }

    @Test func movesWithinAVolume() {
        #expect(DropPlan.mode(for: [file], into: b) == .move)
    }

    @Test func optionForcesACopy() {
        #expect(DropPlan.mode(for: [file], into: b, copyRequested: true) == .copy)
    }

    @Test func commandForcesAMove() {
        #expect(DropPlan.mode(for: [file], into: b, moveRequested: true) == .move)
    }

    @Test func refusesNothing() {
        #expect(DropPlan.mode(for: [], into: b) == nil)
    }

    @Test func refusesAFolderOnItself() {
        #expect(DropPlan.mode(for: [a], into: a) == nil)
    }

    @Test func refusesAFolderInOneOfItsSubfolders() {
        #expect(DropPlan.mode(for: [a], into: a.appending(path: "Sub")) == nil)
        #expect(DropPlan.mode(for: [a], into: a.appending(path: "Sub"), copyRequested: true) == nil)
    }

    @Test func similarNamesAreNotNested() {
        let sibling = root.appending(path: "A2")
        #expect(DropPlan.mode(for: [a], into: sibling, copyRequested: true) == .copy)
    }

    @Test func refusesAMoveToTheSameFolder() {
        #expect(DropPlan.mode(for: [file], into: a) == nil)
    }

    @Test func allowsACopyToTheSameFolder() {
        #expect(DropPlan.mode(for: [file], into: a, copyRequested: true) == .copy)
    }
}
