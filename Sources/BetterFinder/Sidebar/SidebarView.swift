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

    private var favoriteStore: FavoriteStore { .shared }
    private var favorites: [Favorite] { favoriteStore.urls.map(Favorite.init(url:)) }
    @State private var confirmsFavoritesReset = false

    var body: some View {
        List(selection: selection) {
            Label(BrowserModel.computerName, systemImage: "desktopcomputer")
                .sidebarRow { model.showComputer() }
                .tag(SidebarItem.computer)

            Section {
                ForEach(favorites) { favorite in
                    FolderBranch(node: FolderTreeNode(root: favorite.url, url: favorite.url), model: model) {
                        FavoriteRow(favorite: favorite, model: model)
                            .contextMenu { favoriteMenu(for: favorite.url) }
                    }
                }
            } header: {
                HStack {
                    Text("Favoris")
                    Spacer()
                    Button("Ajouter un dossier aux favoris", systemImage: "plus") { chooseFavorites() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Ajouter un dossier aux favoris")
                }
                // Drop a folder on the title to add it.
                .contentShape(Rectangle())
                .dropDestination(for: URL.self) { urls, _ in
                    let folders = urls.filter(Self.isFolder)
                    guard !folders.isEmpty else { return false }
                    favoriteStore.add(folders)
                    return true
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
                // Files dropped on the Trash are put in it.
                Label(DisplayName.trash, systemImage: "trash")
                    .sidebarRow { model.showTrash() }
                    .tag(SidebarItem.place(model.trashURL))
                    .contextMenu { trashMenu }
                    .folderDrop(on: model.trashURL, model: model)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.currentURL, initial: true) { revealCurrentFolder() }
        .onChange(of: followsLocation) { revealCurrentFolder() }
        // A volume or a drive just showed up: the current folder may be on it.
        .onChange(of: treeRoots) { revealCurrentFolder() }
        .confirmationDialog(
            "Rétablir les favoris par défaut ?",
            isPresented: $confirmsFavoritesReset
        ) {
            Button("Rétablir", role: .destructive) { favoriteStore.reset() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Votre liste de favoris est remplacée par la liste d'origine. Les dossiers ne sont pas touchés.")
        }
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
            Button("Ouvrir dans le terminal") { model.openInTerminal(folder) }
            favoriteToggle(for: BrowserModel.normalized(folder))
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
    private var trashMenu: some View {
        Button("Ouvrir") { model.showTrash() }
        Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(model.trashURL) }
        Divider()
        Button("Vider la corbeille…") { model.askToEmptyTrash() }
    }

    @ViewBuilder
    private func placeMenu(for url: URL) -> some View {
        Button("Ouvrir") { model.navigate(to: url) }
        Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(url) }
        Button("Ouvrir dans le terminal") { model.openInTerminal(url) }
        Divider()
        favoriteToggle(for: url)
    }

    // MARK: - Favorites

    /// Menu of a favorite: open, reorder, remove.
    @ViewBuilder
    private func favoriteMenu(for url: URL) -> some View {
        Button("Ouvrir") { model.navigate(to: url) }
        Button("Ouvrir dans un nouvel onglet") { model.openInNewTab(url) }
        Button("Ouvrir dans le terminal") { model.openInTerminal(url) }
        Divider()
        Button("Monter") { favoriteStore.moveUp(url) }
            .disabled(!favoriteStore.list.canMoveUp(url))
        Button("Descendre") { favoriteStore.moveDown(url) }
            .disabled(!favoriteStore.list.canMoveDown(url))
        Divider()
        Button("Retirer des favoris") { favoriteStore.remove(url) }
        Button("Rétablir les favoris par défaut…") { confirmsFavoritesReset = true }
    }

    @ViewBuilder
    private func favoriteToggle(for url: URL) -> some View {
        if favoriteStore.contains(url) {
            Button("Retirer des favoris") { favoriteStore.remove(url) }
        } else {
            Button("Ajouter aux favoris") { favoriteStore.add([url]) }
        }
    }

    /// "+" of the Favorites header: pick folders in a panel.
    private func chooseFavorites() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Ajouter"
        panel.message = "Choisissez les dossiers à ajouter aux favoris."
        guard panel.runModal() == .OK else { return }
        favoriteStore.add(panel.urls)
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
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
        let places = favorites.map(\.url) + localVolumes.map { BrowserModel.normalized($0.url) } + [model.trashURL]
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

/// A favorite's row. Drag it to reorder: dropped on the upper half of
/// another favorite it goes before, on the lower half after.
private struct FavoriteRow: View {
    let favorite: Favorite
    let model: BrowserModel
    @State private var height: CGFloat = 24

    var body: some View {
        Label(favorite.name, systemImage: favorite.symbol)
            .sidebarRow { model.navigate(to: favorite.url) }
            .tag(SidebarItem.place(favorite.url))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .draggable(Self.payload(for: favorite.url))
            .dropDestination(for: String.self) { texts, location in
                guard let path = texts.compactMap(Self.path(in:)).first else { return false }
                FavoriteStore.shared.move(
                    URL(filePath: path),
                    relativeTo: favorite.url,
                    after: location.y > height / 2
                )
                return true
            }
            .folderDrop(on: favorite.url, model: model)
    }

    private static let prefix = "betterfinder-favorite:"

    private static func payload(for url: URL) -> String { prefix + url.path }

    private static func path(in text: String) -> String? {
        text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : nil
    }
}

/// A shortcut to a folder.
struct Favorite: Identifiable {
    let url: URL
    let name: String
    let symbol: String

    var id: URL { url }

    /// A favorite for a folder: the standard ones keep their own symbol.
    init(url: URL) {
        let normalized = BrowserModel.normalized(url)
        self.url = normalized
        name = DisplayName.of(normalized)
        symbol = Self.defaults.first { $0.url == normalized }?.symbol ?? "folder"
    }

    init(url: URL, name: String, symbol: String) {
        self.url = url
        self.name = name
        self.symbol = symbol
    }

    /// The main folders of the user: what "Ce Mac" shows, and the favorites
    /// of a fresh install.
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
