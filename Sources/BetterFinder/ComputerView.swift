import AppKit
import BetterFinderCore
import SwiftUI

/// The computer's overview ("Ce PC" in Explorer): the main folders, the
/// disks with the space they have left, and the network drives.
struct ComputerView: View {
    let model: BrowserModel
    @Environment(VolumeStore.self) private var volumeStore
    @Environment(DriveMonitor.self) private var driveMonitor

    /// The tile that was clicked last. A double-click opens it.
    @State private var selection: Tile?

    /// The user's favorites, as in the sidebar.
    private var favorites: [Favorite] { FavoriteStore.shared.urls.map(Favorite.init(url:)) }
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 12, alignment: .topLeading)]

    private enum Tile: Hashable {
        case place(URL)
        case drive(UUID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Favoris") {
                    ForEach(favorites) { favorite in
                        tile(.place(favorite.url), open: { model.navigate(to: favorite.url) }) {
                            PlaceIcon(url: favorite.url)
                        } text: {
                            Text(favorite.name)
                        } menu: {
                            placeMenu(for: favorite.url)
                            Divider()
                            Button("Retirer des favoris") { FavoriteStore.shared.remove(favorite.url) }
                        }
                    }
                    if favorites.isEmpty {
                        Text("Aucun favori. Glissez un dossier sur « Favoris » dans la barre latérale pour en ajouter.")
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                }

                section("Appareils et lecteurs") {
                    ForEach(volumeStore.volumes(besides: driveMonitor)) { volume in
                        let url = BrowserModel.normalized(volume.url)
                        tile(.place(url), open: { model.navigate(to: url) }) {
                            if volume.isLocal {
                                PlaceIcon(url: url)
                            } else {
                                // No icon is asked of a share: it would
                                // mean a disk access on the main thread.
                                symbolIcon(volume.symbolName)
                            }
                        } text: {
                            Text(volume.name)
                            CapacityBar(volume: volume)
                        } menu: {
                            placeMenu(for: url)
                        }
                    }
                    tile(.place(model.trashURL), open: { model.showTrash() }) {
                        symbolIcon("trash")
                    } text: {
                        Text(DisplayName.trash)
                    } menu: {
                        Button("Vider la corbeille…") { model.askToEmptyTrash() }
                        Divider()
                        placeMenu(for: model.trashURL)
                    }
                }

                section("Lecteurs réseau") {
                    ForEach(driveMonitor.drives) { drive in
                        let status = driveMonitor.status(of: drive.id)
                        tile(.drive(drive.id), open: { model.openDrive(drive.id) }) {
                            driveIcon(status)
                        } text: {
                            Text(drive.name)
                            Text(Self.statusText(status))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(drive.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } menu: {
                            driveMenu(for: drive, status: status)
                        }
                        .help(DriveText.tooltip(for: drive, status: status))
                    }
                    Button {
                        model.driveEditor = DriveEditorRequest()
                    } label: {
                        HStack(spacing: 12) {
                            symbolIcon("plus")
                            Text("Ajouter un lecteur…")
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A click next to the tiles clears the selection.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
        }
        .task { refresh() }
        .onChange(of: model.computerRefreshes) { refresh() }
    }

    /// Free space changes without notice: read it again when the page shows
    /// up and when it is refreshed.
    private func refresh() {
        volumeStore.refresh()
        driveMonitor.scheduleRefresh()
    }

    // MARK: - Layout

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Divider()
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8, content: content)
        }
    }

    private func tile(
        _ id: Tile,
        open: @escaping () -> Void,
        @ViewBuilder icon: () -> some View,
        @ViewBuilder text: () -> some View,
        @ViewBuilder menu: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            icon()
            VStack(alignment: .leading, spacing: 3, content: text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selection == id ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        // Explorer's way: one click selects, two open.
        .gesture(TapGesture(count: 2).onEnded(open))
        .simultaneousGesture(TapGesture().onEnded { selection = id })
        .contextMenu {
            Button("Ouvrir", action: open)
            menu()
        }
    }

    private func symbolIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 26))
            .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private func driveIcon(_ status: DriveStatus) -> some View {
        switch status {
        case .connecting:
            ProgressView().controlSize(.small).frame(width: 40, height: 40)
        case .mounted:
            symbolIcon("externaldrive.connected.to.line.below")
        case .available:
            symbolIcon("externaldrive.connected.to.line.below").foregroundStyle(.secondary)
        case .offline, .unknown:
            symbolIcon("externaldrive.badge.xmark").foregroundStyle(.secondary)
        }
    }

    // MARK: - Menus

    @ViewBuilder
    private func placeMenu(for url: URL) -> some View {
        Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(url) }
        Divider()
        Button("Copier le chemin d'accès") { model.clipboard.copyText(url.path) }
        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @ViewBuilder
    private func driveMenu(for drive: NetworkDrive, status: DriveStatus) -> some View {
        if case .mounted(let folder) = status {
            Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(folder) }
            Button("Déconnecter") {
                Task { await driveMonitor.disconnect(drive.id) }
            }
        }
        Divider()
        Button("Modifier…") { model.driveEditor = DriveEditorRequest(existing: drive) }
    }

    // MARK: - Wording

    static func statusText(_ status: DriveStatus) -> String {
        switch status {
        case .mounted: "Connecté"
        case .available: "Disponible, non connecté"
        case .offline: "Hors ligne"
        case .connecting: "Connexion en cours…"
        case .unknown: "État inconnu"
        }
    }

    /// "120 Go libres sur 494 Go", or `nil` when the sizes are unknown.
    static func capacityText(for volume: VolumeInfo) -> String? {
        guard let total = volume.totalCapacity, total > 0, let available = volume.availableCapacity else {
            return nil
        }
        let free = FileFormat.size(min(available, total))
        return "\(free) libres sur \(FileFormat.size(total))"
    }
}

/// The icon macOS gives a folder or a disk.
private struct PlaceIcon: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 40, height: 40)
    }
}

/// How full a volume is, as in Explorer: a bar, red when little is left,
/// and the space left in words.
private struct CapacityBar: View {
    let volume: VolumeInfo

    var body: some View {
        if let used = volume.usedFraction, let text = ComputerView.capacityText(for: volume) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(volume.isNearlyFull ? Color.red : Color.accentColor)
                        .frame(width: max(geometry.size.width * used, 4))
                }
            }
            .frame(height: 6)
            .padding(.vertical, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
