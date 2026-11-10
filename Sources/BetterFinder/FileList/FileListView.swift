import BetterFinderCore
import SwiftUI

/// The file table plus what is shown over it when there is nothing to list.
struct FileListView: View {
    let model: BrowserModel

    var body: some View {
        if let driveID = model.displayedDriveID {
            UnavailableDriveView(model: model, driveID: driveID)
        } else if let folder = model.currentURL {
            table(for: folder)
        }
    }

    private func table(for folder: URL) -> some View {
        FileTableView(
            model: model,
            state: FileTableView.State(
                folder: folder,
                items: model.items,
                selection: model.selection,
                sort: model.sort,
                isLocalVolume: model.isLocalVolume,
                focusRequests: model.listFocusRequests,
                cutURLs: model.clipboard.cutURLs,
                renameRequest: model.renameRequest
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
