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

    private(set) var history: NavigationHistory<URL>
    /// Entries of the current folder, filtered and sorted for display.
    private(set) var items: [FileItem] = []
    private(set) var state: LoadState = .loading
    private(set) var isLocalVolume = true
    private(set) var sort = FileSort()
    private(set) var showHidden = false
    private(set) var isEditingAddress = false
    /// Incremented to ask the file list to take the keyboard focus.
    private(set) var listFocusRequests = 0
    var selection: Set<URL> = []

    @ObservationIgnored private var allItems: [FileItem] = []
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var pendingSelection: URL?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let watcher = DirectoryWatcher()

    init(start: URL = FileManager.default.homeDirectoryForCurrentUser) {
        history = NavigationHistory(start: Self.normalized(start))
    }

    // MARK: - Location

    var currentURL: URL { history.current }
    var title: String { DisplayName.of(currentURL) }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var canGoUp: Bool { currentURL.path != "/" }

    /// Loads the first folder. Called once, when the window appears.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        load(resetContent: true)
    }

    func navigate(to url: URL, selecting itemToSelect: URL? = nil) {
        let target = Self.normalized(url)
        endEditingAddress()
        guard target != currentURL else {
            if let itemToSelect { selection = [itemToSelect] }
            return
        }
        history.go(to: target)
        pendingSelection = itemToSelect
        load(resetContent: true)
    }

    func goBack() {
        let child = currentURL
        guard history.goBack() != nil else { return }
        // Like Explorer: coming back selects the folder we just left.
        pendingSelection = child.deletingLastPathComponent().path == currentURL.path ? child : nil
        load(resetContent: true)
    }

    func goForward() {
        guard history.goForward() != nil else { return }
        load(resetContent: true)
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: currentURL.deletingLastPathComponent(), selecting: currentURL)
    }

    func goHome() {
        navigate(to: FileManager.default.homeDirectoryForCurrentUser)
    }

    func reload() {
        load(resetContent: false)
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

    func beginEditingAddress() {
        isEditingAddress = true
    }

    func endEditingAddress() {
        guard isEditingAddress else { return }
        isEditingAddress = false
        listFocusRequests += 1
    }

    /// Goes to the path typed in the address bar. Returns false when the
    /// text does not point to an existing file or folder.
    func submitAddress(_ text: String) -> Bool {
        guard case .local(let url) = PathParser.parse(text, relativeTo: currentURL) else {
            return false
        }
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

    // MARK: - Loading

    private func load(resetContent: Bool) {
        loadGeneration += 1
        let generation = loadGeneration
        let url = currentURL

        if resetContent {
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
