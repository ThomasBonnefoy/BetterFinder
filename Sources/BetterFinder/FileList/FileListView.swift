import BetterFinderCore
import SwiftUI

/// The file table plus what is shown over it when there is nothing to list.
struct FileListView: View {
    let model: BrowserModel

    var body: some View {
        FileTableView(
            folder: model.currentURL,
            items: model.items,
            selection: model.selection,
            sort: model.sort,
            isLocalVolume: model.isLocalVolume,
            focusRequests: model.listFocusRequests,
            actions: FileTableView.Actions(
                selectionChanged: { model.selection = $0 },
                sortChanged: { model.setSort($0) },
                open: { model.open($0) },
                goBack: { model.goBack() },
                goForward: { model.goForward() },
                goUp: { model.goUp() },
                reload: { model.reload() }
            )
        )
        .overlay { placeholder }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .allowsHitTesting(false)
        case .failed(let message):
            ContentUnavailableView {
                Label("Impossible d'ouvrir ce dossier", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { model.reload() }
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView("Ce dossier est vide", systemImage: "folder")
                    .allowsHitTesting(false)
            }
        }
    }
}
