import BetterFinderCore
import SwiftUI

/// Menu bar commands that act on the frontmost browser window.
struct BrowserCommands: Commands {
    @FocusedValue(\.browserModel) private var model
    @AppStorage(SidebarSettings.followsLocationKey) private var sidebarFollowsLocation = false

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nouvel onglet") { model?.newTab() }
                .keyboardShortcut("t")
                .disabled(model == nil)
            Divider()
            Button("Nouveau dossier") { model?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Nouveau document texte") { model?.newTextFile() }
                .disabled(model == nil)
            Divider()
            Button("Ouvrir dans le terminal") { model?.openInTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(model?.terminalFolder == nil)
            Divider()
            Button("Vider la corbeille…") { model?.askToEmptyTrash() }
                .disabled(model == nil)
            Divider()
            Button("Ajouter un lecteur réseau…") { model?.driveEditor = DriveEditorRequest() }
                .keyboardShortcut("k")
                .disabled(model == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Renommer") { model?.renameSelection() }
                .disabled(model == nil)
            Button("Copier le chemin d'accès") { model?.copyPathOfSelection() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model == nil)
        }

        CommandGroup(before: .sidebar) {
            Picker("Présentation", selection: viewMode) {
                Text("Détails").tag(ViewMode.details)
                    .keyboardShortcut("1")
                Text("Icônes").tag(ViewMode.icons)
                    .keyboardShortcut("2")
            }
            .pickerStyle(.inline)
            .disabled(model == nil)
            Menu("Trier par") {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Button(Self.title(of: key)) { model?.setSort(FileSort(key: key, ascending: model?.sort.ascending ?? true)) }
                }
                Divider()
                Button("Croissant") { model.map { $0.setSort(FileSort(key: $0.sort.key, ascending: true)) } }
                Button("Décroissant") { model.map { $0.setSort(FileSort(key: $0.sort.key, ascending: false)) } }
            }
            .disabled(model == nil)
            Divider()
            Button("Actualiser") { model?.reload() }
                .keyboardShortcut("r")
                .disabled(model == nil)
            Toggle("Afficher les fichiers masqués", isOn: showHidden)
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model == nil)
            Toggle("Développer jusqu'au dossier ouvert", isOn: $sidebarFollowsLocation)
            Divider()
        }

        CommandMenu("Aller") {
            Button("Précédent") { model?.goBack() }
                .keyboardShortcut("[")
                .disabled(model == nil)
            Button("Suivant") { model?.goForward() }
                .keyboardShortcut("]")
                .disabled(model == nil)
            Button("Dossier parent") { model?.goUp() }
                .keyboardShortcut(.upArrow)
                .disabled(model == nil)
            Divider()
            Button(BrowserModel.computerName) { model?.showComputer() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button(DisplayName.trash) { model?.showTrash() }
                .disabled(model == nil)
            Button("Dossier personnel") { model?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Rechercher") { model?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(model?.canSearch != true)
            Button("Modifier l'adresse") { model?.beginEditingAddress() }
                .keyboardShortcut("l")
                .disabled(model == nil)
        }
    }

    private var viewMode: Binding<ViewMode> {
        Binding(
            get: { model?.viewMode ?? .details },
            set: { model?.viewMode = $0 }
        )
    }

    private static func title(of key: SortKey) -> String {
        switch key {
        case .name: "Nom"
        case .dateModified: "Date de modification"
        case .kind: "Type"
        case .size: "Taille"
        }
    }

    private var showHidden: Binding<Bool> {
        Binding(
            get: { model?.showHidden ?? false },
            set: { model?.setShowHidden($0) }
        )
    }
}
