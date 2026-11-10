import AppKit
import BetterFinderCore

/// Data source and delegate of the file table. Keeps the AppKit table in
/// sync with the SwiftUI state, in both directions, and handles what only
/// AppKit can do well: keys, the context menu and in-place renaming.
@MainActor
final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSMenuDelegate {
    let model: BrowserModel

    private weak var table: FileTable?
    private var folder: URL?
    private var items: [FileItem] = []
    private var isLocalVolume = true
    private var cutURLs: Set<URL> = []
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

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        table.menu = menu
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
        if state.items != items || state.cutURLs != cutURLs || state.isLocalVolume != isLocalVolume {
            items = state.items
            cutURLs = state.cutURLs
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
        cell.configure(with: item, isLocalVolume: isLocalVolume, isCut: cutURLs.contains(item.url))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing, let table else { return }
        model.selection = Set(selectedItems(in: table).map(\.url))
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

    /// Windows Explorer keys, with Option standing in for Alt.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let table else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.keyCode
        let hasSelection = !table.selectedRowIndexes.isEmpty

        if modifiers.isEmpty {
            switch key {
            case KeyCode.return, KeyCode.keypadEnter:
                guard hasSelection else { return false }
                model.open(selectedItems(in: table))
                return true
            case KeyCode.backspace:
                model.goBack()
                return true
            case KeyCode.forwardDelete:
                guard hasSelection else { return false }
                model.trashSelection()
                return true
            case KeyCode.f2:
                guard table.selectedRowIndexes.count == 1 else { return false }
                beginRename(row: table.selectedRow)
                return true
            case KeyCode.f5:
                model.reload()
                return true
            default:
                return false
            }
        }

        if modifiers == .shift, key == KeyCode.forwardDelete {
            guard hasSelection else { return false }
            model.askToDeleteSelection()
            return true
        }

        if modifiers == .option {
            switch key {
            case KeyCode.leftArrow:
                model.goBack()
                return true
            case KeyCode.rightArrow:
                model.goForward()
                return true
            case KeyCode.upArrow:
                model.goUp()
                return true
            default:
                return false
            }
        }

        if modifiers == .command {
            switch key {
            case KeyCode.return, KeyCode.keypadEnter:
                guard model.canOpenSelectionInNewTabs else { return false }
                model.openSelectionInNewTabs()
                return true
            case KeyCode.downArrow:
                guard hasSelection else { return false }
                model.open(selectedItems(in: table))
                return true
            case KeyCode.backspace:
                // The Finder's way to the Trash, for keyboards without Delete.
                guard hasSelection else { return false }
                model.trashSelection()
                return true
            default:
                return false
            }
        }

        if modifiers == [.command, .option], key == KeyCode.backspace {
            guard hasSelection else { return false }
            model.askToDeleteSelection()
            return true
        }

        return false
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table else { return }

        let row = table.clickedRow
        if items.indices.contains(row) {
            // Like Explorer, a right-click on an unselected item selects it.
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            buildItemMenu(menu, selectionCount: table.selectedRowIndexes.count)
        } else {
            table.deselectAll(nil)
            buildFolderMenu(menu)
        }
    }

    private func buildItemMenu(_ menu: NSMenu, selectionCount: Int) {
        menu.addItem(item("Ouvrir", #selector(menuOpen)))
        if model.canOpenSelectionInNewTabs {
            menu.addItem(item("Ouvrir dans un nouvel onglet", #selector(menuOpenInNewTab)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Couper", #selector(menuCut)))
        menu.addItem(item("Copier", #selector(menuCopy)))
        menu.addItem(.separator())
        menu.addItem(item("Renommer", #selector(menuRename), enabled: selectionCount == 1))
        menu.addItem(item("Mettre à la corbeille", #selector(menuTrash)))
        menu.addItem(.separator())
        menu.addItem(item("Copier le chemin d'accès", #selector(menuCopyPath)))
        menu.addItem(item("Afficher dans le Finder", #selector(menuReveal)))
    }

    private func buildFolderMenu(_ menu: NSMenu) {
        let new = NSMenuItem(title: "Nouveau", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(item("Dossier", #selector(menuNewFolder)))
        submenu.addItem(item("Document texte", #selector(menuNewTextFile)))
        new.submenu = submenu
        menu.addItem(new)
        menu.addItem(.separator())
        menu.addItem(item("Coller", #selector(menuPaste), enabled: model.canPaste))
        menu.addItem(.separator())
        menu.addItem(item("Actualiser", #selector(menuReload)))
        menu.addItem(item("Afficher dans le Finder", #selector(menuReveal)))
    }

    private func item(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func menuOpen() { model.openSelection() }
    @objc private func menuOpenInNewTab() { model.openSelectionInNewTabs() }
    @objc private func menuCut() { model.cutSelection() }
    @objc private func menuCopy() { model.copySelection() }
    @objc private func menuPaste() { model.paste() }
    @objc private func menuTrash() { model.trashSelection() }
    @objc private func menuCopyPath() { model.copyPathOfSelection() }
    @objc private func menuReveal() { model.revealSelectionInFinder() }
    @objc private func menuNewFolder() { model.newFolder() }
    @objc private func menuNewTextFile() { model.newTextFile() }
    @objc private func menuReload() { model.reload() }

    @objc private func menuRename() {
        guard let table, table.selectedRowIndexes.count == 1 else { return }
        beginRename(row: table.selectedRow)
    }
}

private enum KeyCode {
    static let `return`: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let f2: UInt16 = 120
    static let f5: UInt16 = 96
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
