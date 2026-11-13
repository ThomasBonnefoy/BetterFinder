import BetterFinderCore
import SwiftUI

/// One item of a batch rename.
struct BatchRenameItem: Equatable {
    let url: URL
    let isDirectory: Bool
}

/// What the batch rename sheet is asked to rename.
struct BatchRenameRequest: Identifiable, Equatable {
    let id = UUID()
    /// In the order of the list: a sequence numbers them in that order.
    let items: [BatchRenameItem]
    /// Every name in the folder, to spot clashes with items left alone.
    let namesInFolder: [String]
}

/// "Renommer N éléments": choose how the names are made, check the result
/// in the preview, then apply.
struct BatchRenameSheet: View {
    let request: BatchRenameRequest
    let apply: ([FileMove]) -> Void
    let cancel: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case sequence = "Numéroter"
        case replace = "Chercher et remplacer"
        case affix = "Préfixe et suffixe"
        var id: String { rawValue }
    }

    @State private var mode = Mode.sequence
    @State private var sequenceName: String
    @State private var start = 1
    @State private var digits = 1
    @State private var find = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var prefix = ""
    @State private var suffix = ""

    init(request: BatchRenameRequest, apply: @escaping ([FileMove]) -> Void, cancel: @escaping () -> Void) {
        self.request = request
        self.apply = apply
        self.cancel = cancel
        let first = request.items.first.map {
            FileNaming.split($0.url.lastPathComponent, isDirectory: $0.isDirectory).base
        } ?? "Fichier"
        _sequenceName = State(initialValue: first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Renommer \(request.items.count) éléments").font(.headline)
            Picker("Méthode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            options
            Text("Les extensions sont conservées.").font(.callout).foregroundStyle(.secondary)
            Divider()
            preview
            HStack {
                Text(summary).font(.callout).foregroundStyle(plan.isValid ? Color.secondary : Color.red)
                Spacer()
                Button("Annuler", action: cancel).keyboardShortcut(.cancelAction)
                Button("Renommer") { apply(plan.moves) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!plan.isValid || !plan.changesSomething)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }

    // MARK: - Options

    @ViewBuilder
    private var options: some View {
        switch mode {
        case .sequence:
            Form {
                TextField("Nom", text: $sequenceName)
                Stepper("Premier numéro : \(start)", value: $start, in: 0...99999)
                Stepper("Chiffres : \(digits)", value: $digits, in: 1...6)
            }
            .formStyle(.columns)
        case .replace:
            Form {
                TextField("Chercher", text: $find)
                TextField("Remplacer par", text: $replacement)
                Toggle("Respecter la casse", isOn: $caseSensitive)
            }
            .formStyle(.columns)
        case .affix:
            Form {
                TextField("Avant le nom", text: $prefix)
                TextField("Après le nom", text: $suffix)
            }
            .formStyle(.columns)
        }
    }

    // MARK: - Preview

    private var rule: BatchRename.Rule {
        switch mode {
        case .sequence: .sequence(name: sequenceName, start: start, digits: digits)
        case .replace: .replace(find: find, with: replacement, caseSensitive: caseSensitive)
        case .affix: .affix(prefix: prefix, suffix: suffix)
        }
    }

    private var plan: BatchRename.Plan {
        BatchRename.plan(
            for: request.items.map { ($0.url, $0.isDirectory) },
            rule: rule,
            namesInFolder: request.namesInFolder
        )
    }

    private var preview: some View {
        List(Array(plan.entries.enumerated()), id: \.offset) { _, entry in
            HStack(spacing: 8) {
                Text(entry.oldName).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(entry.newName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(entry.problem != nil ? Color.red : Color.primary)
                    .fontWeight(entry.isChanged ? .medium : .regular)
                if let problem = entry.problem {
                    Spacer(minLength: 0)
                    Text(Self.text(for: problem)).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.bordered)
    }

    private var summary: String {
        let problems = plan.entries.filter { $0.problem != nil }.count
        if problems > 0 {
            return problems > 1 ? "\(problems) noms impossibles" : "1 nom impossible"
        }
        let changed = plan.entries.filter(\.isChanged).count
        return changed == 0 ? "Aucun nom ne change" : (changed > 1 ? "\(changed) éléments seront renommés" : "1 élément sera renommé")
    }

    static func text(for problem: BatchRename.Problem) -> String {
        switch problem {
        case .invalidName(.empty): "vide"
        case .invalidName(.forbiddenCharacter): "« / » ou « : »"
        case .invalidName(.reserved): "réservé"
        case .duplicate: "en double"
        case .taken: "déjà pris"
        }
    }
}
