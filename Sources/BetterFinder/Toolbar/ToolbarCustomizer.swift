import BetterFinderCore
import SwiftUI

/// The sheet where the user composes the toolbar: which items, in which
/// order. Changes apply at once, in every window.
struct ToolbarCustomizer: View {
    @Environment(\.dismiss) private var dismiss
    var store = ToolbarLayoutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personnaliser la barre d'outils")
                .font(.headline)
            Text("Glissez les lignes pour changer l'ordre ; ajoutez des espaces pour scinder la barre en groupes. Les changements s'appliquent tout de suite.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                Section("Dans la barre d'outils") {
                    ForEach(store.layout.items, id: \.self) { item in
                        row(item) {
                            Button("Monter", systemImage: "chevron.up") { store.moveUp(item) }
                                .disabled(!store.layout.canMoveUp(item))
                            Button("Descendre", systemImage: "chevron.down") { store.moveDown(item) }
                                .disabled(!store.layout.canMoveDown(item))
                            Button("Retirer", systemImage: "minus.circle") { store.remove(item) }
                        }
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Espaces") {
                    row(title: "Espace", symbol: "rectangle.split.2x1", hint: "Scinde les boutons en groupes") {
                        Button("Ajouter", systemImage: "plus.circle") { store.addSpace(.fixed) }
                    }
                    row(title: "Espace flexible", symbol: "arrow.left.and.right", hint: "Pousse la suite à droite") {
                        Button("Ajouter", systemImage: "plus.circle") { store.addSpace(.flexible) }
                    }
                }
                Section("Disponibles") {
                    ForEach(store.layout.available, id: \.self) { item in
                        row(item) {
                            Button("Ajouter", systemImage: "plus.circle") { store.add(item) }
                        }
                    }
                    if store.layout.available.isEmpty {
                        Text("Tous les boutons sont dans la barre d'outils.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 380)

            HStack {
                Button("Rétablir par défaut") { store.reset() }
                Spacer()
                Button("Terminé") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func row(_ item: String, @ViewBuilder actions: () -> some View) -> some View {
        row(title: ToolbarItemInfo.title(of: item), symbol: ToolbarItemInfo.symbol(of: item), hint: nil, actions: actions)
    }

    private func row(title: String, symbol: String, hint: String?, @ViewBuilder actions: () -> some View) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            if let hint {
                Text(hint).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }
}
