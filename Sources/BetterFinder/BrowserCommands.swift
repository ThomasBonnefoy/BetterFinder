import SwiftUI

/// Menu bar commands that act on the frontmost browser window.
struct BrowserCommands: Commands {
    @FocusedValue(\.browserModel) private var model

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nouveau dossier") { model?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Nouveau document texte") { model?.newTextFile() }
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
            Button("Actualiser") { model?.reload() }
                .keyboardShortcut("r")
                .disabled(model == nil)
            Toggle("Afficher les fichiers masqués", isOn: showHidden)
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model == nil)
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
            Button("Dossier personnel") { model?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Modifier l'adresse") { model?.beginEditingAddress() }
                .keyboardShortcut("l")
                .disabled(model == nil)
        }
    }

    private var showHidden: Binding<Bool> {
        Binding(
            get: { model?.showHidden ?? false },
            set: { model?.setShowHidden($0) }
        )
    }
}
