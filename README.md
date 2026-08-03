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

> **Premier lancement, quelle que soit la voie choisie.** Tant que l'application
> n'est pas notarisée par Apple, macOS refuse de l'ouvrir — y compris installée
> par Homebrew. Allez dans **Réglages Système → Confidentialité et sécurité**,
> puis cliquez sur **Ouvrir quand même** en bas de la fenêtre. C'est à faire une
> seule fois ; les lancements suivants sont normaux.

### Par Homebrew

```sh
brew tap CedricHalenria/tap
brew trust CedricHalenria/tap
brew install --cask tinymdedit
```

Installation et mises à jour en une commande — `brew upgrade --cask tinymdedit`.
L'étape `brew trust` est exigée depuis Homebrew 6 pour tout cask provenant d'un
tap tiers ; elle n'est à faire qu'une fois.

### Par téléchargement direct

Récupérez la dernière archive sur la [page des versions](https://github.com/CedricHalenria/tinymdedit/releases),
décompressez-la et glissez **TinyMDEdit.app** dans `/Applications`.

### En compilant soi-même

Prérequis : macOS 14+, et le toolchain Swift — les Command Line Tools suffisent,
**Xcode n'est pas nécessaire**.

```sh
git clone https://github.com/CedricHalenria/tinymdedit.git
cd tinymdedit
./build.sh --run
```

L'app est produite dans `build/TinyMDEdit.app`.

```sh
./build.sh             # build release
./build.sh --debug     # build debug
./build.sh --run       # build puis lance l'app
./build.sh --register  # fait de cette copie l'app par défaut des .md
./test.sh              # banc d'essai du moteur de stylage
./Tools/make-icon.sh   # régénère l'icône
```

La compilation **n'inscrit pas** sa copie auprès de Launch Services. Sans cela,
un exemplaire de développement disputerait l'ouverture des `.md` à celui installé
dans `/Applications` : deux bundles de même identifiant, et macOS choisit seul
lequel répond au double-clic. `--register` force l'inscription quand on veut
travailler sur la copie locale.

L'icône n'est pas un binaire livré tel quel : elle est **dessinée par du code**
(`Tools/make-icon/main.swift`), donc lisible et modifiable comme le reste.

## Vie privée

L'application ne collecte rien et n'envoie rien. Sa **seule** connexion réseau
est la recherche de nouvelles versions : une requête vers l'API publique des
releases de ce dépôt, au plus une fois par jour, sans aucun identifiant. Elle se
désactive dans le menu **TinyMDEdit → Vérifier automatiquement**, et l'app
n'installe jamais rien d'elle-même — elle ouvre la page de téléchargement.

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
