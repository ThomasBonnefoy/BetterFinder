import SwiftUI

/// The search field of the toolbar.
///
/// It is drawn here rather than by `searchable`: the search item macOS adds
/// to the toolbar makes the app quit when the toolbar is being customized.
struct SearchField: View {
    @Bindable var model: BrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .disabled(!model.canSearch)
                // Escape: end the search and give the keyboard back to the list.
                .onExitCommand {
                    model.searchText = ""
                    model.endSearchEditing()
                }
                .onSubmit { model.endSearchEditing() }
            if !model.searchText.isEmpty {
                Button("Effacer la recherche", systemImage: "xmark.circle.fill") {
                    model.searchText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Effacer la recherche")
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 140, idealWidth: 220, maxWidth: 300, minHeight: 28)
        .onChange(of: model.searchFocusRequests) { isFocused = true }
        .help("Rechercher par nom dans ce dossier et ses sous-dossiers (Cmd+F)")
    }
}
