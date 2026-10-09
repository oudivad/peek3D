# Peek3D

Aperçu de modèles 3D dans le Finder : on sélectionne un fichier, on appuie sur
**espace**, la pièce apparaît et tourne. On peut la faire pivoter à la souris,
zoomer, puis refermer. Rien à ouvrir, rien à lancer.

## Téléchargement

### → [**Dernière version publiée**](https://github.com/oudivad/peek3d/releases/latest)

Récupérez `Peek3D-1.0.0.dmg` dans **Releases**, la colonne de droite de cette
page. **Il n'y a rien à compiler.** Ouvrez l'archive, glissez **Peek3D** sur
**Applications**, puis lancez l'application une fois — c'est à ce moment que
macOS découvre l'extension d'aperçu. Vous pouvez la refermer aussitôt, les
aperçus continuent de fonctionner.

> **Ne lancez pas Peek3D depuis l'archive montée.** Glissez-la d'abord dans
> Applications, puis ouvrez-la de là. La lancer depuis l'archive enregistre
> l'extension à un chemin situé sur ce volume ; une fois l'archive éjectée, ce
> chemin n'existe plus et les aperçus échouent sur « extension introuvable ».

Nécessite **macOS 13 (Ventura) ou plus récent**, sur Apple Silicon.

> **Le premier lancement sera refusé.** Peek3D n'est pas notarisé — cela exige
> un certificat Apple payant — donc macOS annonce ne pas pouvoir vérifier le
> développeur. Autorisez-le une fois depuis **Réglages Système >
> Confidentialité et sécurité > Ouvrir quand même**, et la question ne se
> reposera plus. La section [Signature](#la-signature-et-ce-quelle-coûte)
> explique pourquoi, et quelles sont les solutions.

Ou, avec Homebrew :

```sh
brew install --cask --no-quarantine oudivad/tap/peek3d
```

*[English version](README.md)*

Formats pris en charge :

| Format | Extensions | Nature |
|---|---|---|
| STL | `.stl` | maillage, binaire et ASCII |
| Wavefront | `.obj` | maillage |
| Stanford PLY | `.ply` | maillage, ASCII et binaire |
| 3MF | `.3mf` | maillage, scène et transformations |
| STEP | `.step` `.stp` | CAO, surfaces exactes |
| IGES | `.iges` `.igs` | CAO, surfaces exactes |

Les quatre premiers contiennent déjà des triangles. Les deux derniers décrivent
des surfaces mathématiques — plans, cylindres, NURBS — qu'il faut calculer
avant de pouvoir afficher quoi que ce soit : Peek3D embarque pour cela
[OpenCASCADE](https://dev.opencascade.org), le noyau géométrique qui fait
tourner une bonne part des logiciels de CAO libres.

## Prendre la main sur les formats que macOS gère déjà

macOS sait déjà prévisualiser les STL, OBJ et PLY — en moins bien, mais il le
sait. Trois extensions se disputent alors le fichier : celle de Pixar
qu'Apple embarque pour l'USD (`HydraQLPreviewExtension`), qui revendique au
passage ces trois formats ; celle de SceneKit, qui revendique `public.3d-content`
tout entier ; et Peek3D. À égalité de précision dans les types déclarés, c'est
l'extension système qui gagne, et toutes deux sont marquées
`showsInExtensionsManager = false` : elles n'apparaissent même pas dans les
Réglages Système.

Le seul levier est l'« élection » de PlugInKit, une préférence par utilisateur
qui ne demande aucun privilège d'administrateur. Peek3D le propose au premier
lancement, et le réglage reste accessible dans le menu **Peek3D › Utiliser
Peek3D pour les STL, OBJ et PLY**.

Un second réglage, indépendant, commande le bouton **Ouvrir avec…** du panneau
d'aperçu et ce que fait un double-clic dans le Finder. Celui-là désigne
l'application par défaut du type de fichier, que macOS attribue à Aperçu pour
les STL, OBJ et PLY. **Peek3D › Ouvrir les STL, OBJ et PLY avec Peek3D** la
revendique, et le décocher la rend à Aperçu.

En ligne de commande, l'élection de l'aperçu revient à :

```sh
pluginkit -e ignore -i com.apple.HydraQLPreviewExtension   # Peek3D passe devant
pluginkit -e use    -i com.apple.HydraQLPreviewExtension   # retour à macOS
qlmanage -r cache                                          # purge les aperçus
```

L'échange est à connaître : l'extension d'Apple gère aussi l'USD, l'USDZ,
l'Alembic et le MaterialX, que Peek3D ne lit pas. Une fois écartée, ces
fichiers retombent sur l'extension SceneKit, plus sommaire mais fonctionnelle.
Les formats que personne d'autre ne revendique — STEP, IGES, 3MF — reviennent à
Peek3D sans rien avoir à régler.

## Compiler depuis les sources

Utile seulement si vous voulez modifier Peek3D. Pour l'utiliser, prenez
l'archive ci-dessus.


Il n'y a pas besoin d'Xcode : les Command Line Tools suffisent.

```sh
xcode-select --install          # si ce n'est pas déjà fait
brew install opencascade
make app
```

| Commande | Effet |
|---|---|
| `make app` | construit `build/Peek3D.app` |
| `make test` | passe les lecteurs sur `Tests/fixtures` |
| `make icon` | régénère `Resources/AppIcon.icns` |
| `make reset-quicklook` | vide le cache d'aperçus pendant le développement |

Variables utiles : `VERSION`, `BUNDLE_ID`, `MACOS_MIN`, `CODESIGN_ID`,
`OCCT_PREFIX`.

### Installer sa propre version

```sh
make install
```

Puis lancez l'application **une fois** : macOS ne découvre une extension Quick
Look qu'à ce moment-là. Vous pouvez ensuite refermer la fenêtre, elle ne sert
plus à rien — sauf à examiner un modèle plus longuement qu'un aperçu.

Depuis macOS 14, les applications installées sont protégées contre les
modifications faites depuis un terminal. Si `make install` n'arrive pas à
remplacer une copie précédente, glissez Peek3D de /Applications vers la
corbeille depuis le Finder, ou autorisez votre terminal dans Réglages Système >
Confidentialité et sécurité > Gestion des apps.

Désinstallation : `make uninstall`.

### Pour une version publiée

Deux points demandent de l'attention avant de distribuer une archive.

**La version minimale de macOS.** Le paquet OpenCASCADE de Homebrew est compilé
pour la version de macOS de la machine qui l'installe. Une application qui
l'embarque hérite de cette contrainte et refuse de démarrer sur un Mac plus
ancien — ce que l'on ne voit jamais chez soi, seulement chez l'utilisateur.
D'où :

```sh
scripts/build-occt.sh 13.0              # compte 20 à 40 minutes
make app OCCT_PREFIX=$PWD/vendor/occt MACOS_MIN=13.0
```

#### La signature, et ce qu'elle coûte

Par défaut la signature est *ad hoc*, et ne coûte rien. Gatekeeper rejette
alors l'application comme l'archive :

```
$ spctl -a -t exec -vv /Applications/Peek3D.app
/Applications/Peek3D.app: rejected
```

Cela n'empêche *pas* de distribuer : cela signifie seulement que macOS ne se
porte pas garant, et que vos utilisateurs doivent dire qu'ils vous font
confiance. Trois voies, par coût croissant :

1. **Homebrew sans quarantaine.** C'est l'attribut de quarantaine qui déclenche
   l'avertissement ; s'en passer supprime toute friction, au prix de demander
   aux utilisateurs de faire confiance au tap.

   ```sh
   brew install --cask --no-quarantine oudivad/tap/peek3d
   ```

   L'adresse se lit *utilisateur / tap / recette* : la partie du milieu est le
   dépôt qui contient les recettes, que Homebrew cherche sous le nom
   `homebrew-tap`, et le dernier mot est la recette. Pas besoin de `brew tap`
   au préalable : Homebrew s'en charge en voyant une adresse en trois parties.
   Le fichier `Casks/peek3d.rb` de ce dépôt est la recette à y copier.

2. **Téléchargement simple.** L'utilisateur glisse l'application dans
   /Applications, puis l'autorise une fois depuis Réglages Système >
   Confidentialité et sécurité > *Ouvrir quand même*. Ou, en une commande :

   ```sh
   xattr -dr com.apple.quarantine /Applications/Peek3D.app
   ```

3. **Developer ID et notarisation** (99 $/an). Aucun avertissement, aucune
   consigne à lire, rien à expliquer. C'est ce que font la plupart des
   applications Mac abouties, y compris gratuites — quelqu'un paye derrière.

   ```sh
   make app CODESIGN_ID="Developer ID Application: Votre Nom (XXXXXXXXXX)"
   xcrun notarytool submit Peek3D.dmg --keychain-profile peek3d --wait
   xcrun stapler staple Peek3D.dmg
   ```

Une signature ad hoc suffit à ce que l'extension Quick Look se charge : vérifié
ici, l'extension sert les aperçus depuis une version non notarisée. Ce que
paye le certificat, c'est l'absence de dialogue inquiétant, pas le droit de
fonctionner.

## Architecture

```
Sources/
  Peek3DKit/            lecteurs de fichiers, rendu, vue partagée
  OCCTBridge/           interface C au-dessus d'OpenCASCADE (C++)
  Peek3DApp/            application hôte : fenêtre, glisser-déposer
  QuickLookExtension/   l'aperçu déclenché par la barre d'espace
  ThumbnailExtension/   les vignettes du Finder
```

Trois choix structurent le reste.

**Les normales sont recalculées avec un angle de rupture.** Un STL ne contient
que des triangles indépendants. Les souder naïvement et moyenner les normales
arrondit les arêtes d'une pièce mécanique ; ne rien souder facettise les
surfaces courbes. Peek3D regroupe donc les faces qui se rejoignent en un point
par orientation : au-delà de 35° d'écart, elles reçoivent des normales
distinctes. Un cube garde ses arêtes franches, une sphère reste lisse.

**Tout est ramené à une sphère unité.** Les modèles vont du micron au mètre.
Centrer et normaliser avant l'affichage évite à la fois des réglages de caméra
dépendants de la pièce et la perte de précision des flottants sur les cas
extrêmes.

**Le code de lecture est partagé, les bibliothèques aussi.** Les extensions
embarquent chacune le même code Swift, mais OpenCASCADE n'existe qu'en un seul
exemplaire dans `Contents/Frameworks`, référencé en `@rpath`. L'application
complète pèse une quarantaine de mégaoctets.

## Limites connues

- **Vignettes du Finder.** L'extension d'aperçu fonctionne ; l'extension de
  vignettes est en place mais macOS ne la sollicite pas encore de façon fiable
  pour les formats CAO. Les fichiers concernés gardent alors l'icône générique.
- **Application par défaut des .3mf.** Peek3D déclare un type pour le 3MF, que
  macOS ne connaît pas seul. Si un trancheur est installé, ajouter cette
  déclaration amène LaunchServices à reclasser les applications qui
  revendiquent `.3mf`, et l'ouvreur par défaut peut changer — de Bambu Studio
  à OrcaSlicer, par exemple. Rétablissez-le depuis le Finder : sélectionnez un
  fichier, **Lire les informations**, puis **Ouvrir avec › Tout modifier**.
- **USD, USDZ, Alembic.** Non lus par Peek3D. Si vous activez la bascule
  ci-dessus, ils sont affichés par l'extension SceneKit du système.
- **Apple Silicon seulement.** La construction cible `arm64`. Un binaire
  universel demanderait un OpenCASCADE compilé pour les deux architectures.
- **OBJ sans matériaux.** Seule la géométrie est lue ; les fichiers `.mtl` et
  les textures sont ignorés, et de toute façon inaccessibles depuis une
  extension confinée.
- **Polygones concaves.** La triangulation en éventail suffit aux polygones
  convexes, qui sont l'immense majorité ; un polygone fortement concave peut
  s'afficher de travers.

## Licence

MIT, voir [LICENSE](LICENSE). Peek3D embarque OpenCASCADE Technology, sous
LGPL 2.1 avec exception.
