import AppKit
import BetterFinderCore
import Quartz
import SwiftUI

/// The icons view of a folder: a grid of large icons with their names, like
/// the Finder's icon view. Takes the same state as the details list.
struct FileIconsView: NSViewRepresentable {
    let model: BrowserModel
    var state: FileTableView.State

    func makeCoordinator() -> FileIconsCoordinator {
        FileIconsCoordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 96, height: 96)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let collection = FileCollectionView()
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.textBackgroundColor]
        collection.register(FileIconItem.self, forItemWithIdentifier: FileIconItem.identifier)

        let scrollView = NSScrollView()
        scrollView.documentView = collection
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        context.coordinator.attach(to: collection)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(state)
    }
}

/// Collection view that lets its coordinator handle keys first, and answers
/// the Edit menu for the selected files, like the details list.
final class FileCollectionView: NSCollectionView, NSUserInterfaceValidations, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    weak var coordinator: FileIconsCoordinator?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if coordinator?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    /// A click on the empty space selects nothing.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        if indexPathForItem(at: convert(event.locationInWindow, from: nil)) == nil {
            deselectAll(nil)
            coordinator?.selectionChangedByUser()
        }
    }

    @objc func copy(_ sender: Any?) { coordinator?.model.copySelection() }
    @objc func cut(_ sender: Any?) { coordinator?.model.cutSelection() }
    @objc func paste(_ sender: Any?) { coordinator?.model.paste() }
    @objc func delete(_ sender: Any?) { coordinator?.model.trashSelection() }
    @objc override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        coordinator?.selectionChangedByUser()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return !selectionIndexPaths.isEmpty
        case #selector(paste(_:)):
            return coordinator?.model.canPaste ?? false
        default:
            return true
        }
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else if !selectionIndexPaths.isEmpty {
            panel.makeKeyAndOrderFront(nil)
        }
    }

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

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode) else { return false }
        keyDown(with: event)
        return true
    }
}

// MARK: - Item

/// One icon of the grid: the file's icon with its name below.
final class FileIconItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileIconItem")

    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let background = NSView()
    /// Called by a double-click on the item.
    var onOpen: (() -> Void)?

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override func loadView() {
        view = ClickableView { [weak self] in self?.onOpen?() }
        view.wantsLayer = true

        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(icon)

        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 12)
        label.isSelectable = false
        label.drawsBackground = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            icon.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
    }

    /// The text field of the name, for in-place renaming.
    var nameField: NSTextField { label }

    @MainActor
    func configure(with item: FileItem, isLocalVolume: Bool, isCut: Bool) {
        icon.image = FileIcon.image(for: item, isLocalVolume: isLocalVolume)
        label.stringValue = item.name
        let alpha: CGFloat = isCut ? 0.45 : 1
        icon.alphaValue = alpha
        label.alphaValue = alpha
        updateSelectionAppearance()
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        background.layer?.backgroundColor = isSelected
            ? NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.6).cgColor
            : NSColor.clear.cgColor
        if label.isEditable { return }
        label.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        label.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
    }

    func beginEditing(name: String) {
        label.stringValue = name
        label.alphaValue = 1
        label.isEditable = true
        label.isSelectable = true
        label.drawsBackground = true
        label.backgroundColor = .textBackgroundColor
        label.textColor = .labelColor
        label.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func endEditing() {
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        updateSelectionAppearance()
    }
}

/// View that reports double-clicks and lets the click through to the grid.
private final class ClickableView: NSView {
    private let onDoubleClick: () -> Void

    init(onDoubleClick: @escaping () -> Void) {
        self.onDoubleClick = onDoubleClick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 { onDoubleClick() }
    }
}

// MARK: - Coordinator

/// Data source and delegate of the icon grid. Keeps it in sync with the
/// SwiftUI state in both directions, like the table's coordinator.
@MainActor
final class FileIconsCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate,
    NSTextFieldDelegate, FileListHost {
    let model: BrowserModel

    private weak var collection: FileCollectionView?
    private var folder: URL?
    private var items: [FileItem] = []
    private var isLocalVolume = true
    private var cutURLs: Set<URL> = []
    private var focusRequests = 0
    private var hasAppliedFirstState = false
    private var handledRenameRequest: Int?
    private var isSyncing = false
    private var renamingURL: URL?
    private var latestState: FileTableView.State?
    private var contextMenu: FileContextMenu?

    init(model: BrowserModel) {
        self.model = model
    }

    func attach(to collection: FileCollectionView) {
        self.collection = collection
        collection.coordinator = self
        collection.dataSource = self
        collection.delegate = self
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        collection.setDraggingSourceOperationMask([.copy, .generic], forLocal: false)

        let contextMenu = FileContextMenu(
            model: model,
            target: { [weak self] in self?.prepareContextMenu() ?? .background },
            rename: { [weak self] in self?.beginRenameOfSelection() },
            quickLook: { [weak self] in self?.toggleQuickLook() }
        )
        self.contextMenu = contextMenu
        collection.menu = contextMenu.makeMenu()
    }

    // MARK: State from SwiftUI

    func update(_ state: FileTableView.State) {
        latestState = state
        guard renamingURL == nil else { return }
        apply(state)
    }

    private func apply(_ state: FileTableView.State) {
        guard let collection else { return }
        isSyncing = true
        defer { isSyncing = false }

        let folderChanged = state.folder != folder
        folder = state.folder
        if state.items != items || state.cutURLs != cutURLs || state.isLocalVolume != isLocalVolume {
            items = state.items
            cutURLs = state.cutURLs
            isLocalVolume = state.isLocalVolume
            collection.reloadData()
        }
        if folderChanged, !items.isEmpty {
            collection.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
        }

        let wanted = Set(items.indices.filter { state.selection.contains(items[$0].url) }.map { IndexPath(item: $0, section: 0) })
        if wanted != collection.selectionIndexPaths {
            collection.selectionIndexPaths = wanted
            if let first = wanted.sorted().first {
                collection.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge)
            }
        }

        if !hasAppliedFirstState {
            hasAppliedFirstState = true
            focusRequests = state.focusRequests
            handledRenameRequest = state.renameRequest?.id
            takeFocus()
        } else if state.focusRequests != focusRequests {
            focusRequests = state.focusRequests
            takeFocus()
        }

        if let request = state.renameRequest, request.id != handledRenameRequest {
            handledRenameRequest = request.id
            DispatchQueue.main.async { [weak self] in
                self?.beginRename(of: request.url)
            }
        }
    }

    private func takeFocus() {
        DispatchQueue.main.async { [weak collection] in
            guard let collection, let window = collection.window else { return }
            window.makeFirstResponder(collection)
        }
    }

    // MARK: Data source

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: FileIconItem.identifier, for: indexPath)
        guard let cell = cell as? FileIconItem, items.indices.contains(indexPath.item) else { return cell }
        let item = items[indexPath.item]
        cell.configure(with: item, isLocalVolume: isLocalVolume, isCut: cutURLs.contains(item.url))
        cell.onOpen = { [weak self] in
            guard let self else { return }
            // Like in the Finder, Command opens a folder in a new tab.
            if NSEvent.modifierFlags.contains(.command), item.isBrowsable {
                self.model.openInNewTab(item.url)
            } else if self.model.selection.contains(item.url) {
                self.model.open(self.selectedFileItems)
            } else {
                self.model.open([item])
            }
        }
        return cell
    }

    // MARK: Selection

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionChangedByUser()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionChangedByUser()
    }

    func selectionChangedByUser() {
        guard !isSyncing, let collection else { return }
        model.selection = Set(collection.selectionIndexPaths.compactMap {
            items.indices.contains($0.item) ? items[$0.item].url : nil
        })
        collection.refreshQuickLook()
    }

    // MARK: File list host

    var selectedFileItems: [FileItem] {
        guard let collection else { return [] }
        return collection.selectionIndexPaths.sorted().compactMap {
            items.indices.contains($0.item) ? items[$0.item] : nil
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        FileListKeys.handle(event, host: self)
    }

    func toggleQuickLook() {
        collection?.toggleQuickLook()
    }

    // MARK: Drag and drop

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        items.indices.contains(indexPath.item) ? items[indexPath.item].url as NSURL : nil
    }

    private func droppedURLs(_ info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    /// The folder a drop lands in: the folder under the pointer, else the
    /// one shown.
    private func dropTarget(at indexPath: IndexPath, operation: NSCollectionView.DropOperation) -> URL? {
        if operation == .on, items.indices.contains(indexPath.item), items[indexPath.item].isBrowsable {
            return items[indexPath.item].url
        }
        return model.canDropIntoCurrentFolder ? folder : nil
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let index = IndexPath(item: proposedDropIndexPath.pointee.item, section: 0)
        guard let target = dropTarget(at: index, operation: proposedDropOperation.pointee),
              let mode = BrowserModel.dropMode(for: droppedURLs(draggingInfo), into: target)
        else { return [] }
        if target == folder {
            // Not on a folder: the drop is for the whole view.
            proposedDropOperation.pointee = .before
            proposedDropIndexPath.pointee = IndexPath(item: items.count, section: 0) as NSIndexPath
        }
        return mode == .copy ? .copy : .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: any NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let target = dropTarget(at: indexPath, operation: dropOperation) else { return false }
        return model.drop(droppedURLs(draggingInfo), into: target)
    }

    // MARK: Context menu

    private func prepareContextMenu() -> FileContextMenu.Target {
        guard let collection, let event = NSApp.currentEvent else { return .background }
        let point = collection.convert(event.locationInWindow, from: nil)
        if let path = collection.indexPathForItem(at: point), items.indices.contains(path.item) {
            if !collection.selectionIndexPaths.contains(path) {
                collection.selectionIndexPaths = [path]
                selectionChangedByUser()
            }
            return .items(count: collection.selectionIndexPaths.count)
        }
        collection.deselectAll(nil)
        selectionChangedByUser()
        return .background
    }

    // MARK: Renaming in place

    func beginRenameOfSelection() {
        guard let collection, collection.selectionIndexPaths.count == 1,
              let path = collection.selectionIndexPaths.first else { return }
        beginRename(row: path.item)
    }

    private func beginRename(of url: URL) {
        guard let row = items.firstIndex(where: { $0.url == url }) else { return }
        beginRename(row: row)
    }

    private func beginRename(row: Int) {
        guard let collection, renamingURL == nil, items.indices.contains(row), let window = collection.window else { return }
        let path = IndexPath(item: row, section: 0)
        collection.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        guard let cell = collection.item(at: path) as? FileIconItem else { return }

        let item = items[row]
        // Folders are listed under their localized name: what is edited is
        // the real name on disk.
        let name = item.url.lastPathComponent
        renamingURL = item.url
        cell.beginEditing(name: name)
        let field = cell.nameField
        field.delegate = self
        guard window.makeFirstResponder(field) else {
            finishRename(field)
            return
        }
        let base = FileNaming.split(name, isDirectory: item.isDirectory).base
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    private func finishRename(_ field: NSTextField) {
        renamingURL = nil
        field.delegate = nil
        if let cell = field.superview?.nextResponder as? FileIconItem {
            cell.endEditing()
        } else if let cell = collection?.visibleItems().compactMap({ $0 as? FileIconItem }).first(where: { $0.nameField === field }) {
            cell.endEditing()
        }
        collection?.reloadData()
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
            collection?.window?.makeFirstResponder(collection)
        }
        model.rename(url, to: newName)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)),
              renamingURL != nil,
              let field = control as? NSTextField
        else { return false }
        field.abortEditing()
        finishRename(field)
        collection?.window?.makeFirstResponder(collection)
        return true
    }
}
