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
    private(set) var showHidden = false
    private(set) var isEditingAddress = false
    /// Incremented to ask the file list to take the keyboard focus.
    private(set) var listFocusRequests = 0
    /// Network drives, once the window has been given them.
    private(set) var driveMonitor: DriveMonitor?
    /// Set when the current folder is on a network drive that went offline:
    /// the drive's page is shown instead of a list that would never load.
    private(set) var blockedDrive: UUID?
    var selection: Set<URL> = []
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
    /// Items waiting for the user to confirm their permanent deletion.
    var deleteConfirmation: DeleteConfirmation?
    /// The window's undo manager, so that Edit > Undo covers file operations.
    @ObservationIgnored var undoManager: UndoManager?

    let clipboard: FileClipboard
    /// Folder tree of the sidebar. The tabs of the app share one.
    let sidebarTree: SidebarTreeModel
    /// Opens a folder, or the computer's overview, in a new tab. Set by the
    /// window.
    @ObservationIgnored var tabOpener: (@MainActor (BrowserLocation) -> Void)?

    @ObservationIgnored private var allItems: [FileItem] = []
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
    /// Undo entries of this window. The undo manager does not retain its
    /// targets, so they are kept alive here.
    @ObservationIgnored private var undoRecords: [UndoRecord] = []

    init(
        start: URL = FileManager.default.homeDirectoryForCurrentUser,
        clipboard: FileClipboard = .shared,
        sidebarTree: SidebarTreeModel = SidebarTreeModel()
    ) {
        history = NavigationHistory(start: .folder(Self.normalized(start)))
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

    /// Name of the computer's overview ("Ce PC" in Explorer).
    nonisolated static let computerName = "Ce Mac"

    /// True on the computer's overview.
    var isOnComputer: Bool { location == .computer }

    var title: String {
        switch location {
        case .computer:
            return Self.computerName
        case .folder(let url):
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
        tabOpener?(.computer)
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
            if let itemToSelect { selection = [itemToSelect] }
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

    func setSort(_ newSort: FileSort) {
        guard newSort != sort else { return }
        sort = newSort
        applyFilterAndSort()
    }

    func setShowHidden(_ show: Bool) {
        guard show != showHidden else { return }
        showHidden = show
        applyFilterAndSort()
    }

    // MARK: - File operations

    /// The folder file operations act on, or `nil` on a drive's page.
    private var operationFolder: URL? {
        displayedDriveID == nil ? currentURL : nil
    }

    var canPaste: Bool {
        operationFolder != nil && clipboard.hasFiles
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
        guard let folder = operationFolder else { return }
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

    func trashSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        perform(.trash(urls), actionName: "la mise à la corbeille", activity: "Mise à la corbeille…")
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
        guard let folder = operationFolder else { return }
        perform(
            .createFolder(in: folder, name: "Nouveau dossier"),
            actionName: "la création du dossier", activity: "Création…", renameCreated: true
        )
    }

    func newTextFile() {
        guard let folder = operationFolder else { return }
        perform(
            .createFile(in: folder, name: "Nouveau document texte.txt"),
            actionName: "la création du document", activity: "Création…", renameCreated: true
        )
    }

    /// Explorer's "Copy as path".
    func copyPathOfSelection() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else { return }
        clipboard.copyText(paths.joined(separator: "\n"))
    }

    func revealSelectionInFinder() {
        let urls = selectedItems.map(\.url)
        if urls.isEmpty, let folder = currentURL {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
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
        if resetContent || wasBlocked {
            allItems = []
            items = []
            selection = []
            state = .loading
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
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func showNoContent(blockedBy drive: UUID?) {
        watcher.stop()
        blockedDrive = drive
        pendingSelection = []
        pendingRename = nil
        allItems = []
        items = []
        selection = []
        state = .loaded
    }

    private func applyFilterAndSort() {
        let visible = showHidden ? allItems : allItems.filter { !$0.isHidden }
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
}

/// One entry of the undo stack. `inverse` is filled when the operation it
/// undoes has finished.
@MainActor
private final class UndoRecord {
    var inverse: FileOperation?
}
