import BetterFinderCore
import SwiftUI

/// A row of the sidebar.
enum SidebarItem: Hashable {
    /// The computer's overview.
    case computer
    case place(URL)
    case drive(UUID)
    /// A folder of the tree, below one of the rows above.
    case folder(FolderTreeNode)
}

struct SidebarView: View {
    let model: BrowserModel
    @Environment(VolumeStore.self) private var volumeStore
    @Environment(DriveMonitor.self) private var driveMonitor

    @State private var driveToRemove: NetworkDrive?
    /// Explorer's "Expand to open folder".
    @AppStorage(SidebarSettings.followsLocationKey) private var followsLocation = false

    private let favorites = Favorite.defaults

    var body: some View {
        List(selection: selection) {
            Label(BrowserModel.computerName, systemImage: "desktopcomputer")
                .sidebarRow { model.showComputer() }
                .tag(SidebarItem.computer)

            Section("Favoris") {
                ForEach(favorites) { favorite in
                    FolderBranch(node: FolderTreeNode(root: favorite.url, url: favorite.url), model: model) {
                        Label(favorite.name, systemImage: favorite.symbol)
                            .sidebarRow { model.navigate(to: favorite.url) }
                            .tag(SidebarItem.place(favorite.url))
                            .contextMenu { placeMenu(for: favorite.url) }
                            .folderDrop(on: favorite.url, model: model)
                    }
                }
            }

            Section {
                ForEach(driveMonitor.drives) { drive in
                    if let root = mountedRoot(of: drive) {
                        FolderBranch(node: FolderTreeNode(root: root, url: root), model: model) {
                            driveRow(drive)
                        }
                    } else {
                        // Not connected: the row stays, with nothing to unfold.
                        driveRow(drive)
                    }
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
                    FolderBranch(node: FolderTreeNode(root: url, url: url), model: model) {
                        Label(volume.name, systemImage: volume.symbolName)
                            .sidebarRow { model.navigate(to: url) }
                            .tag(SidebarItem.place(url))
                            .contextMenu { placeMenu(for: url) }
                            .folderDrop(on: url, model: model)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.currentURL, initial: true) { revealCurrentFolder() }
        .onChange(of: followsLocation) { revealCurrentFolder() }
        // A volume or a drive just showed up: the current folder may be on it.
        .onChange(of: treeRoots) { revealCurrentFolder() }
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

    private func driveRow(_ drive: NetworkDrive) -> some View {
        NetworkDriveRow(drive: drive, status: driveMonitor.status(of: drive.id))
            .sidebarRow { model.openDrive(drive.id) }
            .tag(SidebarItem.drive(drive.id))
            .contextMenu { driveMenu(for: drive) }
            .folderDrop(on: mountedRoot(of: drive), model: model)
    }

    /// Root folder of a drive whose content can be read right now.
    private func mountedRoot(of drive: NetworkDrive) -> URL? {
        guard case .mounted(let folder) = driveMonitor.status(of: drive.id) else { return nil }
        return BrowserModel.normalized(folder)
    }

    @ViewBuilder
    private func driveMenu(for drive: NetworkDrive) -> some View {
        let status = driveMonitor.status(of: drive.id)
        let hasMount = driveMonitor.volumeRoots[drive.id] != nil

        if case .mounted(let folder) = status {
            Button("Ouvrir") { model.openDrive(drive.id) }
            Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(folder) }
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

    private var localVolumes: [VolumeInfo] {
        volumeStore.volumes(besides: driveMonitor)
    }

    @ViewBuilder
    private func placeMenu(for url: URL) -> some View {
        Button("Ouvrir") { model.navigate(to: url) }
        Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(url) }
    }

    // MARK: - Folder tree

    /// Folders of the rows that can be unfolded, in sidebar order.
    private var treeRoots: [URL] {
        favorites.map(\.url)
            + driveMonitor.drives.compactMap(mountedRoot)
            + localVolumes.map { BrowserModel.normalized($0.url) }
    }

    private func revealCurrentFolder() {
        guard followsLocation, model.displayedDriveID == nil, let current = model.currentURL else { return }
        model.sidebarTree.reveal(current, roots: treeRoots)
    }

    // MARK: - Selection

    /// Highlights the row of the current location, if it has one, and
    /// navigates when a row is clicked.
    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { currentItem },
            set: { item in
                switch item {
                case .computer: model.showComputer()
                case .place(let url): model.navigate(to: url)
                case .drive(let id): model.openDrive(id)
                case .folder(let node): model.navigate(to: node.url)
                case nil: break
                }
            }
        )
    }

    private var currentItem: SidebarItem? {
        if model.isOnComputer {
            return .computer
        }
        if let id = model.displayedDriveID {
            return .drive(id)
        }
        guard let current = model.currentURL else { return nil }
        if let drive = driveMonitor.drives.first(where: { mountedRoot(of: $0) == current }) {
            return .drive(drive.id)
        }
        let places = favorites.map(\.url) + localVolumes.map { BrowserModel.normalized($0.url) }
        if let place = places.first(where: { $0 == current }) {
            return .place(place)
        }
        // A folder shown in the tree, else the drive it is on.
        if let node = model.sidebarTree.visibleNode(for: current, roots: treeRoots, showHidden: model.showHidden) {
            return .folder(node)
        }
        return driveMonitor.drive(containing: current).map { .drive($0.id) }
    }

}

enum SidebarSettings {
    /// Whether the tree unfolds down to the folder shown in the window.
    static let followsLocationKey = "SidebarFollowsLocation"
}

extension View {
    /// Makes the whole row clickable, including when it is already selected:
    /// a list only reports selection *changes*, and Explorer goes back to a
    /// drive's root when its row is clicked again.
    func sidebarRow(action: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded(action))
    }
}

extension View {
    /// Lets files be dropped on a row that stands for a folder. Nothing
    /// happens when the row has no folder to receive them (a drive that is
    /// not connected).
    func folderDrop(on folder: URL?, model: BrowserModel) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            guard let folder else { return false }
            return model.drop(urls.filter(\.isFileURL), into: folder)
        }
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
