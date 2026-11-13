import BetterFinderCore
import SwiftUI

/// The toolbar of a browser window: the items of the user's layout, in
/// their order.
///
/// The layout is BetterFinder's own (`ToolbarLayoutStore`), edited in
/// `ToolbarCustomizer`. It does not use the toolbar customization of macOS
/// (`toolbar(id:)`): on macOS 26 it shuffles the saved layout at launch, at
/// random, and can quit the app while doing so
/// (`AppKitToolbarStrategy.applyItemCustomizations`). Replacing the window's
/// toolbar with an AppKit one is not an option either: SwiftUI quits when
/// the toolbar is not its own. Do not go back to either.
struct BrowserToolbar: ToolbarContent {
    @Bindable var model: BrowserModel
    var store = ToolbarLayoutStore.shared

    var body: some ToolbarContent {
        ForEach(store.layout.items, id: \.self) { item in
            ToolbarItem {
                ToolbarItemView(item: item, model: model)
                    .contextMenu {
                        Button("Retirer de la barre d'outils") { store.remove(item) }
                        Divider()
                        Button("Personnaliser la barre d'outils…") { model.isCustomizingToolbar = true }
                    }
            }
        }
    }
}

/// Name and symbol of a toolbar item, for the toolbar and its customizer.
enum ToolbarItemInfo {
    static func title(of item: String) -> String {
        switch item {
        case "back": "Précédent"
        case "forward": "Suivant"
        case "up": "Dossier parent"
        case "address": "Barre d'adresse"
        case "viewMode": "Présentation"
        case "reload": "Actualiser"
        case "newTab": "Nouvel onglet"
        case "newFile": "Nouveau fichier"
        case "search": "Recherche"
        case "hiddenFiles": "Fichiers masqués"
        case "computer": BrowserModel.computerName
        case "home": "Dossier personnel"
        case "addFavorite": "Ajouter aux favoris"
        case "reveal": "Afficher dans le Finder"
        case "terminal": "Ouvrir dans le terminal"
        case "newFolder": "Nouveau dossier"
        case "cut": "Couper"
        case "copy": "Copier"
        case "paste": "Coller"
        case "rename": "Renommer"
        case "trash": "Mettre à la corbeille"
        case "copyPath": "Copier le chemin"
        case "compress": "Compresser"
        case "properties": "Propriétés"
        case "previewPane": "Panneau d'aperçu"
        default: item
        }
    }

    static func symbol(of item: String) -> String {
        switch item {
        case "back": "chevron.left"
        case "forward": "chevron.right"
        case "up": "arrow.up"
        case "address": "character.cursor.ibeam"
        case "viewMode": "square.grid.2x2"
        case "reload": "arrow.clockwise"
        case "newTab": "plus"
        case "newFile": "doc.badge.plus"
        case "search": "magnifyingglass"
        case "hiddenFiles": "eye"
        case "computer": "desktopcomputer"
        case "home": "house"
        case "addFavorite": "star"
        case "reveal": "macwindow"
        case "terminal": "terminal"
        case "newFolder": "folder.badge.plus"
        case "cut": "scissors"
        case "copy": "doc.on.doc"
        case "paste": "doc.on.clipboard"
        case "rename": "pencil"
        case "trash": "trash"
        case "copyPath": "link"
        case "compress": "doc.zipper"
        case "properties": "info.circle"
        case "previewPane": "sidebar.right"
        default: "questionmark"
        }
    }
}

/// One item of the toolbar.
struct ToolbarItemView: View {
    let item: String
    @Bindable var model: BrowserModel

    var body: some View {
        switch item {
        case "address":
            AddressBar(model: model)
        case "search":
            SearchField(model: model)
        case "viewMode":
            Picker("Présentation", selection: $model.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Mode d'affichage (Cmd+1, Cmd+2)")
        case "hiddenFiles":
            Toggle("Fichiers masqués", systemImage: "eye", isOn: Binding(
                get: { model.showHidden },
                set: { model.setShowHidden($0) }
            ))
            .help("Afficher les fichiers masqués")
        case "previewPane":
            Toggle("Panneau d'aperçu", systemImage: "sidebar.right", isOn: $model.showsPreviewPane)
                .help("Afficher le panneau d'aperçu (Option+P)")
        default:
            Button(ToolbarItemInfo.title(of: item), systemImage: ToolbarItemInfo.symbol(of: item)) { run() }
                .disabled(!isEnabled)
                .help(help)
        }
    }

    private var canCreate: Bool {
        model.canDropIntoCurrentFolder && !model.isInTrash
    }

    private var isEnabled: Bool {
        switch item {
        case "back": model.canGoBack
        case "forward": model.canGoForward
        case "up": model.canGoUp
        case "newFile", "newFolder": canCreate
        case "addFavorite": canAddFavorite
        case "reveal": model.currentURL != nil
        case "terminal": model.terminalFolder != nil
        case "cut", "copy", "trash", "copyPath": !model.selection.isEmpty
        case "paste": model.canPaste
        case "rename": !model.selection.isEmpty
        case "compress": model.canCompressSelection
        case "properties": model.displayedDriveID == nil && !model.isOnComputer
        default: true
        }
    }

    private var canAddFavorite: Bool {
        guard let folder = model.currentURL, model.displayedDriveID == nil, !model.isInTrash else { return false }
        return !FavoriteStore.shared.contains(folder)
    }

    private var help: String {
        switch item {
        case "back": "Dossier précédent"
        case "forward": "Dossier suivant"
        case "newFile": "Nouveau document texte"
        case "addFavorite": "Ajouter le dossier ouvert aux favoris"
        case "trash": model.isInTrash ? "Supprimer définitivement" : "Mettre à la corbeille"
        case "copyPath": "Copier le chemin d'accès"
        default: ToolbarItemInfo.title(of: item)
        }
    }

    private func run() {
        switch item {
        case "back": model.goBack()
        case "forward": model.goForward()
        case "up": model.goUp()
        case "reload": model.reload()
        case "newTab": model.newTab()
        case "newFile": model.newTextFile()
        case "computer": model.showComputer()
        case "home": model.goHome()
        case "addFavorite": if let folder = model.currentURL { FavoriteStore.shared.add([folder]) }
        case "reveal": model.revealSelectionInFinder()
        case "terminal": model.openInTerminal()
        case "newFolder": model.newFolder()
        case "cut": model.cutSelection()
        case "copy": model.copySelection()
        case "paste": model.paste()
        case "rename": model.renameSelection()
        case "trash": model.trashSelection()
        case "copyPath": model.copyPathOfSelection()
        case "compress": model.compressSelection()
        case "properties": model.showProperties()
        default: break
        }
    }
}
