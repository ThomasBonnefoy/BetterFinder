import BetterFinderCore
import SwiftUI

/// The toolbar of a browser window. It is customizable: a right-click on it,
/// or "Personnaliser la barre d'outils…" in the Présentation menu, lets the
/// user add, remove and reorder its buttons. macOS remembers the result.
///
/// Each button has an identifier that must never change: it is what the
/// saved layout refers to.
struct BrowserToolbar: CustomizableToolbarContent {
    @Bindable var model: BrowserModel

    /// Name the layout is saved under.
    static let id = "BetterFinder.BrowserToolbar"

    var body: some CustomizableToolbarContent {
        navigation
        ToolbarItem(id: "address", placement: .principal) {
            AddressBar(model: model)
        }
        .customizationBehavior(.reorderable)
        display
        ToolbarItem(id: "search") {
            SearchField(model: model)
        }
        places
        fileActions
    }

    // MARK: Shown by default

    @ToolbarContentBuilder
    private var navigation: some CustomizableToolbarContent {
        ToolbarItem(id: "back", placement: .navigation) {
            Button("Précédent", systemImage: "chevron.left") { model.goBack() }
                .disabled(!model.canGoBack)
                .help("Dossier précédent")
        }
        ToolbarItem(id: "forward", placement: .navigation) {
            Button("Suivant", systemImage: "chevron.right") { model.goForward() }
                .disabled(!model.canGoForward)
                .help("Dossier suivant")
        }
        ToolbarItem(id: "up", placement: .navigation) {
            Button("Dossier parent", systemImage: "arrow.up") { model.goUp() }
                .disabled(!model.canGoUp)
                .help("Dossier parent")
        }
    }

    @ToolbarContentBuilder
    private var display: some CustomizableToolbarContent {
        ToolbarItem(id: "viewMode") {
            Picker("Présentation", selection: $model.viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Mode d'affichage (Cmd+1, Cmd+2)")
        }
        ToolbarItem(id: "reload") {
            Button("Actualiser", systemImage: "arrow.clockwise") { model.reload() }
                .help("Actualiser")
        }
        // Always there, unlike the tab bar, which macOS hides while the
        // window has a single tab.
        ToolbarItem(id: "newTab") {
            Button("Nouvel onglet", systemImage: "plus") { model.newTab() }
                .help("Nouvel onglet")
        }
        ToolbarItem(id: "newFile") {
            Button("Nouveau fichier", systemImage: "doc.badge.plus") { model.newTextFile() }
                .disabled(!canCreate)
                .help("Nouveau document texte")
        }
        ToolbarItem(id: "hiddenFiles", showsByDefault: false) {
            Toggle("Fichiers masqués", systemImage: "eye", isOn: Binding(
                get: { model.showHidden },
                set: { model.setShowHidden($0) }
            ))
            .help("Afficher les fichiers masqués")
        }
    }

    // MARK: Offered in the customization panel

    @ToolbarContentBuilder
    private var places: some CustomizableToolbarContent {
        ToolbarItem(id: "computer", showsByDefault: false) {
            Button(BrowserModel.computerName, systemImage: "desktopcomputer") { model.showComputer() }
                .help(BrowserModel.computerName)
        }
        ToolbarItem(id: "home", showsByDefault: false) {
            Button("Dossier personnel", systemImage: "house") { model.goHome() }
                .help("Dossier personnel")
        }
        ToolbarItem(id: "addFavorite", showsByDefault: false) {
            Button("Ajouter aux favoris", systemImage: "star") {
                if let folder = model.currentURL { FavoriteStore.shared.add([folder]) }
            }
            .disabled(!canAddFavorite)
            .help("Ajouter le dossier ouvert aux favoris")
        }
        ToolbarItem(id: "reveal", showsByDefault: false) {
            Button("Afficher dans le Finder", systemImage: "macwindow") { model.revealSelectionInFinder() }
                .disabled(model.currentURL == nil)
                .help("Afficher dans le Finder")
        }
    }

    @ToolbarContentBuilder
    private var fileActions: some CustomizableToolbarContent {
        ToolbarItem(id: "newFolder", showsByDefault: false) {
            Button("Nouveau dossier", systemImage: "folder.badge.plus") { model.newFolder() }
                .disabled(!canCreate)
                .help("Nouveau dossier")
        }
        ToolbarItem(id: "cut", showsByDefault: false) {
            Button("Couper", systemImage: "scissors") { model.cutSelection() }
                .disabled(model.selection.isEmpty)
                .help("Couper")
        }
        ToolbarItem(id: "copy", showsByDefault: false) {
            Button("Copier", systemImage: "doc.on.doc") { model.copySelection() }
                .disabled(model.selection.isEmpty)
                .help("Copier")
        }
        ToolbarItem(id: "paste", showsByDefault: false) {
            Button("Coller", systemImage: "doc.on.clipboard") { model.paste() }
                .disabled(!model.canPaste)
                .help("Coller")
        }
        ToolbarItem(id: "rename", showsByDefault: false) {
            Button("Renommer", systemImage: "pencil") { model.renameSelection() }
                .disabled(model.selection.count != 1)
                .help("Renommer")
        }
        ToolbarItem(id: "trash", showsByDefault: false) {
            Button("Mettre à la corbeille", systemImage: "trash") { model.trashSelection() }
                .disabled(model.selection.isEmpty)
                .help(model.isInTrash ? "Supprimer définitivement" : "Mettre à la corbeille")
        }
        ToolbarItem(id: "copyPath", showsByDefault: false) {
            Button("Copier le chemin", systemImage: "link") { model.copyPathOfSelection() }
                .disabled(model.selection.isEmpty)
                .help("Copier le chemin d'accès")
        }
    }

    private var canCreate: Bool {
        model.canDropIntoCurrentFolder && !model.isInTrash
    }

    private var canAddFavorite: Bool {
        guard let folder = model.currentURL, model.displayedDriveID == nil, !model.isInTrash else { return false }
        return !FavoriteStore.shared.contains(folder)
    }
}
