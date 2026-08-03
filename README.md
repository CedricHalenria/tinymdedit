# TinyMDEdit

Un éditeur/visualiseur Markdown **natif macOS**, volontairement minimal — l'esprit de
TextEdit, appliqué au Markdown.

## L'idée

Il n'y a pas deux textes, pas de panneau d'aperçu, pas de conversion. Il y a **le fichier
`.md`, et rien d'autre**. L'app se contente de l'afficher joliment : les titres sont
gros, le gras est gras, et les marqueurs (`##`, `**`, `[ ]`) sont **masqués à
l'affichage** — sans jamais quitter le fichier.

Poser le curseur dans un élément fait réapparaître sa syntaxe, le temps de la modifier.
Conséquence directe : **on tape dans le texte mis en page**, exactement comme dans le
texte brut. Ce qui est à l'écran est ce qui est sur le disque, octet pour octet.

Un sélecteur dans la barre d'outils (ou ⇧⌘M) bascule vers le **mode texte brut** :
monospace uniforme, aucune coloration, le fichier tel qu'il est.

## Installation

Prérequis : macOS 14+, Apple Silicon, et le toolchain Swift (les Command Line Tools
suffisent — **Xcode n'est pas nécessaire**).

```sh
git clone https://github.com/CedricHalenria/tinymdedit.git
cd tinymdedit
./build.sh --run
```

L'app est produite dans `build/TinyMDEdit.app`. Glissez-la dans `/Applications` si vous
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
| `` `code` `` | monospace vert terminal, sans fond |
| ``` ```bloc``` ``` | bloc sur fond discret, délimiteurs masqués, syntaxe colorée |
| `> citation` | italique, décalé, barre verticale à gauche |
| `-`, `*`, `+`, `1.` | listes à retrait suspendu, tiret dessiné en « • » |
| `- [ ]`, `- [x]` | vraies cases ☐ / ☑, **cliquables** |
| `[texte](url)` | libellé souligné, URL en retrait visuel |
| `<https://…>` | lien automatique |
| `---`, `***` | filet horizontal |

## Architecture

Sept fichiers, aucune dépendance externe.

| Fichier | Rôle |
|---|---|
| `TinyMDEditApp.swift` | le `DocumentGroup` : ouverture, enregistrement, fenêtres, menus |
| `MarkdownDocument.swift` | le document — une `String`, rien de plus |
| `MarkdownTextView.swift` | pont SwiftUI ↔ `NSTextView` |
| `EditorTextView.swift` | la vue texte : clic sur les cases, barre des citations, colonne de lecture |
| `MarkdownHighlighter.swift` | le moteur : pose les attributs de style et relève les marqueurs |
| `MarkerVisibility.swift` | masque les marqueurs à l'écran et dessine puces et cases à cocher |
| `CodeHighlighter.swift` | coloration générique du contenu des blocs de code |
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
