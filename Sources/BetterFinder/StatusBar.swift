import BetterFinderCore
import SwiftUI

/// Explorer-style status bar: item count and selection summary.
struct StatusBar: View {
    let model: BrowserModel

    var body: some View {
        HStack(spacing: 16) {
            // A drive's page and the computer's overview list no file:
            // counting items would be noise.
            if model.displayedDriveID == nil, !model.isOnComputer {
                Text(model.isSearching
                    ? Self.resultsText(model.items.count)
                    : Self.countText(model.items.count))
                let selected = model.selectedItems
                if !selected.isEmpty {
                    Text(Self.selectionText(selected))
                }
                if model.isSearching, selected.count == 1, let item = selected.first {
                    Text("Dans " + Self.folderText(of: item.url))
                }
            }
            Spacer()
            if model.isSearchRunning {
                ProgressView().controlSize(.mini)
                Text("Recherche…")
            }
            if let activity = model.activity {
                ProgressView().controlSize(.mini)
                Text(activity)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    static func countText(_ count: Int) -> String {
        count > 1 ? "\(count) éléments" : "\(count) élément"
    }

    static func resultsText(_ count: Int) -> String {
        count > 1 ? "\(count) résultats" : "\(count) résultat"
    }

    /// Folder holding an item, with the home folder written as "~".
    static func folderText(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    static func selectionText(_ selected: [FileItem]) -> String {
        var text = selected.count > 1
            ? "\(selected.count) éléments sélectionnés"
            : "1 élément sélectionné"
        // Folder sizes are unknown: only give a total for plain files.
        if selected.allSatisfy({ $0.size != nil }) {
            let total = selected.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            text += " · " + FileFormat.size(total)
        }
        return text
    }
}
