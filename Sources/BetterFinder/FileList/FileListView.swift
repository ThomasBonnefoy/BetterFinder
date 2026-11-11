import BetterFinderCore
import SwiftUI

/// The file table plus what is shown over it when there is nothing to list.
struct FileListView: View {
    let model: BrowserModel

    var body: some View {
        if model.isOnComputer {
            ComputerView(model: model)
        } else if let driveID = model.displayedDriveID {
            UnavailableDriveView(model: model, driveID: driveID)
        } else if let folder = model.currentURL {
            table(for: folder)
        }
    }

    private func table(for folder: URL) -> some View {
        let state = FileTableView.State(
            folder: folder,
            items: model.items,
            selection: model.selection,
            sort: model.sort,
            isLocalVolume: model.isLocalVolume,
            focusRequests: model.listFocusRequests,
            cutURLs: model.clipboard.cutURLs,
            renameRequest: model.renameRequest,
            gitStates: model.gitInfo?.states ?? [:]
        )
        return Group {
            switch model.viewMode {
            case .details:
                FileTableView(model: model, state: state)
            case .icons:
                FileIconsView(model: model, state: state)
            }
        }
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
            if model.isSearching {
                if model.items.isEmpty {
                    if model.isSearchRunning {
                        ProgressView()
                            .controlSize(.small)
                            .allowsHitTesting(false)
                    } else {
                        ContentUnavailableView.search(text: model.searchText)
                            .allowsHitTesting(false)
                    }
                }
            } else if model.items.isEmpty {
                ContentUnavailableView("Ce dossier est vide", systemImage: "folder")
                    .allowsHitTesting(false)
            }
        }
    }
}
