import AppKit
import BetterFinderCore
import UniformTypeIdentifiers

/// One cell of the file table. The name column has an icon, the others are
/// plain text.
final class FileCellView: NSTableCellView {
    private let column: FileColumn
    /// Git state of the item, at the end of the name column.
    private var badge: GitBadgeView?

    init(column: FileColumn) {
        self.column = column
        super.init(frame: .zero)
        identifier = column.identifier

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
        label.font = column == .name
            ? .systemFont(ofSize: NSFont.systemFontSize)
            : .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = column == .name ? .labelColor : .secondaryLabelColor
        label.alignment = column == .size ? .right : .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label

        var constraints = [
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        if column == .name {
            let badge = GitBadgeView()
            addSubview(badge)
            self.badge = badge
            constraints += [
                badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                badge.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -4),
            ]

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            addSubview(icon)
            imageView = icon
            constraints += [
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            ]
        } else {
            constraints += [
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(with item: FileItem, isLocalVolume: Bool, isCut: Bool, gitState: GitFileState? = nil, showsExtension: Bool = true) {
        badge?.show(gitState, isFolder: item.isBrowsable)
        // Cut items are shown faded until they are pasted, as in Explorer.
        let alpha: CGFloat = isCut ? 0.45 : 1
        textField?.alphaValue = alpha
        imageView?.alphaValue = alpha
        switch column {
        case .name:
            textField?.stringValue = item.displayName(showsExtension: showsExtension)
            imageView?.image = FileIcon.image(for: item, isLocalVolume: isLocalVolume)
        case .dateModified:
            textField?.stringValue = item.modificationDate.map(FileFormat.date) ?? ""
        case .kind:
            textField?.stringValue = item.kind
        case .size:
            textField?.stringValue = item.size.map(FileFormat.size) ?? ""
        }
    }
}

extension FileCellView {
    /// Turns the name label into an editable field holding `name`.
    func beginEditing(name: String) {
        guard let field = textField else { return }
        field.stringValue = name
        field.alphaValue = 1
        field.isEditable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        // A long name scrolls while it is typed instead of being truncated.
        field.cell?.isScrollable = true
    }

    /// Turns the field back into a plain label.
    func endEditing() {
        guard let field = textField else { return }
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.cell?.isScrollable = false
        field.lineBreakMode = .byTruncatingMiddle
    }
}

enum FileIcon {
    /// On a local disk, asks macOS for the real icon of the file (app icons,
    /// custom folder icons). On a network share, uses a generic icon for the
    /// file type so that drawing a row never waits for the network.
    @MainActor
    static func image(for item: FileItem, isLocalVolume: Bool) -> NSImage {
        if isLocalVolume {
            return NSWorkspace.shared.icon(forFile: item.url.path)
        }
        if item.isBrowsable {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let type = UTType(filenameExtension: item.url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

enum FileFormat {
    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
