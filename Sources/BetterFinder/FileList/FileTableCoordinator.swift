import AppKit
import BetterFinderCore

/// Data source and delegate of the file table. Keeps the AppKit table in
/// sync with the SwiftUI state, in both directions.
@MainActor
final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var actions: FileTableView.Actions

    private weak var table: FileTable?
    private var folder: URL?
    private var items: [FileItem] = []
    private var isLocalVolume = true
    private var focusRequests = 0
    private var hasTakenInitialFocus = false
    /// True while the table is being updated from the SwiftUI state, so that
    /// the resulting delegate calls are not reported back as user actions.
    private var isSyncing = false

    init(actions: FileTableView.Actions) {
        self.actions = actions
    }

    func attach(to table: FileTable) {
        self.table = table
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)
        table.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    func update(
        folder newFolder: URL,
        items newItems: [FileItem],
        selection: Set<URL>,
        sort: FileSort,
        isLocalVolume: Bool,
        focusRequests newFocusRequests: Int
    ) {
        guard let table else { return }
        isSyncing = true
        defer { isSyncing = false }

        self.isLocalVolume = isLocalVolume

        let folderChanged = newFolder != folder
        folder = newFolder
        if newItems != items {
            items = newItems
            table.reloadData()
        }
        if folderChanged, !items.isEmpty {
            table.scrollRowToVisible(0)
        }

        let wanted = IndexSet(items.indices.filter { selection.contains(items[$0].url) })
        if wanted != table.selectedRowIndexes {
            table.selectRowIndexes(wanted, byExtendingSelection: false)
            if let first = wanted.first {
                table.scrollRowToVisible(first)
            }
        }

        let key = FileColumn(sortKey: sort.key).rawValue
        let current = table.sortDescriptors.first
        if current?.key != key || current?.ascending != sort.ascending {
            table.sortDescriptors = [NSSortDescriptor(key: key, ascending: sort.ascending)]
        }

        if !hasTakenInitialFocus {
            hasTakenInitialFocus = true
            focusRequests = newFocusRequests
            takeFocus(fittingColumns: true)
        } else if newFocusRequests != focusRequests {
            focusRequests = newFocusRequests
            takeFocus(fittingColumns: false)
        }
    }

    private func takeFocus(fittingColumns: Bool) {
        // The window may not be ready during the first update.
        DispatchQueue.main.async { [weak table] in
            guard let table, let window = table.window else { return }
            if fittingColumns {
                // Saved column widths may not match the window any more:
                // without this, a few extra points show a horizontal scroller.
                table.sizeToFit()
            }
            window.makeFirstResponder(table)
        }
    }

    // MARK: - Data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    // MARK: - Delegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let column = FileColumn(rawValue: tableColumn.identifier.rawValue),
              items.indices.contains(row)
        else { return nil }

        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? FileCellView
            ?? FileCellView(column: column)
        cell.configure(with: items[row], isLocalVolume: isLocalVolume)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing, let table else { return }
        let urls = table.selectedRowIndexes.compactMap { row in
            items.indices.contains(row) ? items[row].url : nil
        }
        actions.selectionChanged(Set(urls))
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncing,
              let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let column = FileColumn(rawValue: key)
        else { return }
        actions.sortChanged(FileSort(key: column.sortKey, ascending: descriptor.ascending))
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        items.indices.contains(row) ? items[row].name : nil
    }

    // MARK: - Mouse and keyboard

    @objc private func rowDoubleClicked() {
        guard let table else { return }
        let row = table.clickedRow
        guard items.indices.contains(row) else { return }
        if table.selectedRowIndexes.contains(row) {
            actions.open(selectedItems(in: table))
        } else {
            actions.open([items[row]])
        }
    }

    private func selectedItems(in table: NSTableView) -> [FileItem] {
        table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    /// Windows Explorer keys, with Option standing in for Alt.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let table else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.keyCode

        if modifiers.isEmpty {
            switch key {
            case KeyCode.return, KeyCode.keypadEnter:
                let selected = selectedItems(in: table)
                guard !selected.isEmpty else { return false }
                actions.open(selected)
                return true
            case KeyCode.delete:
                actions.goBack()
                return true
            case KeyCode.f5:
                actions.reload()
                return true
            default:
                return false
            }
        }

        if modifiers == .option {
            switch key {
            case KeyCode.leftArrow:
                actions.goBack()
                return true
            case KeyCode.rightArrow:
                actions.goForward()
                return true
            case KeyCode.upArrow:
                actions.goUp()
                return true
            default:
                return false
            }
        }

        if modifiers == .command, key == KeyCode.downArrow {
            let selected = selectedItems(in: table)
            guard !selected.isEmpty else { return false }
            actions.open(selected)
            return true
        }

        return false
    }
}

private enum KeyCode {
    static let `return`: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let delete: UInt16 = 51
    static let f5: UInt16 = 96
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
