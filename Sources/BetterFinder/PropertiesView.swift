import BetterFinderCore
import SwiftUI

/// What the Properties sheet is asked to describe.
struct PropertiesRequest: Identifiable, Equatable {
    let id = UUID()
    let urls: [URL]
}

/// The "Propriétés" sheet: details of one item, or the total of several.
/// The size of a folder is computed while the sheet is open.
struct PropertiesView: View {
    let request: PropertiesRequest
    let close: () -> Void

    @State private var infos: [ItemInfo] = []
    @State private var measure: FolderMeasure?
    @State private var isMeasuring = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(rows, id: \.label) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GridRow {
                    Text("Taille").foregroundStyle(.secondary)
                    sizeText
                }
                if measure != nil || !isMeasuring, needsMeasuring {
                    GridRow {
                        Text("Contenu").foregroundStyle(.secondary)
                        Text(contentText).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack {
                Spacer()
                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task(id: request.id) { await load() }
    }

    // MARK: - Content

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: request.urls.first?.path ?? "/"))
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2).textSelection(.enabled)
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        infos.count == 1 ? infos[0].name : "\(request.urls.count) éléments"
    }

    private var subtitle: String {
        infos.count == 1 ? infos[0].kind : "Sélection multiple"
    }

    private var needsMeasuring: Bool {
        infos.contains(where: \.needsMeasuring) || infos.count > 1
    }

    private var rows: [(label: String, value: String)] {
        guard infos.count == 1, let info = infos.first else {
            return [("Emplacement", locationText)]
        }
        var rows: [(String, String)] = [
            ("Emplacement", (info.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath),
        ]
        if let created = info.created { rows.append(("Création", FileFormat.date(created))) }
        if let modified = info.modified { rows.append(("Modification", FileFormat.date(modified))) }
        if let opened = info.lastOpened { rows.append(("Dernière ouverture", FileFormat.date(opened))) }
        var attributes: [String] = []
        if info.isReadOnly { attributes.append("Lecture seule") }
        if info.isHidden { attributes.append("Masqué") }
        rows.append(("Attributs", attributes.isEmpty ? "Aucun" : attributes.joined(separator: ", ")))
        return rows
    }

    /// Where the items are: their folder, or "plusieurs emplacements".
    private var locationText: String {
        let folders = Set(request.urls.map { $0.deletingLastPathComponent().path })
        guard folders.count == 1, let folder = folders.first else { return "Plusieurs emplacements" }
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    @ViewBuilder
    private var sizeText: some View {
        if infos.count == 1, let size = infos[0].fileSize {
            Text(Self.sizeDescription(size))
        } else if let measure {
            Text(Self.sizeDescription(measure.bytes, allocated: measure.allocatedBytes) + (measure.unreadable > 0 ? " (au moins)" : ""))
        } else if isMeasuring {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Calcul en cours…").foregroundStyle(.secondary)
            }
        } else {
            Text("Indisponible").foregroundStyle(.secondary)
        }
    }

    private var contentText: String {
        guard let measure else { return "" }
        var text = "\(Self.plural(measure.files, "fichier")), \(Self.plural(measure.folders, "dossier"))"
        if measure.unreadable > 0 {
            text += " · \(Self.plural(measure.unreadable, "élément")) illisible\(measure.unreadable > 1 ? "s" : "")"
        }
        return text
    }

    // MARK: - Loading

    private func load() async {
        let urls = request.urls
        infos = urls.compactMap { ItemInfo.read($0) }
        measure = nil
        isMeasuring = true
        // A single plain file is already known: nothing to walk.
        guard infos.count != 1 || infos[0].needsMeasuring else {
            isMeasuring = false
            return
        }
        measure = await FolderSize.measure(urls)
        isMeasuring = false
    }

    // MARK: - Formatting

    /// "1,2 Mo (1 234 567 octets)", plus the space used on the disk when it differs.
    static func sizeDescription(_ bytes: Int64, allocated: Int64? = nil) -> String {
        var text = FileFormat.size(bytes)
        if bytes >= 1000 {
            text += " (\(bytes.formatted(.number)) octets)"
        }
        if let allocated, allocated != bytes {
            text += " · \(FileFormat.size(allocated)) sur le disque"
        }
        return text
    }

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count.formatted(.number)) \(word)\(count > 1 ? "s" : "")"
    }
}
