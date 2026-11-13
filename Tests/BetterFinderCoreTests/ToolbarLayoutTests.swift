import Foundation
import Testing
@testable import BetterFinderCore

@Suite struct ToolbarLayoutTests {
    @Test func theStandardLayoutShowsTheNewFileButton() {
        #expect(ToolbarLayout.standard.items.contains("newFile"))
        #expect(ToolbarLayout.standard.items.first == "back")
    }

    @Test func unknownAndRepeatedItemsAreDropped() {
        let layout = ToolbarLayout(items: ["back", "bogus", "back", "trash"])
        #expect(layout.items == ["back", "trash"])
    }

    @Test func everyStandardItemIsKnown() {
        #expect(ToolbarLayout.standardItems.allSatisfy(ToolbarLayout.known.contains))
        #expect(Set(ToolbarLayout.known).count == ToolbarLayout.known.count)
    }

    @Test func availableItemsAreTheOnesLeft() {
        let layout = ToolbarLayout(items: ToolbarLayout.known.filter { $0 != "trash" && $0 != "cut" })
        #expect(layout.available == ["cut", "trash"])
    }

    @Test func addingPutsTheItemLastOrAtAnIndex() {
        var layout = ToolbarLayout(items: ["back", "up"])
        layout.add("trash")
        layout.add("forward", at: 1)
        layout.add("back")
        layout.add("bogus")
        layout.add("copy", at: 99)
        #expect(layout.items == ["back", "forward", "up", "trash", "copy"])
    }

    @Test func removing() {
        var layout = ToolbarLayout(items: ["back", "up", "trash"])
        layout.remove("up")
        #expect(layout.items == ["back", "trash"])
    }

    @Test func movingLikeAList() {
        var layout = ToolbarLayout(items: ["back", "forward", "up", "trash"])
        layout.move(fromOffsets: [0], toOffset: 3)
        #expect(layout.items == ["forward", "up", "back", "trash"])
        layout.move(fromOffsets: [3], toOffset: 0)
        #expect(layout.items == ["trash", "forward", "up", "back"])
        layout.move(fromOffsets: [9], toOffset: 0)
        #expect(layout.items == ["trash", "forward", "up", "back"])
    }

    @Test func movingUpAndDown() {
        var layout = ToolbarLayout(items: ["back", "up", "trash"])
        #expect(!layout.canMoveUp("back"))
        #expect(!layout.canMoveDown("trash"))
        layout.moveUp("trash")
        layout.moveDown("back")
        #expect(layout.items == ["trash", "back", "up"])
    }

    // MARK: - Spaces

    @Test func spacesCanBeAddedSeveralTimesUnderDifferentIdentifiers() {
        var layout = ToolbarLayout(items: ["back", "up"])
        let first = layout.addSpace(.fixed)
        let second = layout.addSpace(.fixed)
        let third = layout.addSpace(.flexible, at: 1)
        #expect(first == "space.fixed.1")
        #expect(second == "space.fixed.2")
        #expect(third == "space.flexible.1")
        #expect(layout.items == ["back", "space.flexible.1", "up", "space.fixed.1", "space.fixed.2"])
    }

    @Test func aFreedSpaceNumberIsReused() {
        var layout = ToolbarLayout(items: ["back"])
        layout.addSpace(.fixed)
        layout.addSpace(.fixed)
        layout.remove("space.fixed.1")
        #expect(layout.addSpace(.fixed) == "space.fixed.1")
    }

    @Test func savedSpacesSurviveButBrokenOnesAreDropped() {
        let layout = ToolbarLayout(items: ["back", "space.fixed.1", "space.flexible.3", "space.fixed.", "space.huge.1", "space.fixed.1"])
        #expect(layout.items == ["back", "space.fixed.1", "space.flexible.3"])
    }

    @Test func spacesKnowTheirKind() {
        #expect(ToolbarLayout.spaceKind(of: "space.fixed.4") == .fixed)
        #expect(ToolbarLayout.spaceKind(of: "space.flexible.1") == .flexible)
        #expect(ToolbarLayout.spaceKind(of: "back") == nil)
        #expect(ToolbarLayout.isSpace("space.fixed.1"))
    }

    @Test func spacesAreNeverListedAsAvailableButtons() {
        var layout = ToolbarLayout(items: [])
        layout.addSpace(.fixed)
        #expect(layout.available == ToolbarLayout.known)
    }

    @Test func spacesMoveLikeAnyItem() {
        var layout = ToolbarLayout(items: ["back", "up"])
        let space = layout.addSpace(.flexible)
        layout.moveUp(space)
        #expect(layout.items == ["back", space, "up"])
    }
}
