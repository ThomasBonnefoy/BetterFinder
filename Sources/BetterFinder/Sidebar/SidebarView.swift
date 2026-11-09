import BetterFinderCore
import SwiftUI

struct SidebarView: View {
    let model: BrowserModel
    @Environment(VolumeStore.self) private var volumeStore

    private let favorites = Favorite.defaults

    var body: some View {
        List(selection: selection) {
            Section("Favoris") {
                ForEach(favorites) { favorite in
                    Label(favorite.name, systemImage: favorite.symbol)
                        .tag(favorite.url)
                }
            }
            Section("Emplacements") {
                ForEach(volumeStore.volumes) { volume in
                    Label(volume.name, systemImage: symbol(for: volume))
                        .tag(BrowserModel.normalized(volume.url))
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Highlights the row of the current folder, if it has one, and
    /// navigates when a row is clicked.
    private var selection: Binding<URL?> {
        Binding(
            get: {
                let current = model.currentURL
                let known = favorites.map(\.url) + volumeStore.volumes.map { BrowserModel.normalized($0.url) }
                return known.first { $0 == current }
            },
            set: { url in
                if let url { model.navigate(to: url) }
            }
        )
    }

    private func symbol(for volume: VolumeInfo) -> String {
        if !volume.isLocal { return "externaldrive.connected.to.line.below" }
        return volume.isEjectable ? "externaldrive" : "internaldrive"
    }
}

/// A fixed shortcut to one of the user's main folders.
struct Favorite: Identifiable {
    let url: URL
    let name: String
    let symbol: String

    var id: URL { url }

    static var defaults: [Favorite] {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let entries: [(URL?, String)] = [
            (home, "house"),
            (files.urls(for: .desktopDirectory, in: .userDomainMask).first, "menubar.dock.rectangle"),
            (files.urls(for: .documentDirectory, in: .userDomainMask).first, "doc"),
            (files.urls(for: .downloadsDirectory, in: .userDomainMask).first, "arrow.down.circle"),
            (files.urls(for: .applicationDirectory, in: .localDomainMask).first, "square.grid.2x2"),
        ]
        return entries.compactMap { url, symbol in
            guard let url else { return nil }
            let normalized = BrowserModel.normalized(url)
            return Favorite(url: normalized, name: DisplayName.of(normalized), symbol: symbol)
        }
    }
}
