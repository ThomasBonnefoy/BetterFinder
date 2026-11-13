import AppKit
import BetterFinderCore
import Observation

/// State of one browser window: where it is, what it shows, what is selected.
@MainActor
@Observable
final class BrowserModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var history: NavigationHistory<BrowserLocation>
    /// Entries of the current folder, filtered and sorted for display.
    private(set) var items: [FileItem] = []
    private(set) var state: LoadState = .loading
    private(set) var isLocalVolume = true
    private(set) var sort = FileSort()
    private(set) var showHidden = AppSettings.showsHiddenFiles
    private(set) var isEditingAddress = false
    /// Incremented to ask the file list to take the keyboard focus.
    private(set) var listFocusRequests = 0
    /// Network drives, once the window has been given them.
    private(set) var driveMonitor: DriveMonitor?
    /// Set when the current folder is on a network drive that went offline:
    /// the drive's page is shown instead of a list that would never load.
    private(set) var blockedDrive: UUID?
    /// True when the current folder could not be read because macOS does not
    /// allow the app to (the Trash, for instance, before "Full Disk Access").
    private(set) var accessDenied = false
    var selection: Set<URL> = []
    /// What Git says about the folder shown, when it is in a working tree
    /// on a local disk.
    private(set) var gitInfo: GitInfo?
    /// What the search field holds. A search looks for names in the current
    /// folder and all its sub-folders; it ends when the text is emptied or
    /// when the window goes elsewhere.
    var searchText = "" {
        didSet {
            if searchText != oldValue { startSearch() }
        }
    }
    /// True while the list shows search results instead of the folder.
    private(set) var isSearching = false
    /// True while a search is still looking.
    private(set) var isSearchRunning = false
    /// Incremented to ask the window to put the cursor in the search field.
    private(set) var searchFocusRequests = 0
    /// Incremented when the computer's overview is asked to refresh.
    private(set) var computerRefreshes = 0
    /// Non-nil while the "add or edit a network drive" sheet is open.
    var driveEditor: DriveEditorRequest?

    /// What a running file operation is doing ("Copie…"), for the status bar.
    private(set) var activity: String?
    /// Asks the file list to start renaming an item in place.
    private(set) var renameRequest: RenameRequest?
    /// An error to show to the user.
    var alert: OperationAlert?
    /// True while the sheet that composes the toolbar is open.
    var isCustomizingToolbar = false
    /// False when the extensions of file names are hidden in the lists.
    /// Remembered between launches.
    var showsExtensions = AppSettings.showsExtensions {
        didSet {
            if showsExtensions != oldValue {
                UserDefaults.standard.set(showsExtensions, forKey: AppSettings.showsExtensionsKey)
            }
        }
    }
    /// How the folder's content is drawn. Remembered between launches.
    var viewMode = ViewMode.saved {
        didSet {
            if viewMode != oldValue { UserDefaults.standard.set(viewMode.rawValue, forKey: ViewMode.defaultsKey) }
        }
    }
    /// Items waiting for the user to confirm their permanent deletion.
    var deleteConfirmation: DeleteConfirmation?
    /// The window's undo manager, so that Edit > Undo covers file operations.
    @ObservationIgnored var undoManager: UndoManager?

    let clipboard: FileClipboard
    /// The user's Trash. A parameter of the model so that tests can use
    /// another folder.
    let trashURL: URL
    /// Folder tree of the sidebar. The tabs of the app share one.
    let sidebarTree: SidebarTreeModel
    /// Opens a folder, or the computer's overview, in a new tab. Set by the
    /// window.
    @ObservationIgnored var tabOpener: (@MainActor (BrowserLocation) -> Void)?

    @ObservationIgnored private var allItems: [FileItem] = []
    @ObservationIgnored private var searchItems: [FileItem] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    /// Folder listings still running. A refresh keeps `state` at `.loaded`,
    /// so this is the only way to tell that the list is up to date.
    @ObservationIgnored private(set) var pendingLoads = 0
    @ObservationIgnored private var pendingSelection: Set<URL> = []
    @ObservationIgnored private var pendingRename: URL?
    @ObservationIgnored private var renameRequestCount = 0
    @ObservationIgnored private var runningOperations = 0
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let watcher = DirectoryWatcher()
    @ObservationIgnored private let executor = FileOperationExecutor()
    /// Watches the `.git` folder: a commit, a checkout or a `git add` made
    /// elsewhere changes it without touching the folder shown.
    @ObservationIgnored private let gitWatcher = DirectoryWatcher()
    @ObservationIgnored private var gitWatchedRoot: URL?
    @ObservationIgnored private var gitGeneration = 0
    /// Git reads still running, for the tests.
    @ObservationIgnored private(set) var pendingGitReads = 0
    /// Undo entries of this window. The undo manager does not retain its
    /// targets, so they are kept alive here.
    @ObservationIgnored private var undoRecords: [UndoRecord] = []

    init(
        start: URL = FileManager.default.homeDirectoryForCurrentUser,
        clipboard: FileClipboard = .shared,
        sidebarTree: SidebarTreeModel = SidebarTreeModel(),
        trash: URL = TrashFolder.url
    ) {
        history = NavigationHistory(start: .folder(Self.normalized(start)))
        trashURL = Self.normalized(trash)
        self.clipboard = clipboard
        self.sidebarTree = sidebarTree
    }

    // MARK: - Location

    var location: BrowserLocation { history.current }

    /// The folder being shown, or `nil` on a network drive's page.
    var currentURL: URL? {
        if case .folder(let url) = location { return url }
        return nil
    }

    /// The network drive whose page replaces the file list, if any.
    var displayedDriveID: UUID? {
        if case .drive(let id) = location { return id }
        return blockedDrive
    }

    /// True on the Trash itself.
    var isOnTrash: Bool {
        currentURL.map { TrashFolder.isTrash($0, trash: trashURL) } ?? false
    }

    /// True in the Trash or in a folder that lies in it.
    var isInTrash: Bool {
        currentURL.map { TrashFolder.contains($0, trash: trashURL) } ?? false
    }

    /// Name of the computer's overview ("Ce PC" in Explorer).
    nonisolated static let computerName = "Ce Mac"

    /// True on the computer's overview.
    var isOnComputer: Bool { location == .computer }

    var title: String {
        switch location {
        case .computer:
            return Self.computerName
        case .folder(let url):
            if TrashFolder.isTrash(url, trash: trashURL) { return DisplayName.trash }
            return driveMonitor?.driveMounted(at: url)?.name ?? DisplayName.of(url)
        case .drive(let id):
            return driveMonitor?.drive(id)?.name ?? "Lecteur réseau"
        }
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    /// Every folder has something above it: the top of a disk leads to the
    /// computer's overview.
    var canGoUp: Bool { currentURL != nil }

    /// Gives the window its network drives. Called once, before `start`.
    func attach(_ monitor: DriveMonitor) {
        driveMonitor = monitor
        sidebarTree.isUnreachable = { [weak monitor] url in
            guard let monitor, let drive = monitor.drive(containing: url) else { return false }
            return monitor.status(of: drive.id) == .offline
        }
    }

    /// Loads the first folder. Called once, when the window appears.
    /// `folder` replaces the one given at creation: a tab is told what to
    /// show after its window has been created.
    func start(at folder: URL? = nil, onComputer: Bool = false) {
        guard !hasStarted else { return }
        hasStarted = true
        if onComputer {
            history = NavigationHistory(start: .computer)
        } else if let folder {
            history = NavigationHistory(start: .folder(Self.normalized(folder)))
        }
        load(resetContent: true)
    }

    // MARK: - Tabs

    /// A new tab on the computer's overview (Ctrl+T in Explorer opens its
    /// home page).
    func newTab() {
        tabOpener?(AppSettings.opensOnComputer
            ? .computer
            : .folder(Self.normalized(FileManager.default.homeDirectoryForCurrentUser)))
    }

    func openInNewTab(_ url: URL) {
        tabOpener?(.folder(Self.normalized(url)))
    }

    /// True when the selection is made of folders only.
    var canOpenSelectionInNewTabs: Bool {
        let selected = selectedItems
        return !selected.isEmpty && selected.allSatisfy(\.isBrowsable)
    }

    /// Opens every selected folder in a tab of its own.
    func openSelectionInNewTabs() {
        guard canOpenSelectionInNewTabs else { return }
        for item in selectedItems {
            openInNewTab(item.url)
        }
    }

    func navigate(to url: URL, selecting itemToSelect: URL? = nil) {
        let target = BrowserLocation.folder(Self.normalized(url))
        endEditingAddress()
        guard target != location else {
            if let itemToSelect {
                // Showing a search result that is in this very folder.
                searchText = ""
                selection = [itemToSelect]
            }
            return
        }
        history.go(to: target)
        pendingSelection = itemToSelect.map { [$0] } ?? []
        load(resetContent: true)
    }

    func goBack() {
        let left = currentURL
        guard history.goBack() != nil else { return }
        // Like Explorer: coming back selects the folder we just left.
        if let left, let current = currentURL, left.deletingLastPathComponent().path == current.path {
            pendingSelection = [left]
        } else {
            pendingSelection = []
        }
        load(resetContent: true)
    }

    func goForward() {
        guard history.goForward() != nil else { return }
        load(resetContent: true)
    }

    func goUp() {
        guard canGoUp, let url = currentURL else { return }
        if BrowserLocation.isVolumeRoot(url) {
            // Like Explorer: above a disk is the computer, not a folder.
            showComputer()
        } else {
            navigate(to: url.deletingLastPathComponent(), selecting: url)
        }
    }

    /// Shows the computer's overview: main folders, disks, network drives.
    func showComputer() {
        endEditingAddress()
        guard location != .computer else { return }
        history.go(to: .computer)
        load(resetContent: true)
    }

    func showTrash() {
        navigate(to: trashURL)
    }

    func goHome() {
        navigate(to: FileManager.default.homeDirectoryForCurrentUser)
    }

    func reload() {
        // On a drive's page, "reload" means "try the drive again".
        if let id = displayedDriveID {
            Task { await connectDrive(id) }
            return
        }
        if isOnComputer {
            computerRefreshes += 1
            return
        }
        sidebarTree.reload()
        load(resetContent: false)
    }

    /// The current folder changed on disk.
    private func contentChanged() {
        guard displayedDriveID == nil else { return }
        load(resetContent: false)
    }

    // MARK: - Search

    /// Whether the search field applies to what the window shows.
    var canSearch: Bool { operationFolder != nil }

    func focusSearch() {
        guard canSearch else { return }
        searchFocusRequests += 1
    }

    /// The search field is done with: the keyboard goes back to the list.
    func endSearchEditing() {
        listFocusRequests += 1
    }

    /// (Re)starts the search for the current text, or ends it if the text is
    /// empty. The previous results stay on screen until the new ones come, so
    /// that the list does not flicker while typing.
    private func startSearch() {
        searchTask?.cancel()
        searchTask = nil

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let folder = operationFolder else {
            let wasSearching = isSearching
            isSearching = false
            isSearchRunning = false
            searchItems = []
            if wasSearching { applyFilterAndSort() }
            return
        }

        if !isSearching {
            isSearching = true
            searchItems = []
            selection = []
            applyFilterAndSort()
        }
        isSearchRunning = true

        let hidden = showHidden
        searchTask = Task {
            var found: [FileItem] = []
            for await batch in FolderSearch.results(in: folder, query: query, showHidden: hidden) {
                if Task.isCancelled { return }
                found += batch.map(Self.normalized)
                searchItems = found
                applyFilterAndSort()
            }
            if Task.isCancelled { return }
            searchItems = found
            isSearchRunning = false
            applyFilterAndSort()
        }
    }

    /// Goes to the folder that holds the selected search result.
    func showSelectionInItsFolder() {
        guard selection.count == 1, let url = selection.first else { return }
        navigate(to: url.deletingLastPathComponent(), selecting: url)
    }

    // MARK: - Network drives

    /// Opens a network drive from the sidebar: its content when it is
    /// connected, otherwise its page, connecting it if its server answers.
    func openDrive(_ id: UUID) {
        guard let monitor = driveMonitor else { return }
        endEditingAddress()
        if case .mounted(let folder) = monitor.status(of: id) {
            navigate(to: folder)
            return
        }
        let target = BrowserLocation.drive(id)
        if target != location {
            history.go(to: target)
            load(resetContent: true)
        }
        guard monitor.status(of: id) != .connecting else { return }
        Task { await connectDrive(id) }
    }

    /// Checks the drive's server again and mounts the drive if it answers.
    func connectDrive(_ id: UUID) async {
        guard let monitor = driveMonitor else { return }
        await monitor.refresh()
        if monitor.status(of: id) == .available {
            await monitor.connect(id)
        }
        driveStatusesChanged()
    }

    /// Reacts to drives going online or offline. Called by the window
    /// whenever a drive status changes.
    func driveStatusesChanged() {
        guard let monitor = driveMonitor else { return }
        switch location {
        case .computer:
            break
        case .drive(let id):
            // The drive we were waiting for is connected: show its content.
            if case .mounted(let folder) = monitor.status(of: id) {
                history.replaceCurrent(with: .folder(Self.normalized(folder)))
                load(resetContent: true)
            }
        case .folder(let url):
            if let blocked = blockedDrive {
                if case .mounted = monitor.status(of: blocked) {
                    load(resetContent: true)
                }
            } else if let drive = monitor.drive(containing: url), monitor.status(of: drive.id) == .offline {
                load(resetContent: true)
            }
        }
    }

    // MARK: - Items

    var selectedItems: [FileItem] {
        items.filter { selection.contains($0.url) }
    }

    func open(_ itemsToOpen: [FileItem]) {
        if itemsToOpen.count == 1, let item = itemsToOpen.first, item.isBrowsable {
            navigate(to: item.url)
            return
        }
        for item in itemsToOpen where !item.isBrowsable {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openSelection() {
        open(selectedItems)
    }

    // MARK: - Properties

    /// Set to show the Properties sheet.
    var propertiesRequest: PropertiesRequest?

    /// What "Propriétés" describes: the selection, otherwise the folder
    /// shown.
    var propertiesTargets: [URL] {
        let selected = selectedItems.map(\.url)
        if !selected.isEmpty { return selected }
        return currentURL.map { [$0] } ?? []
    }

    func showProperties() {
        let urls = propertiesTargets
        guard !urls.isEmpty, displayedDriveID == nil, !isOnComputer else { return }
        propertiesRequest = PropertiesRequest(urls: urls)
    }

    // MARK: - Open with

    /// Finds applications and opens files with one. A property so that tests
    /// can replace it.
    @ObservationIgnored var openWith = OpenWith.live

    /// The files "Ouvrir avec…" acts on: the selection, when it holds only
    /// files (a folder is browsed, not opened with an application).
    var filesToOpenWith: [URL] {
        let selected = selectedItems
        guard !selected.isEmpty, selected.allSatisfy({ !$0.isBrowsable }) else { return [] }
        return selected.map(\.url)
    }

    /// Applications that can open the selection: those of the first file.
    func applicationsForSelection() -> [OpenWithApp] {
        guard let first = filesToOpenWith.first else { return [] }
        return openWith.applications(first)
    }

    func openSelection(with app: URL) {
        let files = filesToOpenWith
        guard !files.isEmpty else { return }
        openWith.open(files, app)
    }

    /// Lets the user pick any application in /Applications, then opens the
    /// selection with it.
    func chooseApplicationToOpenSelection() {
        guard !filesToOpenWith.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Ouvrir avec"
        panel.prompt = "Ouvrir"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let app = panel.url else { return }
        openSelection(with: app)
    }

    func setSort(_ newSort: FileSort) {
        guard newSort != sort else { return }
        sort = newSort
        applyFilterAndSort()
    }

    func setShowHidden(_ show: Bool) {
        guard show != showHidden else { return }
        showHidden = show
        applyFilterAndSort()
        if isSearching { startSearch() }
    }

    // MARK: - File operations

    /// The folder file operations act on, or `nil` on a drive's page.
    private var operationFolder: URL? {
        displayedDriveID == nil ? currentURL : nil
    }

    /// Whether files can be dropped on the list itself.
    var canDropIntoCurrentFolder: Bool {
        operationFolder != nil
    }

    var canPaste: Bool {
        operationFolder != nil && !isInTrash && clipboard.hasFiles
    }

    func copySelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard.copy(urls)
    }

    func cutSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard.cut(urls)
    }

    /// Pastes into the current folder: a move after a cut, a copy otherwise.
    func paste() {
        guard let folder = operationFolder, !isInTrash else { return }
        let content = clipboard.contents()
        guard !content.urls.isEmpty else { return }
        if content.isCut {
            perform(.move(sources: content.urls, to: folder), actionName: "le déplacement", activity: "Déplacement…") {
                [clipboard] in clipboard.clearCut()
            }
        } else {
            perform(.copy(sources: content.urls, to: folder), actionName: "la copie", activity: "Copie…")
        }
    }

    /// What dropping `urls` on `folder` would do with the keys held now, or
    /// `nil` when the drop is refused.
    static func dropMode(for urls: [URL], into folder: URL) -> TransferMode? {
        let modifiers = NSEvent.modifierFlags
        return DropPlan.mode(
            for: urls,
            into: folder,
            copyRequested: modifiers.contains(.option),
            moveRequested: modifiers.contains(.command)
        )
    }

    /// Files dropped on a folder, from this window, another one or another app.
    @discardableResult
    func drop(_ urls: [URL], into folder: URL, mode: TransferMode) -> Bool {
        guard !urls.isEmpty else { return false }
        if TrashFolder.isTrash(folder, trash: trashURL) {
            // Dropped on the Trash: what is not there yet goes to it, and
            // can be put back with Undo.
            let outside = urls.filter { !TrashFolder.contains($0, trash: trashURL) }
            guard !outside.isEmpty else { return false }
            trash(outside)
            return true
        }
        switch mode {
        case .copy:
            perform(.copy(sources: urls, to: folder), actionName: "la copie", activity: "Copie…")
        case .move:
            perform(.move(sources: urls, to: folder), actionName: "le déplacement", activity: "Déplacement…")
        }
        return true
    }

    /// Drop on the sidebar or on a folder, with the keys held at that moment.
    @discardableResult
    func drop(_ urls: [URL], into folder: URL) -> Bool {
        guard let mode = Self.dropMode(for: urls, into: folder) else { return false }
        return drop(urls, into: folder, mode: mode)
    }

    func trashSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        if isInTrash {
            // Already in the Trash: the only way out is to delete for good.
            askToDeleteSelection()
            return
        }
        trash(urls)
    }

    private func trash(_ urls: [URL]) {
        perform(.trash(urls), actionName: "la mise à la corbeille", activity: "Mise à la corbeille…")
    }

    /// Asks before emptying the Trash. Works from any page.
    func askToEmptyTrash() {
        let trash = trashURL
        Task {
            do {
                let urls = try await TrashFolder.contents(of: trash)
                if urls.isEmpty {
                    alert = OperationAlert(title: "La corbeille est vide", message: "Il n'y a rien à supprimer.")
                } else {
                    deleteConfirmation = DeleteConfirmation(urls: urls, becauseNoTrash: false, emptiesTrash: true)
                }
            } catch {
                alert = Self.trashAlert(for: error)
            }
        }
    }

    private static func trashAlert(for error: Error) -> OperationAlert {
        if TrashFolder.isPermissionDenied(error) {
            return OperationAlert(
                title: "BetterFinder ne peut pas lire la corbeille",
                message: "macOS protège la corbeille. Autorisez BetterFinder dans Réglages Système > Confidentialité et sécurité > Accès complet au disque, puis relancez l'app."
            )
        }
        return OperationAlert(title: "La corbeille est illisible", message: error.localizedDescription)
    }

    /// Asks before deleting the selection for good (Shift+Delete in Explorer).
    func askToDeleteSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        deleteConfirmation = DeleteConfirmation(urls: urls, becauseNoTrash: false)
    }

    func deletePermanently(_ urls: [URL]) {
        perform(.delete(urls), actionName: "la suppression", activity: "Suppression…")
    }

    func rename(_ url: URL, to newName: String) {
        guard newName != url.lastPathComponent else { return }
        perform(.rename(url, to: newName), actionName: "le renommage", activity: "Renommage…")
    }

    /// Asks the file list to edit the name of the single selected item.
    func renameSelection() {
        guard selection.count == 1, let url = selection.first else { return }
        renameRequestCount += 1
        renameRequest = RenameRequest(id: renameRequestCount, url: url)
    }

    func newFolder() {
        guard let folder = operationFolder, !isInTrash else { return }
        perform(
            .createFolder(in: folder, name: "Nouveau dossier"),
            actionName: "la création du dossier", activity: "Création…", renameCreated: true
        )
    }

    func newTextFile() {
        guard let folder = operationFolder, !isInTrash else { return }
        perform(
            .createFile(in: folder, name: "Nouveau document texte.txt"),
            actionName: "la création du document", activity: "Création…", renameCreated: true
        )
    }

    // MARK: - Put back

    /// Puts items back in the Trash's listing: replaced by tests.
    @ObservationIgnored var putBackRunner: TrashPutBack.Runner = TrashPutBack.osascript

    /// True when "Remettre" applies: the selection is at the top of the
    /// Trash (an item inside a trashed folder cannot be put back alone).
    var canRestoreSelection: Bool {
        isOnTrash && !selection.isEmpty
    }

    /// Puts the selected items of the Trash back where they came from.
    func restoreSelection() {
        guard canRestoreSelection else { return }
        let urls = selectedItems.map(\.url)
        runningOperations += 1
        activity = "Remise en place…"
        Task {
            let failure = await TrashPutBack.restore(urls, runner: putBackRunner)
            runningOperations -= 1
            if runningOperations == 0 { activity = nil }
            switch failure {
            case nil:
                break
            case .notAllowed:
                alert = OperationAlert(
                    title: "BetterFinder ne peut pas remettre les éléments",
                    message: "Pour remettre un élément à sa place, BetterFinder demande au Finder de le faire. Autorisez-le dans Réglages Système > Confidentialité et sécurité > Automatisation, en cochant Finder sous BetterFinder."
                )
            case .failed(let message):
                alert = OperationAlert(title: "Impossible de remettre l'élément", message: message)
            }
            load(resetContent: false)
        }
    }

    // MARK: - Compress

    /// True when the selection can be packed into a zip: not in the Trash,
    /// not on a drive's page.
    var canCompressSelection: Bool {
        guard operationFolder != nil, !isInTrash, !selection.isEmpty else { return false }
        // Search results can come from several folders; an archive needs one.
        return Set(selection.map { $0.deletingLastPathComponent().path }).count == 1
    }

    /// Packs the selection into a zip archive next to it (in the folder
    /// shown), then selects the archive.
    func compressSelection() {
        guard canCompressSelection, let folder = operationFolder else { return }
        let urls = selectedItems.map(\.url)
        perform(
            .compress(urls, in: folder, name: FileNaming.archiveName(for: urls.map(\.lastPathComponent))),
            actionName: "la compression", activity: "Compression…"
        )
    }

    /// Explorer's "Copy as path".
    func copyPathOfSelection() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else { return }
        clipboard.copyText(paths.joined(separator: "\n"))
    }

    /// True when the selection holds folders that are not favorites yet.
    var canAddSelectionToFavorites: Bool {
        let folders = selectedItems.filter(\.isBrowsable)
        return !folders.isEmpty && folders.contains { !FavoriteStore.shared.contains($0.url) }
    }

    func addSelectionToFavorites() {
        FavoriteStore.shared.add(selectedItems.filter(\.isBrowsable).map(\.url))
    }

    func revealSelectionInFinder() {
        let urls = selectedItems.map(\.url)
        if urls.isEmpty, let folder = currentURL {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    // MARK: - Terminal

    /// Opens folders in the user's terminal. A property so that tests can
    /// replace it.
    @ObservationIgnored var terminal = TerminalLauncher.live

    /// The folder shown, when a terminal can be opened in it: not on the
    /// computer's overview, a drive's page or in the Trash (macOS keeps
    /// its content out of reach).
    var terminalFolderHere: URL? {
        guard let folder = operationFolder, !isInTrash else { return nil }
        return folder
    }

    /// The folder "Ouvrir dans le terminal" acts on: the single selected
    /// folder, otherwise the folder shown.
    var terminalFolder: URL? {
        let selected = selectedItems
        if selected.count == 1, selected[0].isBrowsable, !isInTrash {
            return selected[0].url
        }
        return selected.isEmpty ? terminalFolderHere : nil
    }

    /// Opens a terminal window in `folder`, or in `terminalFolder`.
    func openInTerminal(_ folder: URL? = nil) {
        guard let folder = folder ?? terminalFolder else { return }
        terminal.open(folder) { [weak self] message in
            self?.alert = OperationAlert(title: "Impossible d'ouvrir le terminal", message: message)
        }
    }

    /// Runs an operation in the background and makes it undoable.
    ///
    /// The undo entry is registered right away, while the operation is still
    /// running: that is the only moment the undo manager can tell whether it
    /// belongs to the undo or to the redo stack. What it will actually do is
    /// filled in when the operation ends.
    private func perform(
        _ operation: FileOperation,
        actionName: String,
        activity: String,
        renameCreated: Bool = false,
        afterSuccess: (@MainActor () -> Void)? = nil
    ) {
        let record = UndoRecord()
        undoRecords.append(record)
        if let undoManager {
            undoManager.registerUndo(withTarget: record) { [weak self] record in
                MainActor.assumeIsolated {
                    self?.revert(record, actionName: actionName)
                }
            }
            undoManager.setActionName(actionName)
        }

        runningOperations += 1
        self.activity = activity

        Task {
            let outcome = await executor.run(operation)

            runningOperations -= 1
            if runningOperations == 0 {
                self.activity = nil
            }
            record.inverse = outcome.undo
            if outcome.undo == nil {
                // Nothing to undo: drop the entry registered up front.
                undoManager?.removeAllActions(withTarget: record)
                undoRecords.removeAll { $0 === record }
            }
            if let failure = outcome.failure {
                present(failure)
            } else {
                afterSuccess?()
            }

            // Show the result: select what was created here, then refresh.
            if let folder = operationFolder {
                let here = outcome.affected
                    .map(Self.normalized)
                    .filter { $0.deletingLastPathComponent().path == folder.path }
                if !here.isEmpty {
                    pendingSelection = Set(here)
                    pendingRename = renameCreated ? here.first : nil
                }
                load(resetContent: false)
            }
        }
    }

    private func revert(_ record: UndoRecord, actionName: String) {
        guard let operation = record.inverse else {
            // The operation is still running, or left nothing to undo.
            NSSound.beep()
            return
        }
        perform(operation, actionName: actionName, activity: "Annulation…")
    }

    private func present(_ failure: FileOperationFailure) {
        let name = failure.url?.lastPathComponent ?? ""
        switch failure.reason {
        case .trashUnavailable:
            // No Trash on this volume (typical of network shares): offer to
            // delete for good instead.
            deleteConfirmation = DeleteConfirmation(urls: failure.remaining, becauseNoTrash: true)
        case .nameTaken:
            alert = OperationAlert(
                title: "Ce nom est déjà utilisé",
                message: "Un élément nommé « \(name) » existe déjà à cet endroit."
            )
        case .invalidName(let problem):
            alert = OperationAlert(title: "Nom impossible", message: Self.explanation(of: problem))
        case .differentFolders:
            alert = OperationAlert(
                title: "Compression impossible",
                message: "Les éléments à compresser doivent être dans le même dossier."
            )
        case .intoItself:
            alert = OperationAlert(
                title: "Opération impossible",
                message: "Le dossier « \(name) » ne peut pas être copié ou déplacé dans lui-même."
            )
        case .system(let message):
            alert = OperationAlert(title: "L'opération a échoué", message: message)
        }
    }

    private static func explanation(of problem: FileNaming.Problem) -> String {
        switch problem {
        case .empty: "Le nom ne peut pas être vide."
        case .forbiddenCharacter: "Un nom ne peut contenir ni « / » ni « : »."
        case .reserved: "« . » et « .. » sont réservés par le système."
        }
    }

    // MARK: - Address bar

    /// Text put in the address field when editing starts.
    var addressText: String {
        switch location {
        case .computer:
            return Self.computerName
        case .folder(let url):
            return url.path
        case .drive(let id):
            return driveMonitor?.drive(id)?.url.absoluteString ?? ""
        }
    }

    func beginEditingAddress() {
        isEditingAddress = true
    }

    func endEditingAddress() {
        guard isEditingAddress else { return }
        isEditingAddress = false
        listFocusRequests += 1
    }

    /// Goes to what was typed in the address bar. Returns false when the
    /// text does not point to an existing file or folder, or to a share.
    func submitAddress(_ text: String) -> Bool {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.compare(Self.computerName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            showComputer()
            return true
        }
        let base = currentURL ?? FileManager.default.homeDirectoryForCurrentUser
        switch PathParser.parse(text, relativeTo: base) {
        case .invalid:
            return false

        case .remote(let address):
            guard NetworkDrive.url(fromAddress: address.absoluteString) != nil else { return false }
            if let drive = driveMonitor?.drives.first(where: { $0.pointsTo(address) }) {
                openDrive(drive.id)
            } else {
                // An unknown share: offer to add it as a network drive.
                endEditingAddress()
                driveEditor = DriveEditorRequest(address: address.absoluteString)
            }
            return true

        case .local(let url):
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return false
            }
            if isDirectory.boolValue {
                navigate(to: url)
            } else {
                navigate(to: url.deletingLastPathComponent(), selecting: Self.normalized(url))
            }
            return true
        }
    }

    // MARK: - Loading

    private func load(resetContent: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        // Going elsewhere ends the search.
        if resetContent, !searchText.isEmpty {
            searchText = ""
        }

        // A drive's page, or a folder on a drive whose server is gone: there
        // is nothing to list, and trying would only wait on a dead mount.
        guard case .folder(let url) = location else {
            showNoContent(blockedBy: nil)
            return
        }
        if let monitor = driveMonitor,
           let drive = monitor.drive(containing: url),
           monitor.status(of: drive.id) == .offline {
            showNoContent(blockedBy: drive.id)
            return
        }

        let wasBlocked = blockedDrive != nil
        blockedDrive = nil
        accessDenied = false
        if resetContent || wasBlocked {
            allItems = []
            items = []
            selection = []
            state = .loading
            // Inside the same working tree the branch stays on screen while
            // the new folder loads; elsewhere it no longer applies.
            if let root = gitInfo?.root, !Self.isInside(url, root) {
                gitInfo = nil
            }
            watcher.watch(url) { [weak self] in
                Task { @MainActor in self?.contentChanged() }
            }
        }

        pendingLoads += 1
        Task {
            defer { pendingLoads -= 1 }
            do {
                let listing = try await DirectoryLoader.load(url)
                guard generation == loadGeneration else { return }
                allItems = listing.items.map(Self.normalized)
                isLocalVolume = listing.isLocalVolume
                state = .loaded
                sidebarTree.folderLoaded(url, items: allItems)
                applyFilterAndSort()
                refreshGit()
                // The folder changed (files were moved, deleted…): the
                // results may be out of date.
                if isSearching { startSearch() }
                if !pendingSelection.isEmpty {
                    let found = pendingSelection.intersection(items.map(\.url))
                    pendingSelection = []
                    if !found.isEmpty {
                        selection = found
                    }
                }
                if let url = pendingRename {
                    pendingRename = nil
                    if items.contains(where: { $0.url == url }) {
                        renameRequestCount += 1
                        renameRequest = RenameRequest(id: renameRequestCount, url: url)
                    }
                }
            } catch {
                guard generation == loadGeneration else { return }
                allItems = []
                items = []
                selection = []
                accessDenied = TrashFolder.isPermissionDenied(error)
                state = .failed(error.localizedDescription)
                refreshGit()
            }
        }
    }

    private func showNoContent(blockedBy drive: UUID?) {
        watcher.stop()
        accessDenied = false
        blockedDrive = drive
        pendingSelection = []
        pendingRename = nil
        allItems = []
        items = []
        selection = []
        state = .loaded
        refreshGit()
    }

    // MARK: - Git

    /// Asks Git again about the folder shown. Called after each listing of
    /// the folder, when `.git` changes and when the app comes to the front.
    ///
    /// Git is never run on a network drive: it would read the whole working
    /// tree over the network, or wait on a server that is gone.
    func refreshGit() {
        gitGeneration += 1
        let generation = gitGeneration
        guard AppSettings.showsGitInfo,
              state == .loaded,
              isLocalVolume,
              let folder = operationFolder,
              driveMonitor?.drive(containing: folder) == nil
        else {
            if gitInfo != nil { gitInfo = nil }
            watchGit(nil)
            return
        }
        pendingGitReads += 1
        Task {
            defer { pendingGitReads -= 1 }
            let info = await GitReader.read(folder)
            guard generation == gitGeneration else { return }
            if info != gitInfo { gitInfo = info }
            watchGit(info?.root)
        }
    }

    /// Switches the repository of the folder shown to another branch.
    /// `remoteBranch` ("origin/name") creates the local branch following it.
    func switchBranch(to branch: String, remoteBranch: Bool = false) {
        guard let root = gitInfo?.root, branch != gitInfo?.status.branch else { return }
        runningOperations += 1
        activity = "Changement de branche…"
        Task {
            let failure = await GitReader.switchBranch(in: root, to: branch, remoteBranch: remoteBranch)
            runningOperations -= 1
            if runningOperations == 0 { activity = nil }
            if let failure {
                alert = OperationAlert(title: "Impossible de changer de branche", message: failure)
            }
            // The folder shown may not exist on the new branch: fall back
            // on the closest one that does.
            if var folder = operationFolder {
                var isDirectory: ObjCBool = false
                while folder.path != root.path, folder.path != "/",
                      !(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
                          && isDirectory.boolValue) {
                    folder = folder.deletingLastPathComponent()
                }
                if folder.path != operationFolder?.path {
                    navigate(to: folder)
                    return
                }
            }
            sidebarTree.reload()
            load(resetContent: false)
        }
    }

    private func watchGit(_ root: URL?) {
        guard root != gitWatchedRoot else { return }
        gitWatchedRoot = root
        guard let root else {
            gitWatcher.stop()
            return
        }
        gitWatcher.watch(root.appending(path: ".git")) { [weak self] in
            Task { @MainActor in self?.refreshGit() }
        }
    }

    private static func isInside(_ url: URL, _ root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }

    private func applyFilterAndSort() {
        let source = isSearching ? searchItems : allItems
        let visible = showHidden ? source : source.filter { !$0.isHidden }
        items = visible.sorted(by: sort)
        let urls = Set(items.map(\.url))
        if !selection.isSubset(of: urls) {
            selection.formIntersection(urls)
        }
    }

    // MARK: - URL normalization

    /// One spelling per location, so that URLs can be compared: no trailing
    /// slash, no "." or ".." segment.
    nonisolated static func normalized(_ url: URL) -> URL {
        URL(filePath: url.standardizedFileURL.path, directoryHint: .notDirectory)
    }

    nonisolated static func normalized(_ item: FileItem) -> FileItem {
        FileItem(
            url: normalized(item.url),
            name: item.name,
            isDirectory: item.isDirectory,
            isPackage: item.isPackage,
            isHidden: item.isHidden,
            size: item.size,
            modificationDate: item.modificationDate,
            kind: item.kind
        )
    }
}

/// What the network drive sheet is opened for.
/// How a folder is drawn.
enum ViewMode: String, CaseIterable {
    /// A sortable table: name, date, type, size.
    case details
    /// A grid of large icons.
    case icons

    static let defaultsKey = "ViewMode"

    static var saved: ViewMode {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ViewMode.init) ?? .details
    }

    var title: String {
        switch self {
        case .details: "Détails"
        case .icons: "Icônes"
        }
    }

    var symbol: String {
        switch self {
        case .details: "list.bullet"
        case .icons: "square.grid.2x2"
        }
    }
}

struct DriveEditorRequest: Identifiable {
    let id = UUID()
    /// The drive being edited, or `nil` to add a new one.
    var existing: NetworkDrive?
    /// Address to start with when adding a drive.
    var address = ""

    init(existing: NetworkDrive? = nil, address: String = "") {
        self.existing = existing
        self.address = address
    }
}

/// Asks the file list to start editing an item's name.
struct RenameRequest: Equatable {
    let id: Int
    let url: URL
}

/// An error shown in an alert.
struct OperationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Items about to be deleted for good, pending the user's confirmation.
struct DeleteConfirmation: Identifiable {
    let id = UUID()
    let urls: [URL]
    /// True when the question comes up because the volume has no Trash.
    let becauseNoTrash: Bool
    /// True when these are all the items of the Trash, which is being emptied.
    var emptiesTrash = false
}

/// One entry of the undo stack. `inverse` is filled when the operation it
/// undoes has finished.
@MainActor
private final class UndoRecord {
    var inverse: FileOperation?
}
