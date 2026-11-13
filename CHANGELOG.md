# Journal des modifications

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les numéros de version suivent [SemVer](https://semver.org/lang/fr/). Une fonctionnalité par version.

## [Non publié]

## [0.28.0] - 2026-11-13

Les images montrent leur contenu.

### Modifié
- Les images, les vidéos et les PDF s'affichent sous forme d'une miniature de leur contenu, dans la liste comme dans la vue en icônes, au lieu de l'icône générique de leur type. La miniature arrive une fraction de seconde après la ligne (l'icône du type s'affiche d'abord) et est gardée en mémoire tant que le fichier ne change pas.
- Les dossiers, les applications et les autres documents gardent leur icône. Sur un lecteur réseau, les icônes restent génériques : lire chaque fichier à distance pour dessiner une liste serait trop lent.

## [0.27.0] - 2026-11-13

La barre d'outils se compose par glisser-déposer.

### Modifié
- « Personnaliser la barre d'outils… » montre la barre d'outils en haut, sous forme de pastilles, et les éléments disponibles en dessous (les deux espaces compris, en pointillés), comme la palette de macOS. On glisse une pastille de la barre pour la déplacer (elle se place avant celle sur laquelle on la dépose, ou à la fin), on glisse un élément du bas dans la barre pour l'ajouter, et on dépose une pastille de la barre sur la zone du bas pour la retirer. Un trait de couleur montre où elle ira.
- Sans glisser : un clic sur un élément du bas l'ajoute à la fin, et le clic droit sur une pastille de la barre propose « Reculer », « Avancer » et « Retirer ». L'ancienne liste avec « Monter » et « Descendre » disparaît.

## [0.26.0] - 2026-11-13

Des espaces dans la barre d'outils.

### Ajouté
- Le panneau « Personnaliser la barre d'outils… » a une section « Espaces » : « Espace » (un petit vide qui scinde les boutons en groupes) et « Espace flexible » (prend toute la place libre et pousse ce qui suit vers le bord droit). On en ajoute autant qu'on veut ; chacun se déplace, se retire et se range comme un bouton. Ce sont les espaces de la barre d'outils de macOS 26, que la v0.18.1 avait fait perdre.
- Ta disposition actuelle n'est pas modifiée ; « Rétablir par défaut » retire les espaces.

## [0.25.0] - 2026-11-13

Le panneau d'aperçu et de détails.

### Ajouté
- Un panneau à droite de la liste (menu Présentation > « Panneau d'aperçu », `Option+P`, ou le bouton de la barre d'outils) : aperçu Quick Look de l'élément sélectionné (images, PDF, texte, vidéos…), son type, sa taille, sa date de modification, son emplacement, et un bouton « Propriétés… ». Avec plusieurs éléments, il donne leur nombre et leur taille totale ; sans sélection, il le dit. Il suit la sélection dans les deux présentations.
- Les dossiers et les lecteurs réseau montrent l'icône au lieu de l'aperçu, pour ne jamais lire un fichier distant juste pour l'afficher. Le panneau n'apparaît pas sur « Ce Mac » ni sur la page d'un lecteur.
- Réglage « Ouvrir le panneau d'aperçu dans les nouvelles fenêtres » (`Cmd+,`). L'état est retenu d'un lancement à l'autre.
- Trois boutons de plus à ajouter dans la barre d'outils : « Compresser », « Propriétés » et « Panneau d'aperçu ». Le bouton « Renommer » s'applique aussi à plusieurs éléments.

## [0.24.0] - 2026-11-13

Renommer plusieurs éléments d'un coup.

### Ajouté
- Avec plusieurs éléments sélectionnés, `F2`, « Renommer » du menu Édition ou « Renommer N éléments… » au clic droit ouvrent une fenêtre avec trois méthodes : numéroter (« Vacances (01).jpg », « Vacances (02).jpg »… avec le premier numéro et le nombre de chiffres au choix), chercher et remplacer (avec ou sans respect de la casse), ajouter un préfixe et un suffixe. Les extensions sont toujours conservées.
- Un aperçu montre l'ancien et le nouveau nom de chaque élément pendant la saisie. Les noms impossibles (vide, « / » ou « : », en double, déjà pris par un élément laissé tel quel) sont signalés en rouge et bloquent le bouton « Renommer ».
- Le renommage se fait en deux temps : des éléments peuvent donc échanger ou décaler leurs noms (a → b et b → c). Si un renommage échoue, tout revient à l'état d'avant. `Cmd+Z` rend les noms d'origine.

## [0.23.0] - 2026-11-13

Remettre un élément de la corbeille à sa place.

### Ajouté
- « Remettre » au clic droit sur un élément de la corbeille, et dans le menu Fichier : l'élément retourne dans le dossier d'où il venait. macOS ne fournit aucune fonction publique pour cela ; BetterFinder demande donc au Finder de le faire (commande « Remettre » du Finder). À la première utilisation, macOS demande si BetterFinder peut contrôler le Finder (Réglages Système > Confidentialité et sécurité > Automatisation) ; si on refuse, un message explique où le changer.
- Seuls les éléments posés à la racine de la corbeille se remettent (un fichier à l'intérieur d'un dossier jeté n'a pas de place d'origine propre). La remise ne s'annule pas avec `Cmd+Z`.

## [0.22.0] - 2026-11-13

Compresser en zip.

### Ajouté
- « Compresser » au clic droit et dans le menu Fichier : les éléments sélectionnés sont rangés dans une archive zip à côté d'eux (« photo.png.zip » pour un seul, « Archive.zip » pour plusieurs, comme le Finder), puis l'archive est sélectionnée. Rien n'est jamais écrasé : un nom pris reçoit un numéro. `Cmd+Z` met l'archive à la corbeille.
- L'archive ne contient que les éléments, sans dossier `__MACOSX` : elle s'ouvre proprement sous Windows. Les éléments doivent être dans le même dossier (ce qui n'est pas toujours le cas dans des résultats de recherche : l'entrée est alors grisée). Pas dans la corbeille.

## [0.21.0] - 2026-11-13

Les propriétés d'un élément, avec la vraie taille d'un dossier.

### Ajouté
- « Propriétés » (`Cmd+I` ou `Option+Entrée`, menu Édition ou clic droit, sur un élément, une sélection ou le vide de la liste pour le dossier ouvert) : nom, type, emplacement, dates de création, de modification et de dernière ouverture, attributs (lecture seule, masqué), taille exacte en octets.
- Pour un dossier, un paquet (une app) ou une sélection de plusieurs éléments, la taille totale est calculée pendant que la fenêtre est ouverte, avec le nombre de fichiers et de dossiers et l'espace pris sur le disque. Les fichiers masqués comptent, les liens symboliques ne sont pas suivis, et les éléments que macOS refuse de lire sont signalés (la taille est alors un minimum). Fermer la fenêtre arrête le calcul.

## [0.20.0] - 2026-11-13

Afficher ou masquer les extensions.

### Ajouté
- Menu Présentation > « Afficher les extensions de nom de fichier » : décoché, la liste et la vue en icônes montrent « photo » au lieu de « photo.png ». Les dossiers et les fichiers sans extension ne changent pas. Le choix est retenu d'un lancement à l'autre.
- Réglage du même nom (`Cmd+,`) pour les nouvelles fenêtres.
- Quand les extensions sont masquées, renommer un fichier ne modifie que son nom : l'extension d'origine est remise toute seule.

## [0.19.0] - 2026-11-13

Ouvrir un fichier avec une autre application.

### Ajouté
- « Ouvrir avec » au clic droit sur un ou plusieurs fichiers : le sous-menu liste les applications qui savent les ouvrir (celle par défaut en premier, avec son icône) et « Autre… » ouvre un sélecteur d'application. Rien n'est proposé quand la sélection contient un dossier.

## [0.18.2] - 2026-11-12

### Corrigé
- Après chaque installation, macOS refusait de nouveau l'accès aux dossiers protégés (Téléchargements, Documents, corbeille…) alors que « Accès complet au disque » était coché : la signature de l'app changeait à chaque version. `scripts/bundle.sh` signe maintenant avec le certificat local « BetterFinder Local » s'il existe dans le trousseau (la signature ne change plus), sinon en ad hoc comme avant. Il faut retirer puis remettre BetterFinder dans « Accès complet au disque » une dernière fois ; ensuite l'autorisation tient d'une version à l'autre.

## [0.18.1] - 2026-11-12

### Corrigé
- L'app quittait au lancement ou à l'ouverture d'un dossier, dans la barre d'outils personnalisable de macOS, qui mélangeait aussi l'ordre des boutons d'un lancement à l'autre. BetterFinder gère maintenant lui-même le choix et l'ordre des boutons.

### Modifié
- « Personnaliser la barre d'outils… » (menu Présentation, ou clic droit sur un bouton) ouvre un panneau de BetterFinder : on y ajoute, retire et réordonne les boutons, par glisser ou avec les flèches ; « Rétablir par défaut » revient à l'ensemble d'origine. Un clic droit sur un bouton permet aussi de le retirer. La disposition est commune à toutes les fenêtres.
- Nouveau bouton proposé : « Ouvrir dans le terminal ».
- Les espaces libres et le choix « icônes et texte » de l'ancien panneau de macOS n'existent plus. L'ancienne disposition n'est pas reprise.

## [0.18.0] - 2026-11-12

Ouvrir un dossier dans le terminal.

### Ajouté
- « Ouvrir dans le terminal » au clic droit : sur le vide de la liste (le dossier ouvert), sur un dossier de la liste, sur les favoris, les emplacements, les dossiers de l'arborescence, les lecteurs réseau connectés et les tuiles de « Ce Mac ». Aussi dans le menu Fichier, avec `Cmd+Option+T` (dossier sélectionné, sinon dossier ouvert).
- Réglage « Terminal » (`Cmd+,`) : Automatique prend le premier installé parmi Ghostty, iTerm, Warp et Terminal ; on peut en imposer un.
- Rien n'est proposé dans la corbeille, sur « Ce Mac » ou sur un lecteur hors ligne.

## [0.17.0] - 2026-11-12

### Ajouté
- Un bouton « Nouveau fichier » dans la barre d'outils, à côté du « + » des onglets : il crée un document texte dans le dossier ouvert et passe tout de suite en renommage. Il est grisé là où l'on ne peut rien créer (corbeille, « Ce Mac », lecteur hors ligne).

## [0.16.0] - 2026-11-11

La barre d'outils personnalisable.

### Ajouté
- La barre d'outils se personnalise : clic droit dessus, ou menu Présentation > « Personnaliser la barre d'outils… ». On y glisse les boutons voulus, on en retire, on les remet dans l'ordre, on ajoute des espaces, et on choisit entre icônes seules ou icônes et texte. macOS retient le résultat.
- Nouveaux boutons proposés : Fichiers masqués, Ce Mac, Dossier personnel, Ajouter aux favoris, Afficher dans le Finder, Nouveau dossier, Couper, Copier, Coller, Renommer, Mettre à la corbeille, Copier le chemin.

### Modifié
- Le champ de recherche est dessiné par BetterFinder : celui de macOS faisait quitter l'app à l'ouverture du panneau de personnalisation. `Cmd+F` et `Échap` marchent comme avant.

## [0.15.1] - 2026-11-11

### Modifié
- La première section de la page « Ce Mac » montre vos favoris, dans leur ordre, au lieu des cinq dossiers fixes. Un clic droit sur une tuile permet de la retirer des favoris. Elle s'appelle « Favoris » et la corbeille passe dans « Appareils et lecteurs ».

## [0.15.0] - 2026-11-11

La corbeille.

### Ajouté
- Une ligne « Corbeille » à la fin des emplacements de la barre latérale, et une tuile « Corbeille » dans la page « Ce Mac ». Elles ouvrent la corbeille ; la ligne de la barre latérale accepte aussi des fichiers glissés dessus, qui sont mis à la corbeille (et peuvent être remis avec `Cmd+Z`). Menu « Aller > Corbeille ».
- « Vider la corbeille… » au clic droit sur la ligne, sur la tuile ou sur le vide de la corbeille, et dans le menu Fichier : une confirmation est demandée, la suppression est définitive.
- Dans la corbeille, `Suppr` et le menu contextuel proposent « Supprimer définitivement… » au lieu de remettre à la corbeille ; on n'y colle ni ne crée rien. Glisser un élément hors de la corbeille le remet dans le dossier voulu.
- Quand macOS refuse l'accès à un dossier, une page l'explique et ouvre les réglages de confidentialité, au lieu d'un message d'erreur technique.

### À savoir
- macOS protège la corbeille : pour y voir les fichiers, BetterFinder doit être ajouté dans Réglages Système > Confidentialité et sécurité > Accès complet au disque, puis relancé. Mettre un fichier à la corbeille n'en a pas besoin. L'app n'a pas de signature de développeur : après une mise à jour, il peut falloir retirer BetterFinder de la liste puis l'y remettre.
- Seule la corbeille du dossier personnel est gérée, pas celles des autres disques.

## [0.14.0] - 2026-11-11

Le dernier commit et le changement de branche.

### Ajouté
- La barre d'état affiche le dernier commit du dépôt : son identifiant court et la première ligne de son message. L'infobulle donne l'auteur et l'ancienneté.
- Le nom de la branche est un menu : il liste les branches locales, coche la branche courante, et un clic en choisit une autre. Le sous-menu « Branches distantes » crée la branche locale qui suit une branche du serveur.
- Si Git refuse le changement (des modifications seraient perdues, par exemple), son message est affiché et rien n'est changé. Si le dossier ouvert n'existe pas dans la nouvelle branche, la fenêtre remonte au dossier le plus proche.

## [0.13.0] - 2026-11-11

Les infos Git.

### Ajouté
- Dans un dossier qui fait partie d'un dépôt Git, la barre d'état affiche la branche, les commits à envoyer (↑) et à recevoir (↓), et le nombre de fichiers indexés, modifiés, non suivis ou en conflit. L'infobulle donne le dépôt et la branche suivie.
- Une lettre de couleur marque les fichiers changés, en liste comme en icônes : `M` modifié, `A` ajouté, `R` renommé, `?` non suivi, `!` en conflit. Un dossier prend la marque de ce qu'il contient.
- L'affichage se met à jour quand un fichier change, après un commit ou un changement de branche fait ailleurs, et au retour dans BetterFinder.
- Git n'est jamais lancé sur un lecteur réseau, et ne modifie rien dans le dépôt.
- Réglage « Afficher la branche et l'état des fichiers dans les dépôts Git » (`Cmd+,`), coché par défaut.

## [0.12.1] - 2026-11-11

### Corrigé
- Glisser un dossier dans les favoris faisait quitter l'app (une erreur interne de SwiftUI au dépôt entre deux lignes de la barre latérale). Le dépôt entre deux favoris n'existe plus : un dossier se dépose sur le titre « Favoris » pour l'ajouter, et un favori se glisse sur la moitié haute ou basse d'un autre pour passer avant ou après lui.

## [0.12.0] - 2026-11-11

Des favoris à votre façon.

### Ajouté
- La liste des favoris est la vôtre : elle est enregistrée dans `~/Library/Application Support/BetterFinder/favorites.json` et commune à toutes les fenêtres. Au premier lancement, elle contient les cinq dossiers habituels (dossier personnel, Bureau, Documents, Téléchargements, Applications).
- Ajouter un dossier : bouton « + » de la section Favoris, « Ajouter aux favoris » au clic droit sur un dossier (liste, arborescence, volume, lecteur réseau), ou glisser un dossier sur le titre « Favoris », depuis la liste, une autre fenêtre ou le Finder.
- Retirer : « Retirer des favoris » au clic droit. Le dossier n'est pas touché.
- Réordonner : glisser un favori sur un autre, ou « Monter » et « Descendre » au clic droit.
- « Rétablir les favoris par défaut… » au clic droit sur un favori.
- La page « Ce Mac » garde ses dossiers principaux habituels.

## [0.11.0] - 2026-11-11

Les réglages.

### Ajouté
- Fenêtre de réglages (`Cmd+,`) :
  - les nouvelles fenêtres et les nouveaux onglets s'ouvrent sur « Ce Mac » ou sur le dossier personnel ;
  - présentation des dossiers (détails ou icônes) ;
  - fichiers masqués affichés ou non dans les nouvelles fenêtres ;
  - option « Développer jusqu'au dossier ouvert » de la barre latérale, déjà présente dans le menu Présentation.

## [0.10.0] - 2026-11-11

La vue icônes.

### Ajouté
- Deuxième présentation des dossiers : une grille de grandes icônes avec leur nom. Le sélecteur de la barre d'outils, le menu Présentation (`Cmd+1` Détails, `Cmd+2` Icônes) ou la barre d'outils la choisissent ; le choix est retenu d'un lancement à l'autre.
- La grille fait tout ce que fait la liste : sélection à la souris et au clavier, double-clic, couper/copier/coller, renommer sur place (`F2`), corbeille, Coup d'œil, glisser-déposer, menu contextuel, recherche.
- Menu Présentation > « Trier par » : nom, date de modification, type ou taille, croissant ou décroissant. Utile surtout dans la grille, qui n'a pas d'en-têtes de colonnes.

## [0.9.0] - 2026-11-11

Le Coup d'œil.

### Ajouté
- `Espace` (ou `Cmd+Y`, ou « Coup d'œil » au clic droit) affiche un aperçu des éléments sélectionnés dans le panneau Coup d'œil de macOS : images, PDF, documents, vidéos, son, texte.
- Le panneau suit la sélection : les flèches du clavier passent d'un élément à l'autre, y compris quand le panneau est au premier plan. `Espace` le referme.

## [0.8.0] - 2026-11-11

La recherche.

### Ajouté
- Champ de recherche dans la barre d'outils (`Cmd+F`) : cherche dans le dossier affiché et dans tous ses sous-dossiers, pendant la frappe. Les résultats arrivent au fur et à mesure et la barre d'état indique « Recherche… » tant qu'elle n'est pas terminée.
- Un nom correspond s'il contient tous les mots saisis, sans tenir compte des majuscules ni des accents. Les fichiers masqués ne sont cherchés que s'ils sont affichés ; l'intérieur des applications n'est pas parcouru.
- La barre d'état donne le nombre de résultats et, pour un résultat sélectionné, le dossier qui le contient. Clic droit : « Ouvrir l'emplacement du dossier ».
- La recherche s'arrête quand le champ est vidé ou quand la fenêtre change de dossier. Elle s'applique aux résultats triés, renommés, copiés ou supprimés comme à n'importe quelle liste.

## [0.7.0] - 2026-11-11

Le glisser-déposer.

### Ajouté
- Les éléments de la liste se glissent vers un dossier de la liste, vers la liste elle-même (depuis une autre fenêtre ou un autre onglet), vers une ligne de la barre latérale (favori, volume, lecteur réseau connecté, dossier de l'arborescence) ou vers une autre application, le Finder compris.
- Comme dans l'Explorateur : l'élément est déplacé dans le même disque et copié vers un autre. `Option` force la copie, `Cmd` force le déplacement.
- Rien n'est écrasé : un nom déjà pris reçoit un numéro. Un dossier ne peut pas être déposé sur lui-même ni dans l'un de ses sous-dossiers.
- Un dépôt s'annule avec `Cmd+Z`.
- Les fichiers glissés depuis le Finder se déposent dans la liste et dans la barre latérale.

## [0.6.0] - 2026-11-10

La vue « Ce Mac », l'équivalent de « Ce PC ».

### Ajouté
- Page « Ce Mac » : les dossiers principaux, les disques et volumes avec une barre d'occupation et l'espace libre (« 232 Go libres sur 494 Go »), et les lecteurs réseau avec leur état (connecté, disponible, hors ligne).
- Un clic sélectionne une tuile, un double-clic l'ouvre. Un lecteur réseau disponible se connecte à l'ouverture, comme depuis la barre latérale.
- « Ce Mac » en tête de la barre latérale, dans le menu Aller (`Cmd+Maj+M`), et en saisissant « Ce Mac » dans la barre d'adresse.
- Le bouton « dossier parent » mène à « Ce Mac » depuis la racine d'un disque ou d'un lecteur, comme dans l'Explorateur.
- Clic droit sur une tuile : ouvrir, ouvrir dans un nouvel onglet, copier le chemin d'accès, afficher dans le Finder ; pour un lecteur réseau : déconnecter, modifier.
- « Actualiser » relit l'espace libre des disques et l'état des lecteurs.
- BetterFinder s'ouvre sur « Ce Mac », et non plus sur le dossier personnel. Les nouvelles fenêtres et les nouveaux onglets (`Cmd+T` ou « + ») aussi.

## [0.5.0] - 2026-11-10

Les onglets.

### Ajouté
- Onglets dans la fenêtre, avec la barre d'onglets de macOS (la même que celle du Finder) : chaque onglet a son dossier, son historique et sa sélection.
- Nouvel onglet avec `Cmd+T` ou le bouton « + » de la barre d'outils, toujours visible (la barre d'onglets n'a pas de « + » à elle). La barre d'onglets n'apparaît que lorsqu'il y a plusieurs onglets. Un nouvel onglet s'ouvre sur le dossier personnel, juste après l'onglet courant.
- « Ouvrir dans un nouvel onglet » au clic droit sur un dossier : dans la liste (un onglet par dossier sélectionné), dans l'arborescence, sur un favori, un volume ou un lecteur réseau connecté.
- `Cmd+Entrée` ou `Cmd+double-clic` ouvre un dossier dans un nouvel onglet.
- `Cmd+W` ferme l'onglet ; `Ctrl+Tab` et `Ctrl+Maj+Tab` passent d'un onglet à l'autre. Un onglet se déplace à la souris, se détache en fenêtre ou rejoint une autre fenêtre (menu Fenêtre).
- L'arborescence de la barre latérale est commune à tous les onglets : un dossier déplié dans l'un l'est dans les autres.

## [0.4.0] - 2026-11-10

L'arborescence dans la barre latérale.

### Ajouté
- Chaque ligne de la barre latérale (favoris, lecteurs réseau connectés, volumes) se déplie avec sa flèche pour montrer ses sous-dossiers, qui se déplient à leur tour. Un clic sur un dossier l'ouvre dans la liste.
- Les sous-dossiers ne sont lus qu'au moment où une ligne est dépliée. La flèche disparaît quand un dossier n'a pas de sous-dossier.
- Le dossier affiché dans la fenêtre est surligné dans l'arborescence quand il y est visible.
- Option « Développer jusqu'au dossier ouvert » du menu Présentation : l'arborescence se déplie toute seule jusqu'au dossier affiché. Désactivée par défaut, comme dans l'Explorateur.
- L'arborescence suit les dossiers créés, renommés ou supprimés dans la liste ; « Actualiser » relit aussi les dossiers dépliés.
- Les dossiers masqués apparaissent dans l'arborescence quand les fichiers masqués sont affichés.
- Clic droit sur un dossier de l'arborescence : ouvrir, copier le chemin d'accès, afficher dans le Finder.
- Un lecteur réseau hors ligne garde sa ligne, sans flèche : rien n'est lu sur un serveur injoignable.

## [0.3.0] - 2026-11-10

Les opérations sur les fichiers.

### Ajouté
- Couper, copier et coller (`Cmd+X`, `Cmd+C`, `Cmd+V`), y compris entre BetterFinder et le Finder. Un élément coupé apparaît estompé jusqu'à ce qu'il soit collé.
- Rien n'est jamais écrasé : une copie faite à côté de l'original s'appelle « nom - Copie », un autre conflit de nom reçoit un numéro (« nom (2) »).
- Renommer sur place avec `F2` : le nom est sélectionné, pas l'extension. `Entrée` valide, `Échap` annule.
- `Suppr` ou `Cmd+Retour arrière` envoie à la corbeille. `Maj+Suppr` ou `Cmd+Option+Retour arrière` supprime définitivement, après confirmation.
- Sur un lecteur sans corbeille (cas fréquent des lecteurs réseau), BetterFinder propose la suppression définitive au lieu d'échouer.
- Nouveau dossier (`Cmd+Maj+N`) et nouveau document texte, créés directement en mode renommage.
- Annuler et rétablir (`Cmd+Z`, `Cmd+Maj+Z`) pour la copie, le déplacement, le renommage, la mise à la corbeille et les créations.
- Menu contextuel au clic droit : ouvrir, couper, copier, renommer, mettre à la corbeille, copier le chemin d'accès, afficher dans le Finder ; sur le fond de la liste : nouveau, coller, actualiser.
- « Copier le chemin d'accès » (`Cmd+Maj+C`).
- La barre d'état indique l'opération en cours.

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
