import AppKit
import BetterFinderCore
import QuickLookUI
import SwiftUI

/// The pane on the right of the list ("Panneau d'aperçu" of Explorer): a
/// preview of the selected item and its main details.
struct PreviewPane: View {
    let model: BrowserModel

    /// Width of the pane.
    static let width: CGFloat = 300

    var body: some View {
        let selected = model.selectedItems
        VStack(spacing: 0) {
            if selected.count == 1, let item = selected.first {
                single(item)
            } else if selected.count > 1 {
                placeholder(
                    icon: "square.on.square",
                    title: "\(selected.count) éléments sélectionnés",
                    detail: StatusBar.selectionDetail(selected)
                )
            } else {
                placeholder(
                    icon: "doc.text.magnifyingglass",
                    title: "Aucune sélection",
                    detail: "Sélectionnez un élément pour voir son aperçu."
                )
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - One item

    private func single(_ item: FileItem) -> some View {
        VStack(spacing: 0) {
            preview(of: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(3)
                    .textSelection(.enabled)
                ForEach(Self.details(of: item), id: \.label) { detail in
                    HStack(alignment: .firstTextBaseline) {
                        Text(detail.label).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(detail.value).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    .font(.callout)
                }
                Button("Propriétés…") { model.showProperties() }
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    /// A Quick Look preview, except for folders (nothing to show) and for
    /// network shares, where reading the file just to preview it could be
    /// slow: both show the icon.
    @ViewBuilder
    private func preview(of item: FileItem) -> some View {
        if item.isBrowsable || !model.isLocalVolume {
            Image(nsImage: FileIcon.image(for: item, isLocalVolume: model.isLocalVolume))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 128, maxHeight: 128)
        } else {
            QuickLookPreview(url: item.url)
        }
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(detail)
        }
    }

    /// The details shown under the preview, from what the list already knows
    /// (no disk access while drawing).
    static func details(of item: FileItem) -> [(label: String, value: String)] {
        var rows: [(String, String)] = [("Type", item.kind)]
        if let size = item.size { rows.append(("Taille", FileFormat.size(size))) }
        if let date = item.modificationDate { rows.append(("Modifié", FileFormat.date(date))) }
        rows.append(("Emplacement", (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
        return rows.filter { !$0.1.isEmpty }
    }
}

/// A Quick Look view for one file.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        // Releases the preview process.
        view.close()
    }
}
