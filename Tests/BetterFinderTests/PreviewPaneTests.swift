import Foundation
import Testing
@testable import BetterFinder
import BetterFinderCore

@MainActor
@Suite struct PreviewPaneTests {
    private func file(size: Int64? = 2048, kind: String = "Document texte") -> FileItem {
        FileItem(
            url: URL(filePath: "/Users/test/Docs/note.txt"),
            name: "note.txt",
            isDirectory: false,
            size: size,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            kind: kind
        )
    }

    @Test func detailsListTypeSizeDateAndPlace() {
        let labels = PreviewPane.details(of: file()).map(\.label)
        #expect(labels == ["Type", "Taille", "Modifié", "Emplacement"])
    }

    @Test func aFolderHasNoSize() {
        let folder = FileItem(url: URL(filePath: "/Users/test/Docs"), name: "Docs", isDirectory: true, kind: "Dossier")
        #expect(PreviewPane.details(of: folder).map(\.label) == ["Type", "Emplacement"])
    }

    @Test func emptyValuesAreLeftOut() {
        let labels = PreviewPane.details(of: file(kind: "")).map(\.label)
        #expect(!labels.contains("Type"))
    }

    @Test func aSelectionOfFilesGivesATotalSize() {
        let text = StatusBar.selectionDetail([file(size: 1000), file(size: 500)])
        #expect(text.hasPrefix("Taille totale"))
    }

    @Test func aSelectionWithAFolderPointsToTheProperties() {
        let folder = FileItem(url: URL(filePath: "/x"), name: "x", isDirectory: true, kind: "Dossier")
        #expect(StatusBar.selectionDetail([file(), folder]).contains("propriétés"))
    }

    @Test func theNewToolbarButtonsExist() {
        for id in ["compress", "properties", "previewPane"] {
            #expect(ToolbarLayout.known.contains(id))
            #expect(ToolbarItemInfo.symbol(of: id) != "questionmark")
            #expect(ToolbarItemInfo.title(of: id) != "")
        }
    }
}
