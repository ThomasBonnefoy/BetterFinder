import AppKit
import BetterFinderCore

/// Data source and delegate of the file table. Keeps the AppKit table in
/// sync with the SwiftUI state, in both directions, and handles what only
/// AppKit can do well: keys, the context menu and in-place renaming.
@MainActor
final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, FileListHost {
    let model: BrowserModel

    private weak var table: FileTable?
    private var folder: URL?
    private var items: [FileItem] = []
    private var isLocalVolume = true
    private var cutURLs: Set<URL> = []
    private var gitStates: [String: GitFileState] = [:]
    private var focusRequests = 0
    private var hasAppliedFirstState = false
    private var handledRenameRequest: Int?
    /// True while the table is being updated from the SwiftUI state, so that
    /// the resulting delegate calls are not reported back as user actions.
    private var isSyncing = false

    /// The item whose name is being edited, if any.
    private var renamingURL: URL?
    /// Last state received. While a name is being edited the table is left
    /// alone (reloading it would close the editor); this is applied after.
    private var latestState: FileTableView.State?

    private var contextMenu: FileContextMenu?

    init(model: BrowserModel) {
        self.model = model
    }

    func attach(to table: FileTable) {
        self.table = table
        table.coordinator = self
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)
        table.registerForDraggedTypes([.fileURL])
        // Out of the window the Finder and others get a copy; inside, a move.
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .generic], forLocal: false)

        let contextMenu = FileContextMenu(
            model: model,
            target: { [weak self] in self?.prepareContextMenu() ?? .background },
            rename: { [weak self] in self?.beginRenameOfSelection() },
            quickLook: { [weak self] in self?.toggleQuickLook() }
        )
        self.contextMenu = contextMenu
        table.menu = contextMenu.makeMenu()
    }

    // MARK: - File list host

    var selectedFileItems: [FileItem] {
        guard let table else { return [] }
        return selectedItems(in: table)
    }

    func beginRenameOfSelection() {
        guard let table, table.selectedRowIndexes.count == 1 else { return }
        beginRename(row: table.selectedRow)
    }

    func toggleQuickLook() {
        table?.toggleQuickLook()
    }

    // MARK: - State from SwiftUI

    func update(_ state: FileTableView.State) {
        latestState = state
        guard renamingURL == nil else { return }
        apply(state)
    }

    private func apply(_ state: FileTableView.State) {
        guard let table else { return }
        isSyncing = true
        defer { isSyncing = false }

        let folderChanged = state.folder != folder
        folder = state.folder
        if state.items != items || state.cutURLs != cutURLs || state.isLocalVolume != isLocalVolume
            || state.gitStates != gitStates {
            items = state.items
            cutURLs = state.cutURLs
            gitStates = state.gitStates
            isLocalVolume = state.isLocalVolume
            table.reloadData()
        }
        if folderChanged, !items.isEmpty {
            table.scrollRowToVisible(0)
        }

        let wanted = IndexSet(items.indices.filter { state.selection.contains(items[$0].url) })
        if wanted != table.selectedRowIndexes {
            table.selectRowIndexes(wanted, byExtendingSelection: false)
            if let first = wanted.first {
                table.scrollRowToVisible(first)
            }
        }

        let key = FileColumn(sortKey: state.sort.key).rawValue
        let current = table.sortDescriptors.first
        if current?.key != key || current?.ascending != state.sort.ascending {
            table.sortDescriptors = [NSSortDescriptor(key: key, ascending: state.sort.ascending)]
        }

        if !hasAppliedFirstState {
            hasAppliedFirstState = true
            focusRequests = state.focusRequests
            // A request older than this table is not for it.
            handledRenameRequest = state.renameRequest?.id
            takeFocus(fittingColumns: true)
        } else if state.focusRequests != focusRequests {
            focusRequests = state.focusRequests
            takeFocus(fittingColumns: false)
        }

        if let request = state.renameRequest, request.id != handledRenameRequest {
            handledRenameRequest = request.id
            // Once the table has laid out the rows it was just given.
            DispatchQueue.main.async { [weak self] in
                self?.beginRename(of: request.url)
            }
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
        let item = items[row]
        cell.configure(
            with: item,
            isLocalVolume: isLocalVolume,
            isCut: cutURLs.contains(item.url),
            gitState: gitStates[item.url.path]
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing, let table else { return }
        model.selection = Set(selectedItems(in: table).map(\.url))
        table.refreshQuickLook()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncing,
              let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let column = FileColumn(rawValue: key)
        else { return }
        model.setSort(FileSort(key: column.sortKey, ascending: descriptor.ascending))
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        items.indices.contains(row) ? items[row].name : nil
    }

    private func selectedItems(in table: NSTableView) -> [FileItem] {
        table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    // MARK: - Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard items.indices.contains(row) else { return nil }
        return items[row].url as NSURL
    }

    /// The folder a drop at this position lands in: the folder under the
    /// pointer, else the one shown.
    private func dropTarget(row: Int, operation: NSTableView.DropOperation) -> URL? {
        if operation == .on, items.indices.contains(row), items[row].isBrowsable {
            return items[row].url
        }
        return model.canDropIntoCurrentFolder ? folder : nil
    }

    private func droppedURLs(_ info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation operation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard let target = dropTarget(row: row, operation: operation),
              let mode = BrowserModel.dropMode(for: droppedURLs(info), into: target)
        else { return [] }
        // Highlight the folder under the pointer, else the whole list.
        if target == folder {
            tableView.setDropRow(-1, dropOperation: .on)
        } else {
            tableView.setDropRow(row, dropOperation: .on)
        }
        return mode == .copy ? .copy : .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation operation: NSTableView.DropOperation
    ) -> Bool {
        guard let target = dropTarget(row: row, operation: operation) else { return false }
        return model.drop(droppedURLs(info), into: target)
    }

    // MARK: - Mouse

    @objc private func rowDoubleClicked() {
        guard let table else { return }
        let row = table.clickedRow
        guard items.indices.contains(row) else { return }
        // Like in the Finder, Command opens a folder in a new tab.
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true, items[row].isBrowsable {
            model.openInNewTab(items[row].url)
            return
        }
        if table.selectedRowIndexes.contains(row) {
            model.open(selectedItems(in: table))
        } else {
            model.open([items[row]])
        }
    }

    // MARK: - Keyboard

    func handleKey(_ event: NSEvent) -> Bool {
        FileListKeys.handle(event, host: self)
    }

    // MARK: - Renaming in place

    private func beginRename(of url: URL) {
        guard let row = items.firstIndex(where: { $0.url == url }) else { return }
        beginRename(row: row)
    }

    private func beginRename(row: Int) {
        guard let table, renamingURL == nil, items.indices.contains(row), let window = table.window else { return }
        let column = table.column(withIdentifier: FileColumn.name.identifier)
        guard column >= 0 else { return }
        table.scrollRowToVisible(row)
        guard let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as? FileCellView,
              let field = cell.textField
        else { return }

        let item = items[row]
        // Folders are listed under their localized name ("Bureau"): what is
        // edited is the real name on disk.
        let name = item.url.lastPathComponent
        renamingURL = item.url
        cell.beginEditing(name: name)
        field.delegate = self
        guard window.makeFirstResponder(field) else {
            finishRename(field)
            return
        }
        // Like Explorer: select the name, leave the extension alone.
        let base = FileNaming.split(name, isDirectory: item.isDirectory).base
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    /// Puts the cell and the table back to normal after an edit.
    private func finishRename(_ field: NSTextField) {
        renamingURL = nil
        field.delegate = nil
        (field.superview as? FileCellView)?.endEditing()
        if let table {
            // Shows the listed name again until the folder is reloaded.
            let row = table.row(for: field)
            let column = table.column(withIdentifier: FileColumn.name.identifier)
            if row >= 0, column >= 0 {
                table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: column))
            }
        }
        if let latestState {
            apply(latestState)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let url = renamingURL else { return }
        let newName = field.stringValue
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        finishRename(field)
        if movement == NSTextMovement.return.rawValue {
            // Enter validated the name: give the keyboard back to the list.
            // Otherwise the user clicked somewhere else, which keeps focus.
            table?.window?.makeFirstResponder(table)
        }
        model.rename(url, to: newName)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)),
              renamingURL != nil,
              let field = control as? NSTextField
        else { return false }
        // Escape: drop the edit without renaming.
        field.abortEditing()
        finishRename(field)
        table?.window?.makeFirstResponder(table)
        return true
    }

    // MARK: - Context menu

    /// Like Explorer, a right-click on an unselected item selects it; one on
    /// the empty space selects nothing.
    private func prepareContextMenu() -> FileContextMenu.Target {
        guard let table else { return .background }
        let row = table.clickedRow
        if items.indices.contains(row) {
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            return .items(count: table.selectedRowIndexes.count)
        }
        table.deselectAll(nil)
        return .background
    }
}
