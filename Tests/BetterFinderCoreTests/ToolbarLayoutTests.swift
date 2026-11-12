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
}
