import AppKit

/// The right-click menu of a file list (details or icons): one for an item,
/// another for the empty space.
@MainActor
final class FileContextMenu: NSObject, NSMenuDelegate {
    enum Target {
        /// A click on an item: how many are selected, the clicked one included.
        case items(count: Int)
        case background
    }

    private let model: BrowserModel
    /// Called when the menu is about to open, once the list has selected the
    /// clicked item.
    private let target: () -> Target
    private let rename: () -> Void
    private let quickLook: () -> Void

    init(
        model: BrowserModel,
        target: @escaping () -> Target,
        rename: @escaping () -> Void,
        quickLook: @escaping () -> Void
    ) {
        self.model = model
        self.target = target
        self.rename = rename
        self.quickLook = quickLook
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch target() {
        case .items(let count):
            buildItemMenu(menu, selectionCount: count)
        case .background:
            buildFolderMenu(menu)
        }
    }

    private func buildItemMenu(_ menu: NSMenu, selectionCount: Int) {
        menu.addItem(item("Ouvrir", #selector(menuOpen)))
        menu.addItem(item("Coup d'œil", #selector(menuQuickLook)))
        if model.canOpenSelectionInNewTabs {
            menu.addItem(item("Ouvrir dans un nouvel onglet", #selector(menuOpenInNewTab)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Couper", #selector(menuCut)))
        menu.addItem(item("Copier", #selector(menuCopy)))
        menu.addItem(.separator())
        menu.addItem(item("Renommer", #selector(menuRename), enabled: selectionCount == 1))
        if model.isInTrash {
            menu.addItem(item("Supprimer définitivement…", #selector(menuDeleteForGood)))
        } else {
            menu.addItem(item("Mettre à la corbeille", #selector(menuTrash)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Copier le chemin d'accès", #selector(menuCopyPath)))
        if model.canAddSelectionToFavorites {
            menu.addItem(item("Ajouter aux favoris", #selector(menuAddFavorite)))
        }
        if model.isSearching {
            menu.addItem(item("Ouvrir l'emplacement du dossier", #selector(menuShowInFolder), enabled: selectionCount == 1))
        }
        menu.addItem(item("Afficher dans le Finder", #selector(menuReveal)))
    }

    private func buildFolderMenu(_ menu: NSMenu) {
        if model.isInTrash {
            // Nothing is created or pasted in the Trash.
            if model.isOnTrash {
                menu.addItem(item("Vider la corbeille…", #selector(menuEmptyTrash)))
                menu.addItem(.separator())
            }
            menu.addItem(item("Actualiser", #selector(menuReload)))
            menu.addItem(item("Afficher dans le Finder", #selector(menuReveal)))
            return
        }
        let new = NSMenuItem(title: "Nouveau", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(item("Dossier", #selector(menuNewFolder)))
        submenu.addItem(item("Document texte", #selector(menuNewTextFile)))
        new.submenu = submenu
        menu.addItem(new)
        menu.addItem(.separator())
        menu.addItem(item("Coller", #selector(menuPaste), enabled: model.canPaste))
        menu.addItem(.separator())
        menu.addItem(item("Actualiser", #selector(menuReload)))
        menu.addItem(item("Afficher dans le Finder", #selector(menuReveal)))
    }

    private func item(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func menuOpen() { model.openSelection() }
    @objc private func menuQuickLook() { quickLook() }
    @objc private func menuOpenInNewTab() { model.openSelectionInNewTabs() }
    @objc private func menuCut() { model.cutSelection() }
    @objc private func menuCopy() { model.copySelection() }
    @objc private func menuPaste() { model.paste() }
    @objc private func menuTrash() { model.trashSelection() }
    @objc private func menuDeleteForGood() { model.askToDeleteSelection() }
    @objc private func menuEmptyTrash() { model.askToEmptyTrash() }
    @objc private func menuCopyPath() { model.copyPathOfSelection() }
    @objc private func menuShowInFolder() { model.showSelectionInItsFolder() }
    @objc private func menuAddFavorite() { model.addSelectionToFavorites() }
    @objc private func menuReveal() { model.revealSelectionInFinder() }
    @objc private func menuNewFolder() { model.newFolder() }
    @objc private func menuNewTextFile() { model.newTextFile() }
    @objc private func menuReload() { model.reload() }
    @objc private func menuRename() { rename() }
}
