# BetterFinder

Un explorateur de fichiers pour macOS qui reprend les habitudes de l'Explorateur Windows, avec l'apparence de macOS.

L'idée de départ : garder les **lecteurs réseau toujours visibles dans la barre latérale**, même quand le VPN est coupé, ce que le Finder ne fait pas.

## Fonctions

- Liste détaillée triable (nom, date de modification, type, taille), dossiers en premier
- Barre d'adresse : fil d'Ariane cliquable, ou chemin à saisir (`Cmd+L`)
- Précédent, suivant, dossier parent
- Raccourcis de l'Explorateur Windows adaptés au Mac

La suite est décrite dans le [journal des modifications](CHANGELOG.md).

## Raccourcis

| Action | Raccourci |
|---|---|
| Ouvrir | `Entrée` ou double-clic |
| Dossier précédent | `Retour arrière`, `Option+←` ou `Cmd+[` |
| Dossier suivant | `Option+→` ou `Cmd+]` |
| Dossier parent | `Option+↑` ou `Cmd+↑` |
| Modifier l'adresse | `Cmd+L` |
| Actualiser | `Cmd+R` ou `F5` |
| Afficher les fichiers masqués | `Cmd+Maj+.` |

## Compiler

Il faut macOS 26 ou plus récent et Xcode 26 ou plus récent (ou ses outils en ligne de commande).

```bash
swift test
```

```bash
scripts/bundle.sh
```

```bash
open dist/BetterFinder.app
```

Pour ouvrir l'app directement dans un dossier :

```bash
open dist/BetterFinder.app --args ~/Documents
```

Pour l'installer dans `/Applications` :

```bash
scripts/install.sh
```

## Installer une version téléchargée

L'app n'est pas signée par un compte développeur Apple. Après avoir décompressé l'archive d'une release, macOS refuse de l'ouvrir tant que la quarantaine n'est pas levée :

```bash
xattr -dr com.apple.quarantine BetterFinder.app
```

## Organisation du code

- `Sources/BetterFinderCore` : la logique (lecture des dossiers, tri, historique de navigation, analyse des chemins), couverte par des tests.
- `Sources/BetterFinder` : l'interface (SwiftUI pour la fenêtre, AppKit pour la liste de fichiers).
- `scripts/` : construction du `.app`, installation, archive de release.
