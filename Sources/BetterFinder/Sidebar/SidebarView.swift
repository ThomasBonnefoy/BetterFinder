import BetterFinderCore
import SwiftUI

/// A row of the sidebar.
enum SidebarItem: Hashable {
    case place(URL)
    case drive(UUID)
}

struct SidebarView: View {
    let model: BrowserModel
    @Environment(VolumeStore.self) private var volumeStore
    @Environment(DriveMonitor.self) private var driveMonitor

    @State private var driveToRemove: NetworkDrive?

    private let favorites = Favorite.defaults

    var body: some View {
        List(selection: selection) {
            Section("Favoris") {
                ForEach(favorites) { favorite in
                    Label(favorite.name, systemImage: favorite.symbol)
                        .sidebarRow { model.navigate(to: favorite.url) }
                        .tag(SidebarItem.place(favorite.url))
                }
            }

            Section {
                ForEach(driveMonitor.drives) { drive in
                    NetworkDriveRow(drive: drive, status: driveMonitor.status(of: drive.id))
                        .sidebarRow { model.openDrive(drive.id) }
                        .tag(SidebarItem.drive(drive.id))
                        .contextMenu { driveMenu(for: drive) }
                }
                if driveMonitor.drives.isEmpty {
                    Button {
                        model.driveEditor = DriveEditorRequest()
                    } label: {
                        Label("Ajouter un lecteur…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Lecteurs réseau")
                    Spacer()
                    Button("Ajouter un lecteur réseau", systemImage: "plus") {
                        model.driveEditor = DriveEditorRequest()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Ajouter un lecteur réseau")
                }
            }

            Section("Emplacements") {
                ForEach(localVolumes) { volume in
                    let url = BrowserModel.normalized(volume.url)
                    Label(volume.name, systemImage: symbol(for: volume))
                        .sidebarRow { model.navigate(to: url) }
                        .tag(SidebarItem.place(url))
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Retirer « \(driveToRemove?.name ?? "") » de la barre latérale ?",
            isPresented: Binding(
                get: { driveToRemove != nil },
                set: { if !$0 { driveToRemove = nil } }
            ),
            presenting: driveToRemove
        ) { drive in
            Button("Retirer", role: .destructive) { driveMonitor.remove(drive.id) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Le lecteur n'est pas effacé : seul son raccourci disparaît. Vous pourrez l'ajouter à nouveau.")
        }
    }

    // MARK: - Network drives

    @ViewBuilder
    private func driveMenu(for drive: NetworkDrive) -> some View {
        let status = driveMonitor.status(of: drive.id)
        let hasMount = driveMonitor.volumeRoots[drive.id] != nil

        if case .mounted = status {
            Button("Ouvrir") { model.openDrive(drive.id) }
        } else {
            Button("Connecter") { model.openDrive(drive.id) }
                .disabled(status == .connecting)
        }
        if hasMount {
            Button("Déconnecter") {
                Task { await driveMonitor.disconnect(drive.id) }
            }
        }
        Divider()
        Button("Modifier…") { model.driveEditor = DriveEditorRequest(existing: drive) }
        Button("Retirer de la barre latérale…", role: .destructive) { driveToRemove = drive }
    }

    /// Mounted volumes, minus the ones already listed as network drives.
    private var localVolumes: [VolumeInfo] {
        let driveRoots = Set(driveMonitor.volumeRoots.values.map(\.path))
        return volumeStore.volumes.filter { !driveRoots.contains($0.url.path) }
    }

    // MARK: - Selection

    /// Highlights the row of the current location, if it has one, and
    /// navigates when a row is clicked.
    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { currentItem },
            set: { item in
                switch item {
                case .place(let url): model.navigate(to: url)
                case .drive(let id): model.openDrive(id)
                case nil: break
                }
            }
        )
    }

    private var currentItem: SidebarItem? {
        if let id = model.displayedDriveID {
            return .drive(id)
        }
        guard let current = model.currentURL else { return nil }
        if let drive = driveMonitor.drive(containing: current) {
            return .drive(drive.id)
        }
        let places = favorites.map(\.url) + localVolumes.map { BrowserModel.normalized($0.url) }
        return places.first { $0 == current }.map(SidebarItem.place)
    }

    private func symbol(for volume: VolumeInfo) -> String {
        if !volume.isLocal { return "externaldrive.connected.to.line.below" }
        return volume.isEjectable ? "externaldrive" : "internaldrive"
    }
}

private extension View {
    /// Makes the whole row clickable, including when it is already selected:
    /// a list only reports selection *changes*, and Explorer goes back to a
    /// drive's root when its row is clicked again.
    func sidebarRow(action: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded(action))
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
