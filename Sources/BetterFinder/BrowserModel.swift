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
    /// Non-nil while the "add or edit a network drive" sheet is open.
    var driveEditor: DriveEditorRequest?

    @ObservationIgnored private var allItems: [FileItem] = []
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var pendingSelection: URL?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let watcher = DirectoryWatcher()

    init(start: URL = FileManager.default.homeDirectoryForCurrentUser) {
        history = NavigationHistory(start: .folder(Self.normalized(start)))
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

    var title: String {
        switch location {
        case .folder(let url):
            return driveMonitor?.driveMounted(at: url)?.name ?? DisplayName.of(url)
        case .drive(let id):
            return driveMonitor?.drive(id)?.name ?? "Lecteur réseau"
        }
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var canGoUp: Bool {
        guard let url = currentURL else { return false }
        return url.path != "/"
    }

    /// Gives the window its network drives. Called once, before `start`.
    func attach(_ monitor: DriveMonitor) {
        driveMonitor = monitor
    }

    /// Loads the first folder. Called once, when the window appears.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        load(resetContent: true)
    }

    func navigate(to url: URL, selecting itemToSelect: URL? = nil) {
        let target = BrowserLocation.folder(Self.normalized(url))
        endEditingAddress()
        guard target != location else {
            if let itemToSelect { selection = [itemToSelect] }
            return
        }
        history.go(to: target)
        pendingSelection = itemToSelect
        load(resetContent: true)
    }

    func goBack() {
        let left = currentURL
        guard history.goBack() != nil else { return }
        // Like Explorer: coming back selects the folder we just left.
        if let left, let current = currentURL, left.deletingLastPathComponent().path == current.path {
            pendingSelection = left
        } else {
            pendingSelection = nil
        }
        load(resetContent: true)
    }

    func goForward() {
        guard history.goForward() != nil else { return }
        load(resetContent: true)
    }

    func goUp() {
        guard canGoUp, let url = currentURL else { return }
        navigate(to: url.deletingLastPathComponent(), selecting: url)
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

    // MARK: - Address bar

    /// Text put in the address field when editing starts.
    var addressText: String {
        switch location {
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
                Task { @MainActor in self?.reload() }
            }
        }

        Task {
            do {
                let listing = try await DirectoryLoader.load(url)
                guard generation == loadGeneration else { return }
                allItems = listing.items.map(Self.normalized)
                isLocalVolume = listing.isLocalVolume
                state = .loaded
                applyFilterAndSort()
                if let pending = pendingSelection {
                    pendingSelection = nil
                    if items.contains(where: { $0.url == pending }) {
                        selection = [pending]
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
        pendingSelection = nil
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

    nonisolated private static func normalized(_ item: FileItem) -> FileItem {
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
