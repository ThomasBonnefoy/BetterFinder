# BetterFinder

Un explorateur de fichiers pour macOS qui reprend les habitudes de l'Explorateur Windows, avec l'apparence de macOS.

L'idée de départ : garder les **lecteurs réseau toujours visibles dans la barre latérale**, même quand le VPN est coupé, ce que le Finder ne fait pas.

## Fonctions

- **Lecteurs réseau toujours visibles** : chaque lecteur garde sa place dans la barre latérale et montre son état (connecté, disponible, hors ligne). Il se reconnecte tout seul quand le serveur répond de nouveau, si l'option est cochée.
- **Arborescence dans la barre latérale** : chaque favori, lecteur ou volume se déplie pour montrer ses sous-dossiers ; l'option « Développer jusqu'au dossier ouvert » (menu Présentation) la fait suivre le dossier affiché
- **Favoris personnalisables** : ajoutez les dossiers de votre choix (bouton « + », clic droit, ou glisser-déposer), retirez-en et remettez-les dans l'ordre voulu
- **Vue « Ce Mac »** (l'équivalent de « Ce PC ») : favoris, disques avec leur espace libre, lecteurs réseau avec leur état
- **Onglets**, avec la barre d'onglets de macOS : `Cmd+T`, « Ouvrir dans un nouvel onglet » au clic droit
- Liste détaillée triable (nom, date de modification, type, taille), dossiers en premier, ou grille d'icônes (`Cmd+1`, `Cmd+2`)
- Couper, copier, coller, renommer, corbeille, nouveau dossier et nouveau document, avec annulation ; rien n'est jamais écrasé
- Glisser-déposer entre dossiers, fenêtres, onglets, barre latérale et Finder : déplacement dans le même disque, copie vers un autre (`Option` force la copie, `Cmd` le déplacement)
- Recherche par nom dans le dossier et ses sous-dossiers (`Cmd+F`), sans tenir compte des accents ni des majuscules
- Coup d'œil : `Espace` affiche un aperçu du fichier sélectionné
- **Infos Git** : dans un dépôt, la barre d'état montre la branche, les commits à envoyer ou à recevoir, le nombre de fichiers changés et le dernier commit ; un clic sur la branche permet d'en changer ; une lettre de couleur marque les fichiers modifiés, ajoutés ou non suivis
- **Corbeille** dans la barre latérale et dans « Ce Mac » : on y glisse des fichiers, on la vide avec confirmation. Pour en voir le contenu, macOS demande d'ajouter BetterFinder dans Réglages Système > Confidentialité et sécurité > Accès complet au disque
- Menu contextuel au clic droit
- Barre d'adresse : fil d'Ariane cliquable, ou chemin à saisir (`Cmd+L`)
- Précédent, suivant, dossier parent
- Raccourcis de l'Explorateur Windows adaptés au Mac
- **Barre d'outils personnalisable** : clic droit sur la barre pour choisir ses boutons et leur ordre
- Réglages (`Cmd+,`) : page d'ouverture, présentation, fichiers masqués, infos Git

La suite est décrite dans le [journal des modifications](CHANGELOG.md).

## Lecteurs réseau

Ajoutez un lecteur avec le bouton « + » de la section « Lecteurs réseau » ou avec `Cmd+K`, en donnant son adresse : `smb://serveur/partage`, `\\serveur\partage` ou simplement `serveur/partage`.

| Icône | État | Au clic |
|---|---|---|
| Disque relié, texte normal | Connecté | Ouvre le lecteur |
| Disque relié, texte grisé | Disponible : le serveur répond, le lecteur n'est pas monté | Connecte puis ouvre |
| Disque barré d'une croix | Hors ligne : le serveur est injoignable (VPN coupé) | Affiche la page du lecteur, avec « Réessayer » |

Le mot de passe est demandé par macOS à la première connexion et rangé dans le Trousseau. BetterFinder n'enregistre que le nom, l'adresse et le nom d'utilisateur, dans `~/Library/Application Support/BetterFinder/drives.json`.

## Raccourcis

| Action | Raccourci |
|---|---|
| Ouvrir | `Entrée` ou double-clic |
| Nouvel onglet | `Cmd+T` |
| Ouvrir dans un nouvel onglet | `Cmd+Entrée` ou `Cmd+double-clic` |
| Fermer l'onglet | `Cmd+W` |
| Onglet suivant, précédent | `Ctrl+Tab`, `Ctrl+Maj+Tab` |
| Ce Mac | `Cmd+Maj+M` |
| Dossier précédent | `Retour arrière`, `Option+←` ou `Cmd+[` |
| Dossier suivant | `Option+→` ou `Cmd+]` |
| Dossier parent | `Option+↑` ou `Cmd+↑` |
| Couper, copier, coller | `Cmd+X`, `Cmd+C`, `Cmd+V` |
| Renommer | `F2` |
| Mettre à la corbeille | `Suppr` ou `Cmd+Retour arrière` |
| Supprimer définitivement | `Maj+Suppr` ou `Cmd+Option+Retour arrière` |
| Nouveau dossier | `Cmd+Maj+N` |
| Annuler, rétablir | `Cmd+Z`, `Cmd+Maj+Z` |
| Copier le chemin d'accès | `Cmd+Maj+C` |
| Modifier l'adresse | `Cmd+L` |
| Rechercher | `Cmd+F` |
| Présentation détails, icônes | `Cmd+1`, `Cmd+2` |
| Coup d'œil | `Espace` ou `Cmd+Y` |
| Ajouter un lecteur réseau | `Cmd+K` |
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

L'app s'ouvre sur « Ce Mac ». Pour l'ouvrir directement dans un dossier :

```bash
open dist/BetterFinder.app --args -StartLocation ~/Documents
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

- `Sources/BetterFinderCore` : la logique (lecture des dossiers, tri, historique de navigation, analyse des chemins, arborescence de la barre latérale, lecteurs réseau, opérations sur les fichiers), couverte par des tests.
- `Sources/BetterFinder` : l'interface (SwiftUI pour la fenêtre, AppKit pour la liste de fichiers).
- `scripts/` : construction du `.app`, installation, archive de release.
