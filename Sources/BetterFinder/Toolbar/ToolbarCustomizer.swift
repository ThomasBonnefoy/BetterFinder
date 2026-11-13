import BetterFinderCore
import SwiftUI

/// The sheet where the user composes the toolbar, the way macOS does it: the
/// toolbar as it is on top, the buttons that are not in it below.
///
/// - Drag a button of the toolbar to move it; drop it before another button
///   or at the end.
/// - Drag a button or a space from below into the toolbar to add it.
/// - Drag a button out of the toolbar, onto the area below, to remove it.
///
/// Changes apply at once, in every window. Clicking a button below adds it at
/// the end, and the menu of a button of the toolbar moves or removes it, for
/// those who do not drag.
struct ToolbarCustomizer: View {
    @Environment(\.dismiss) private var dismiss
    var store = ToolbarLayoutStore.shared
    /// True while a button is held over the area below, which removes it.
    @State private var isOverPalette = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Personnaliser la barre d'outils")
                .font(.headline)
            Text("Glissez les boutons pour les ranger dans la barre d'outils. Les changements s'appliquent tout de suite.")
                .font(.callout)
                .foregroundStyle(.secondary)

            section("Barre d'outils") { strip }
            section("Éléments disponibles", hint: "Glissez-les dans la barre. Déposez ici un bouton de la barre pour le retirer.") {
                palette
            }

            HStack {
                Button("Rétablir par défaut") { store.reset() }
                Spacer()
                Button("Terminé") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    // MARK: - Toolbar

    private var strip: some View {
        FlowLayout(spacing: 8) {
            ForEach(store.layout.items, id: \.self) { item in
                ToolbarChip(item: item, isDashed: ToolbarLayout.isSpace(item))
                    .draggable(Payload.existing(item))
                    .modifier(DropBefore(target: item) { drop($0, before: item) })
                    .contextMenu { menu(for: item) }
            }
            // The end of the toolbar: what is dropped here goes last.
            EndOfToolbar { drop($0, before: nil) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder
    private func menu(for item: String) -> some View {
        Button("Reculer", systemImage: "chevron.left") { store.moveUp(item) }
            .disabled(!store.layout.canMoveUp(item))
        Button("Avancer", systemImage: "chevron.right") { store.moveDown(item) }
            .disabled(!store.layout.canMoveDown(item))
        Divider()
        Button("Retirer de la barre d'outils", systemImage: "minus.circle") { store.remove(item) }
    }

    // MARK: - Palette

    private var palette: some View {
        FlowLayout(spacing: 8) {
            ForEach(store.layout.available, id: \.self) { item in
                ToolbarChip(item: item, isDashed: false)
                    .draggable(Payload.existing(item))
                    .onTapGesture { store.add(item) }
                    .help("Glissez dans la barre d'outils, ou cliquez pour l'ajouter à la fin")
            }
            ToolbarChip(title: "Espace", symbol: "rectangle.split.2x1", isDashed: true)
                .draggable(Payload.newFixed)
                .onTapGesture { store.addSpace(.fixed) }
                .help("Un petit vide qui scinde les boutons en groupes")
            ToolbarChip(title: "Espace flexible", symbol: "arrow.left.and.right", isDashed: true)
                .draggable(Payload.newFlexible)
                .onTapGesture { store.addSpace(.flexible) }
                .help("Prend toute la place libre et pousse la suite à droite")
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        // Dropping a button of the toolbar here takes it out.
        .dropDestination(for: String.self) { payloads, _ in
            guard let item = Payload.existingItem(in: payloads) else { return false }
            store.remove(item)
            return true
        } isTargeted: { isOverPalette = $0 }
        .overlay {
            if isOverPalette {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.6), lineWidth: 2)
                    .padding(-10)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Dropping

    @discardableResult
    private func drop(_ payloads: [String], before target: String?) -> Bool {
        guard let payload = payloads.first else { return false }
        switch payload {
        case Payload.newFixed:
            store.addSpace(.fixed, before: target)
        case Payload.newFlexible:
            store.addSpace(.flexible, before: target)
        default:
            guard let item = Payload.existingItem(in: [payload]) else { return false }
            store.place(item, before: target)
        }
        return true
    }

    private func section(_ title: String, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// What travels while a button is dragged: text, so that it can only be
/// dropped where this sheet expects it.
private enum Payload {
    static let prefix = "betterfinder-toolbar:"
    static let newFixed = prefix + "new:fixed"
    static let newFlexible = prefix + "new:flexible"

    static func existing(_ item: String) -> String { prefix + item }

    /// The identifier of the existing item carried by one of `payloads`.
    static func existingItem(in payloads: [String]) -> String? {
        payloads.first { $0.hasPrefix(prefix) && !$0.hasPrefix(prefix + "new:") }
            .map { String($0.dropFirst(prefix.count)) }
    }
}

/// A button of the toolbar, drawn as a small label.
private struct ToolbarChip: View {
    let title: String
    let symbol: String
    let isDashed: Bool

    init(item: String, isDashed: Bool) {
        self.init(title: ToolbarItemInfo.title(of: item), symbol: ToolbarItemInfo.symbol(of: item), isDashed: isDashed)
    }

    init(title: String, symbol: String, isDashed: Bool) {
        self.title = title
        self.symbol = symbol
        self.isDashed = isDashed
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: isDashed ? [4, 3] : []))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Makes a button accept drops that go right before it, and shows where.
private struct DropBefore: ViewModifier {
    let target: String
    let action: ([String]) -> Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if isTargeted {
                    Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, -2).offset(x: -6)
                }
            }
            .dropDestination(for: String.self) { payloads, _ in
                action(payloads)
            } isTargeted: { isTargeted = $0 }
    }
}

/// The empty end of the toolbar, where a drop adds or moves a button last.
private struct EndOfToolbar: View {
    let action: ([String]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Color.clear
            .frame(width: 60, height: 30)
            .overlay(alignment: .leading) {
                if isTargeted {
                    Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, -2)
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { payloads, _ in
                action(payloads)
            } isTargeted: { isTargeted = $0 }
    }
}

/// Lays its views out in rows, moving to the next row when one does not fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in rows.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (frames, usedWidth, y + rowHeight)
    }
}
