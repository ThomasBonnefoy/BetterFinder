import AppKit
import BetterFinderCore
import SwiftUI

/// A sidebar row that unfolds to show the sub-folders of its folder, each of
/// them unfolding in turn.
///
/// `row` is the row itself: a favorite, a drive, a volume or, further down,
/// a plain folder.
struct FolderBranch<Row: View>: View {
    let node: FolderTreeNode
    let model: BrowserModel
    @ViewBuilder let row: Row

    var body: some View {
        let tree = model.sidebarTree
        if tree.isLeaf(node.url, showHidden: model.showHidden) {
            // Nothing to unfold: no disclosure arrow.
            row
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                if let folders = tree.subfolders(of: node.url, showHidden: model.showHidden) {
                    ForEach(folders) { folder in
                        let child = FolderTreeNode(root: node.root, url: folder.url)
                        FolderBranch<FolderRow>(node: child, model: model) {
                            FolderRow(folder: folder, node: child, model: model)
                        }
                    }
                } else {
                    Text("Chargement…")
                        .foregroundStyle(.secondary)
                }
            } label: {
                row
            }
        }
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { model.sidebarTree.isExpanded(node) },
            set: { model.sidebarTree.setExpanded(node, $0) }
        )
    }
}

/// Row of a folder inside the tree.
struct FolderRow: View {
    let folder: FileItem
    let node: FolderTreeNode
    let model: BrowserModel

    var body: some View {
        Label(folder.name, systemImage: "folder")
            .sidebarRow { model.navigate(to: folder.url) }
            .tag(SidebarItem.folder(node))
            .folderDrop(on: folder.url, model: model)
            .contextMenu {
                Button("Ouvrir") { model.navigate(to: folder.url) }
                Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(folder.url) }
                Button("Ouvrir dans le terminal") { model.openInTerminal(folder.url) }
                Divider()
                if FavoriteStore.shared.contains(folder.url) {
                    Button("Retirer des favoris") { FavoriteStore.shared.remove(folder.url) }
                } else {
                    Button("Ajouter aux favoris") { FavoriteStore.shared.add([folder.url]) }
                }
                Divider()
                Button("Copier le chemin d'accès") { model.clipboard.copyText(folder.url.path) }
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                }
            }
    }
}
