# MDViewer

Un éditeur/visualiseur Markdown **natif macOS**, volontairement minimal — l'esprit de
TextEdit, appliqué au Markdown.

## L'idée

Il n'y a pas deux textes, pas de panneau d'aperçu, pas de conversion. Il y a **le fichier
`.md`, et rien d'autre**. L'app se contente de l'afficher joliment : les titres sont
gros, le gras est gras, les marqueurs (`##`, `**`, `-`) restent visibles mais s'effacent
en gris discret.

Conséquence directe : **on tape dans le texte mis en page**, exactement comme dans le
texte brut. Ce qui est à l'écran est ce qui est sur le disque, octet pour octet.

Un sélecteur dans la barre d'outils (ou ⇧⌘M) bascule vers le **mode texte brut** :
monospace uniforme, aucune coloration, le fichier tel qu'il est.

## Installation

Prérequis : macOS 14+, Apple Silicon, et le toolchain Swift (les Command Line Tools
suffisent — **Xcode n'est pas nécessaire**).

```sh
git clone https://github.com/<compte>/mdviewer.git
cd mdviewer
./build.sh --run
```

L'app est produite dans `build/MDViewer.app`. Glissez-la dans `/Applications` si vous
voulez la garder.

```sh
./build.sh          # build release
./build.sh --debug  # build debug
./test.sh           # banc d'essai du moteur de stylage
```

## Syntaxe reconnue

| Élément | Rendu |
|---|---|
| `#` … `######` | titres, six tailles |
| `**gras**`, `__gras__` | gras |
| `*italique*`, `_italique_` | italique |
| `***gras italique***` | les deux |
| `~~barré~~` | barré |
| `` `code` `` | monospace sur fond coloré |
| ``` ```bloc``` ``` | bloc monospace, contenu non réinterprété |
| `> citation` | italique, décalé |
| `-`, `*`, `+`, `1.` | listes, puce en couleur d'accent, retrait suspendu |
| `- [ ]`, `- [x]` | cases à cocher |
| `[texte](url)` | libellé souligné, URL en retrait visuel |
| `<https://…>` | lien automatique |
| `---`, `***` | filet horizontal |

## Architecture

Quatre fichiers, aucune dépendance externe.

| Fichier | Rôle |
|---|---|
| `MDViewerApp.swift` | le `DocumentGroup` : ouverture, enregistrement, fenêtres, menus |
| `MarkdownDocument.swift` | le document — une `String`, rien de plus |
| `MarkdownTextView.swift` | pont SwiftUI ↔ `NSTextView` |
| `MarkdownHighlighter.swift` | le moteur : pose les attributs de style sur le texte source |
| `Theme.swift` | fontes, couleurs, métriques — tout le rendu se règle ici |

Le moteur est un `NSTextStorageDelegate` : à chaque frappe, il repose les attributs
d'affichage sur les paragraphes touchés. Il ne modifie **jamais** un caractère du
document. Au-delà de 200 000 caractères, il ne restyle plus que les paragraphes édités
au lieu du document entier.

`NSTextView` est préféré au `TextEditor` de SwiftUI parce qu'il donne accès au
`NSTextStorage`, et qu'il apporte gratuitement l'annulation, la barre de recherche, le
correcteur orthographique et le comportement clavier standard de macOS.

## Licence

MIT — voir [LICENSE](LICENSE).
