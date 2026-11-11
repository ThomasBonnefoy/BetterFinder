import AppKit
import Quartz
import BetterFinderCore
import SwiftUI

/// The details list of a folder: an AppKit table, for sortable columns,
/// fast scrolling in big folders, in-place renaming and keyboard handling.
struct FileTableView: NSViewRepresentable {
    /// What the table shows. Passed by value so that SwiftUI refreshes the
    /// table whenever one of these changes.
    struct State {
        var folder: URL
        var items: [FileItem]
        var selection: Set<URL>
        var sort: FileSort
        var isLocalVolume: Bool
        var focusRequests: Int
        var cutURLs: Set<URL>
        var renameRequest: RenameRequest?
        /// Git state of the changed files and folders, by path.
        var gitStates: [String: GitFileState] = [:]
    }

    let model: BrowserModel
    var state: State

    func makeCoordinator() -> FileTableCoordinator {
        FileTableCoordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTable()
        table.style = .inset
        table.rowHeight = 24
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.autosaveName = "BetterFinder.FileTable"
        table.autosaveTableColumns = true

        for column in FileColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.defaultWidth
            tableColumn.minWidth = column.minWidth
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            if column == .size {
                tableColumn.headerCell.alignment = .right
            }
            table.addTableColumn(tableColumn)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        context.coordinator.attach(to: table)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(state)
    }
}

/// Columns of the details list.
enum FileColumn: String, CaseIterable {
    case name
    case dateModified
    case kind
    case size

    var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }

    var title: String {
        switch self {
        case .name: "Nom"
        case .dateModified: "Modifié le"
        case .kind: "Type"
        case .size: "Taille"
        }
    }

    var sortKey: SortKey {
        switch self {
        case .name: .name
        case .dateModified: .dateModified
        case .kind: .kind
        case .size: .size
        }
    }

    init(sortKey: SortKey) {
        switch sortKey {
        case .name: self = .name
        case .dateModified: self = .dateModified
        case .kind: self = .kind
        case .size: self = .size
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .name: 340
        case .dateModified: 150
        case .kind: 170
        case .size: 90
        }
    }

    var minWidth: CGFloat {
        self == .name ? 140 : 60
    }
}

/// Table view that lets its coordinator handle keys first, and that answers
/// the Edit menu (Cut, Copy, Paste, Delete) for the selected files.
final class FileTable: NSTableView, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    weak var coordinator: FileTableCoordinator?

    // MARK: Quick Look

    /// Shows or hides the Quick Look panel for the selected files.
    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else if !selectedRowIndexes.isEmpty {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// The selection changed: the panel follows it.
    func refreshQuickLook() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        coordinator?.model.selectedItems.count ?? 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let items = coordinator?.model.selectedItems, items.indices.contains(index) else { return nil }
        return items[index].url as NSURL
    }

    /// Arrow keys typed in the panel move the selection of the list, which
    /// the panel then follows.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode) else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if coordinator?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) {
        coordinator?.model.copySelection()
    }

    @objc func cut(_ sender: Any?) {
        coordinator?.model.cutSelection()
    }

    @objc func paste(_ sender: Any?) {
        coordinator?.model.paste()
    }

    @objc func delete(_ sender: Any?) {
        coordinator?.model.trashSelection()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(paste(_:)):
            return coordinator?.model.canPaste ?? false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
