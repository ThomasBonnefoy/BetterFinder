# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les numéros de version suivent [SemVer](https://semver.org/lang/fr/). Une fonctionnalité par version.

## [Non publié]

## [0.2.0] - 2026-11-10

Les lecteurs réseau, toujours visibles.

### Ajouté
- Section « Lecteurs réseau » dans la barre latérale. Un lecteur y reste affiché même quand son serveur est injoignable (VPN coupé), avec une icône qui indique son état : connecté, disponible ou hors ligne.
- Ajout d'un lecteur par son adresse : `smb://serveur/partage`, `\\serveur\partage` ou `serveur/partage` (AFP, NFS et WebDAV sont aussi acceptés). `Cmd+K` ou le bouton « + ».
- Un clic sur un lecteur disponible le connecte puis l'ouvre. Le mot de passe est demandé par macOS et conservé dans le Trousseau, jamais par BetterFinder.
- Page « lecteur hors ligne » à la place de la liste, avec un bouton Réessayer. Elle laisse place au contenu dès que le lecteur est de nouveau connecté.
- Option « Reconnecter automatiquement » : le lecteur se remonte tout seul quand son serveur répond de nouveau, par exemple à l'activation du VPN.
- Si le VPN tombe pendant la consultation d'un lecteur, la fenêtre affiche la page du lecteur au lieu de se figer, puis revient au même dossier au retour de la connexion.
- Menu contextuel d'un lecteur : connecter, déconnecter, modifier, retirer.
- Une adresse de partage saisie dans la barre d'adresse ouvre le lecteur correspondant, ou propose de l'ajouter.
- Option de lancement `-StartLocation <dossier ou partage>`.

## [0.1.0] - 2026-11-10

Première version : la navigation de base.

### Ajouté
- Fenêtre avec barre latérale : favoris (dossier personnel, Bureau, Documents, Téléchargements, Applications) et volumes montés.
- Liste détaillée triable par nom, date de modification, type ou taille, dossiers toujours en premier, tri naturel des noms.
- Boutons précédent, suivant et dossier parent ; revenir en arrière sélectionne le dossier que l'on vient de quitter.
- Barre d'adresse : fil d'Ariane cliquable, ou chemin à saisir (`Cmd+L`), y compris `~`, un chemin relatif ou le chemin d'un fichier.
- Raccourcis de l'Explorateur Windows : `Entrée` ouvre, `Retour arrière` revient en arrière, `Option+flèches` pour précédent, suivant et parent, `F5` actualise.
- Barre d'état : nombre d'éléments, sélection et taille totale.
- Fichiers masqués affichables avec `Cmd+Maj+.`.
- La liste se met à jour seule quand le dossier change sur le disque.
