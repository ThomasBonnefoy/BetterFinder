import AppKit
import BetterFinderCore
import SwiftUI

/// The details list of a folder: an AppKit table, for sortable columns,
/// fast scrolling in big folders and keyboard handling.
struct FileTableView: NSViewRepresentable {
    struct Actions {
        var selectionChanged: (Set<URL>) -> Void
        var sortChanged: (FileSort) -> Void
        var open: ([FileItem]) -> Void
        var goBack: () -> Void
        var goForward: () -> Void
        var goUp: () -> Void
        var reload: () -> Void
    }

    var folder: URL
    var items: [FileItem]
    var selection: Set<URL>
    var sort: FileSort
    var isLocalVolume: Bool
    var focusRequests: Int
    var actions: Actions

    func makeCoordinator() -> FileTableCoordinator {
        FileTableCoordinator(actions: actions)
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
        context.coordinator.actions = actions
        context.coordinator.update(
            folder: folder,
            items: items,
            selection: selection,
            sort: sort,
            isLocalVolume: isLocalVolume,
            focusRequests: focusRequests
        )
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

/// Table view that lets its coordinator handle keys first.
final class FileTable: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}
