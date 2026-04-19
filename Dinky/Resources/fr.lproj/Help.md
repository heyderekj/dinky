# Welcome

Dinky rend les fichiers minables. Déposez quelque chose, sortez une version plus petite – même look, moins de poids.

Il fonctionne sur les **images** (JPEG, PNG, WebP, AVIF, TIFF, BMP), les **vidéos** (MP4, MOV, M4V) et les **PDF**.

Tout se passe sur votre Mac. Rien n'est téléchargé.

---

## Quick start

1. Faites glisser un fichier (ou une pile de fichiers) sur la fenêtre de Dinky.
2. Regardez le décompte diminuer.
3. Recherchez les copies plus petites à côté des originaux (par défaut), dans votre dossier Téléchargements ou dans un dossier de votre choix.

C'est ça. Les valeurs par défaut sont bonnes. Continuez à lire si vous souhaitez les plier à votre guise.

---

## Ways to compress

Vous n'êtes pas obligé d'ouvrir l'application au préalable. Choisissez celui qui correspond à votre façon de travailler.

- **Faites glisser et déposez** sur la fenêtre Dinky ou sur l'icône du Dock.
- **Open Files…** — `{{SK_OPEN_FILES}}` pour choisir dans une feuille.
- **Clipboard Compress** — `{{SK_PASTE}}` colle un **fichier** pris en charge copié dans le Finder (images, vidéos, PDF) ou des données **d'image brute** (PNG/TIFF à partir de captures d'écran ou de navigateurs).
- **Cliquez avec le bouton droit dans Finder → Services → Compresser avec Dinky** — fonctionne sur des sélections de n'importe quelle taille.
- **Surveiller un dossier** — Dinky compresse tout ce qui y arrive. (Voir *Surveiller les dossiers* ci-dessous.)
- **Action rapide** : attribuez un raccourci clavier à "Compresser avec Dinky" dans Paramètres système → Clavier → Raccourcis clavier → Services.

---

## Where files go

Définissez ceci une fois dans **Paramètres → Sortie**.

- **Même dossier que l'original** *(par défaut)* — garde les choses bien rangées et locales.
- **Dossier Téléchargements** — idéal si vous traitez beaucoup de courriers électroniques ou de messages.
- **Dossier personnalisé…** — pointez Dinky n'importe où.

### Filenames

- **Ajouter "-dinky"** *(par défaut)* — `photo.jpg` devient `photo-dinky.jpg`. Les originaux sont en sécurité.
- **Remplacer l'original** — écrase le fichier. Combinez avec *Déplacer les originaux vers la corbeille* dans **Général** si vous souhaitez un fichier propre à la fin.
- **Suffixe personnalisé** — pour les bricoleurs de flux de travail. Utilisez ce qui convient à votre système de classement.

> **Conseil de pro :** Les préréglages peuvent remplacer l'emplacement de sauvegarde et le nom de fichier par règle. Utilisez-le pour des choses comme "captures d'écran → `~/Desktop/web/`, remplacez l'original".

---

## Sidebar & formats

La barre latérale à droite de la fenêtre principale est l'endroit où vous dites à Dinky **quoi** faire.

### Simple sidebar (default)

Trois choix en langage simple : **Image**, **Vidéo**, **PDF**. Choisissez-en un par catégorie et déposez-le. Dinky trouve un encodeur, une qualité et une taille raisonnables.

### Full sidebar

Désactivez **Paramètres → Général → Utiliser la barre latérale simple** (ou activez des sections individuelles) pour exposer chaque contrôle :

- **Images** — format, indice de contenu (photo/illustration/capture d'écran), largeur maximale, taille maximale du fichier.
- **Vidéos** : famille de codecs (H.264 / HEVC / AV1), niveau de qualité, bande audio.
- **PDF** : préservez le texte et les liens, ou aplatissez-les en images pour obtenir le fichier le plus petit possible.

---

## Smart quality

Lorsque la **Qualité intelligente** est activée (par défaut pour les nouveaux préréglages), Dinky inspecte chaque fichier et sélectionne ses paramètres :

- Les images reçoivent un encodeur adapté à leur contenu (photo occupée ou graphique – interface utilisateur, illustration, logo, capture d'écran).
- Les vidéos obtiennent un niveau basé sur la résolution et le débit binaire de la source, puis adaptées au type de contenu : les enregistrements d'écran et les animations/graphiques animés montent d'un niveau afin que le texte et les bords restent lisibles. Les images de la caméra sont identifiées à partir de la marque/du modèle EXIF ​​afin qu'elles ne soient pas surprotégées. Les sources HDR (Dolby Vision, HDR10, HLG) sont exportées avec HEVC pour préserver les couleurs et mettre en évidence les détails ; H.264 les aplatirait silencieusement en SDR.
- Les PDF bénéficient d'un niveau en fonction de la complexité du document et du fait qu'ils contiennent d'abord du texte ou des images.

Désactivez-le dans n'importe quel préréglage sous **Compression** lorsque vous souhaitez un niveau de qualité fixe (Équilibré/Élevé pour la vidéo, Faible/Moyen/Élevé pour les PDF) — utile pour les lots nécessitant des résultats prévisibles.

---

## Presets

Les préréglages sont des combinaisons de paramètres enregistrées. Créez-en un pour chaque tâche répétitive.

Exemples qui fonctionnent bien :

- **Images de héros Web** — WebP, largeur maximale 1920, ajouter « -web ».
- **Livrables client** — WebP, largeur maximale 2 560, remplacer l'original, enregistrer dans `~/Deliverables/`.
- **Enregistrements d'écran** — H.264 équilibré, bande audio.
- **PDF numérisés** — aplatis, qualité moyenne, niveaux de gris.

Créez-les dans **Paramètres → Préréglages**. Chacun peut :

- S'applique à tous les supports ou à un seul type (Image/Vidéo/PDF).
- Utilisez son propre emplacement de sauvegarde et sa propre règle de nom de fichier.
- Regarder son propre dossier *(voir ci-dessous)*.
- Supprimez les métadonnées, nettoyez les noms de fichiers, ouvrez le dossier de sortie une fois terminé.

Changez le préréglage actif depuis la barre latérale à tout moment.

---

## Watch folders

Déposez les fichiers dans un dossier et laissez Dinky les gérer en arrière-plan.

- **Veille globale** — *Paramètres → Montre → Global*. Utilise ce sur quoi la barre latérale est actuellement définie. Idéal pour un dossier « entrant » ou une capture d’écran.
- **Surveillance par préréglage** — chaque préréglage peut également surveiller son propre dossier avec ses propres règles. Indépendant de la barre latérale : modifiez la barre latérale autant que vous le souhaitez, le préréglage fait toujours son travail.

> **Conseil de pro :** Combinez le « dossier d'enregistrements d'écran » + un préréglage qui supprime l'audio et le réencode en H.264 équilibré. Appuyez sur `⌘⇧5`, enregistrez l'écran, appuyez sur stop - Dinky a un petit fichier prêt avant d'atteindre le Finder.

---

## Manual mode

Activez **Paramètres → Général → Mode manuel** lorsque vous souhaitez un contrôle total.

Les fichiers déposés ne seront pas compressés automatiquement. Cliquez avec le bouton droit sur n'importe quelle ligne pour choisir un format sur place, utilisez **Fichier → Compresser maintenant** (`{{SK_COMPRESS_NOW}}`) lorsque la file d'attente est prête ou modifiez d'abord les paramètres dans la barre latérale. Utile lorsqu'un lot contient des fichiers très différents.

---

## Keyboard shortcuts

Vous trouverez la même liste dans **Paramètres → Raccourcis** afin que vous n'ayez pas à parcourir cette page.

| Raccourci | Actions |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Ouvrir des fichiers… |
| `{{SK_PASTE}}` | Compresser le presse-papiers |
| `{{SK_COMPRESS_NOW}}` | Compresser maintenant (exécute la file d'attente - particulièrement utile en mode manuel) |
| `{{SK_CLEAR_ALL}}` | Tout effacer |
| `{{SK_TOGGLE_SIDEBAR}}` | Basculer la barre latérale de format |
| `{{SK_DELETE}}` | Supprimer les lignes sélectionnées |
| `{{SK_SETTINGS}}` | Paramètres |
| `{{SK_HELP}}` | Cette fenêtre d'aide |

Ajoutez le vôtre pour *Compresser avec Dinky* dans **Paramètres système → Clavier → Raccourcis clavier → Services**.

---

## Shortcuts app

Dinky enregistre une action **Compresser les images** pour l'application Raccourcis. Utilisez-le pour transférer des fichiers du Finder ou d'autres actions via Dinky avec un format choisi - même moteur que la compression dans l'application (respecte les paramètres de qualité intelligente, de redimensionnement et de métadonnées).

---

## Privacy & safety

- Tout fonctionne **localement**. Pas de téléchargements, pas de télémétrie, pas de compte.
- Les **rapports de crash** ne sont envoyés que si *vous* le souhaitez — via l'invite post-crash, le menu « Signaler un bug… » ou la fiche détaillée de l'erreur. Si vous avez activé le partage de diagnostic macOS dans les paramètres système, Apple fournit également des données d'accident anonymisées à Dinky en votre nom via MetricKit, sans qu'aucune donnée supplémentaire ne quitte votre Mac.
- Les encodeurs (`cwebp`, `avifenc`, `oxipng`, ainsi que les pipelines vidéo PDF et AVFoundation intégrés d'Apple) sont livrés dans l'application et lisent directement vos fichiers.
- Les originaux sont conservés par défaut. *Déplacer les originaux vers la corbeille après la compression* est une option optionnelle, dans **Paramètres → Général**.
- *Ignorer si les économies ci-dessous* (désactivé par défaut) empêche les fichiers déjà légers d'être réencodés pour rien.
- *Supprimer les métadonnées* dans n'importe quel préréglage supprime les EXIF, le GPS, les informations sur l'appareil photo et les profils de couleur. Ça vaut le coup avant de publier des photos sur le Web.

---

## Troubleshooting

**Un fichier est sorti plus gros que l'original.**
Dinky conserve l'original à la place. Vous verrez *"Impossible de réduire la taille de celui-ci. Conserver l'original."* dans la ligne.

**Un fichier a été ignoré.**
Soit il était déjà très petit (sous votre seuil *Ignorer si les économies sont inférieures*), soit l'encodeur n'a pas pu le lire. Cliquez sur la ligne pour plus de détails.

**Une vidéo prend beaucoup de temps.**
Le réencodage vidéo nécessite beaucoup de CPU. Le paramètre *Vitesse du lot* dans **Paramètres → Général** contrôle le nombre de fichiers exécutés en même temps. Réglez-le sur **Rapide** si votre Mac fait autre chose.

**Mon PDF a perdu la sélection de texte/les hyperliens.**
Vous avez utilisé *Aplatir (le plus petit)*. Basculez la sortie PDF du préréglage sur *Préserver le texte et les liens* et réexécutez. Aplatir gagne toujours en taille ; préserver gagne toujours sur l'utilité.

**Cliquez avec le bouton droit sur "Compresser avec Dinky" n'apparaît pas.**
Ouvrez Dinky une fois après l'installation pour que macOS enregistre le service. S'il n'apparaît toujours pas, activez-le dans **Paramètres système → Clavier → Raccourcis clavier → Services → Fichiers et dossiers**.

**Pourquoi Dinky ne produit-il pas de fichiers JPEG ?**
WebP et AVIF sont strictement meilleurs que JPEG : même qualité visuelle, fichier plus petit et pris en charge partout où cela compte. Si votre plate-forme nécessite un « .jpg », essayez d'abord WebP ; c'est maintenant accepté presque universellement. Si vous rencontrez un endroit qui le rejette sincèrement, contactez-nous et faites-le nous savoir.

---

## Get in touch

- Site : [dinkyfiles.com](https://dinkyfiles.com)
- Code et problèmes : [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- E-mail : [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Construit par Derek Castelli. Les suggestions, les bugs et « est-ce que ça pourrait aussi faire… » sont tous les bienvenus.
