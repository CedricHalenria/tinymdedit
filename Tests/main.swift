import AppKit

// Banc d'essai du moteur de stylage et du masquage des marqueurs.
// Voir ./test.sh — ne nécessite ni Xcode ni XCTest.

let sample = """
# Titre 1
Du texte avec du **gras** et de l'*italique* et du `code`.
- item de liste
1. item numéroté
- [ ] tâche à faire
- [x] tâche finie
> citation
```swift
// bloc **non** interprété
let message = "Bonjour"  // 42 à la fin
```
[lien](https://exemple.fr)
"""

let storage = NSTextStorage(string: sample)
let hl = MarkdownHighlighter()
storage.delegate = hl
hl.rehighlight(storage)

var ok = 0, ko = 0
func check(_ label: String, _ condition: Bool) {
    if condition { ok += 1; print("  ✓ \(label)") } else { ko += 1; print("  ✗ \(label)") }
}

let ns = sample as NSString
func paragraph0(_ needle: String, _ o: Int = 0) -> NSParagraphStyle {
    storage.attributes(at: (sample as NSString).range(of: needle).location + o,
                       effectiveRange: nil)[.paragraphStyle] as! NSParagraphStyle
}
func at(_ needle: String, _ offsetInNeedle: Int = 0) -> Int {
    ns.range(of: needle).location + offsetInNeedle
}
func attrs(_ needle: String, _ offsetInNeedle: Int = 0) -> [NSAttributedString.Key: Any] {
    storage.attributes(at: at(needle, offsetInNeedle), effectiveRange: nil)
}
func font(_ needle: String, _ o: Int = 0) -> NSFont { attrs(needle, o)[.font] as! NSFont }
func color(_ needle: String, _ o: Int = 0) -> NSColor? { attrs(needle, o)[.foregroundColor] as? NSColor }

print("MODE MISE EN PAGE — attributs")
check("titre en grand (30pt)", font("Titre 1").pointSize == 30)
check("marqueur ## en gris", color("# Titre") == Theme.marker)
check("gras appliqué", font("gras").fontDescriptor.symbolicTraits.contains(.bold))
check("italique appliqué", font("italique").fontDescriptor.symbolicTraits.contains(.italic))
check("code en ligne monospace", font("`code`", 1).isFixedPitch)
check("code en ligne en vert", color("`code`", 1) == Theme.codeText)
check("code en ligne sans fond", attrs("`code`", 1)[.backgroundColor] == nil)
check("bloc de code avec fond", attrs("bloc **non**")[.backgroundColor] != nil)
check("puce sans couleur particulière", color("- item") == Theme.text)
check("numéro sans couleur particulière", color("1. item") == Theme.text)
check("citation en italique", font("citation").fontDescriptor.symbolicTraits.contains(.italic))
check("bloc de code monospace", font("// bloc").isFixedPitch)
check("gras NON interprété dans le bloc", !font("**non**", 2).fontDescriptor.symbolicTraits.contains(.bold))

print("\nCOLORATION DU CODE")
check("commentaire en gris", color("// bloc") == Theme.codeComment)
check("commentaire en italique", font("// bloc").fontDescriptor.symbolicTraits.contains(.italic))
check("mot-clé « let » coloré", color("let message") == Theme.codeKeyword)
check("identifiant en vert de base", color("message =") == Theme.codeText)
check("chaîne colorée", color("\"Bonjour\"") == Theme.codeString)
check("commentaire de fin de ligne en gris", color("// 42") == Theme.codeComment)
check("nombre dans un commentaire non recoloré", color("42 à la fin") == Theme.codeComment)
check("libellé de lien en accent", color("lien") == Theme.accent)
check("texte courant normal", font("Du texte").pointSize == Theme.bodySize)

print("\nMASQUAGE DES MARQUEURS — curseur à l'écart")
let visibility = MarkerVisibilityController()
visibility.update(markers: hl.hiddenMarkers, substitutions: hl.substitutions,
                  enabled: hl.markersAreComplete)
func substitution(_ index: Int) -> Character? {
    hl.substitutions.first { $0.range.location == index }?.character
}
// Curseur sur du texte courant, à l'écart de tout élément : rien ne doit être révélé.
// (Attention : les bornes de révélation sont inclusives, poser le curseur en fin
// de document révélerait le dernier élément — ici le lien.)
visibility.setSelection(NSRange(location: at("avec"), length: 0))

check("relevé des marqueurs complet", hl.markersAreComplete)
check("« # » masqué", visibility.isHidden(at("# Titre")))
check("espace après « # » masqué", visibility.isHidden(at("# Titre", 1)))
check("titre lui-même visible", !visibility.isHidden(at("Titre 1")))
check("« ** » ouvrant masqué", visibility.isHidden(at("**gras**")) && visibility.isHidden(at("**gras**", 1)))
check("« ** » fermant masqué", visibility.isHidden(at("**gras**", 6)))
check("mot « gras » visible", !visibility.isHidden(at("**gras**", 2)))
check("« * » d'italique masqué", visibility.isHidden(at("*italique*")))
check("accents graves du code masqués", visibility.isHidden(at("`code`")) && visibility.isHidden(at("`code`", 5)))
check("contenu du code visible", !visibility.isHidden(at("`code`", 1)))
check("« [ » du lien masqué", visibility.isHidden(at("[lien]")))
check("URL du lien masquée", visibility.isHidden(at("https://exemple.fr")))
check("libellé du lien visible", !visibility.isHidden(at("lien]")))
check("« > » de citation masqué", visibility.isHidden(at("> citation")))
check("tiret de liste NON masqué (devient une puce)", !visibility.isHidden(at("- item")))
check("tiret dessiné en « • »", substitution(at("- item")) == "•")

print("\nBLOCS DE CODE ET CASES À COCHER")
check("« ```swift » masqué", visibility.isHidden(at("```swift")) && visibility.isHidden(at("```swift", 5)))
check("« ``` » de fermeture masqué", visibility.isHidden(at("```\n[lien]")))
check("contenu du bloc visible", !visibility.isHidden(at("// bloc")))
check("tiret de la tâche masqué", visibility.isHidden(at("- [ ]")))
check("crochets de la tâche masqués",
      visibility.isHidden(at("[ ] tâche")) && visibility.isHidden(at("[ ] tâche", 2)))
check("case vide dessinée en ☐", substitution(at("[ ] tâche", 1)) == Theme.uncheckedBox)
check("case cochée dessinée en ☑", substitution(at("[x] tâche", 1)) == Theme.checkedBox)
check("case à la fonte Apple Symbols", (attrs("[ ] tâche", 1)[.font] as? NSFont)?.fontName == Theme.symbol.fontName)
check("libellé de la tâche visible", !visibility.isHidden(at("tâche à faire")))

print("\nRÉVÉLATION AU CURSEUR")
visibility.setSelection(NSRange(location: at("Titre 1"), length: 0))
check("curseur dans le titre → « # » réapparaît", !visibility.isHidden(at("# Titre")))
check("… sans révéler le gras plus bas", visibility.isHidden(at("**gras**")))

// Régression : l'élément d'un bloc ne doit pas inclure son saut de ligne, sinon
// cliquer sous un titre ferait réapparaître son « # ».
visibility.setSelection(NSRange(location: at("Du texte"), length: 0))
check("curseur sous le titre → « # » reste masqué", visibility.isHidden(at("# Titre")))

visibility.setSelection(NSRange(location: at("**gras**", 3), length: 0))
check("curseur dans le gras → « ** » réapparaît", !visibility.isHidden(at("**gras**")))
check("… et le titre se remasque", visibility.isHidden(at("# Titre")))

visibility.setSelection(NSRange(location: at("**gras**"), length: 0))
check("curseur collé avant le gras → révélé aussi", !visibility.isHidden(at("**gras**")))

visibility.setSelection(NSRange(location: at("tâche à faire"), length: 0))
check("curseur dans la tâche → crochets réapparaissent", !visibility.isHidden(at("[ ] tâche")))
check("… et la case redevient l'espace d'origine", !visibility.isSubstituted(at("[ ] tâche", 1)))
check("… sans toucher à l'autre tâche", visibility.isSubstituted(at("[x] tâche", 1)))

visibility.setSelection(NSRange(location: at("// bloc"), length: 0))
check("curseur dans le code → « ```swift » reste masqué", visibility.isHidden(at("```swift")))
visibility.setSelection(NSRange(location: at("```swift", 4), length: 0))
check("curseur sur la délimitation → elle réapparaît", !visibility.isHidden(at("```swift")))

visibility.setSelection(NSRange(location: at("avec"), length: 0))
check("puce toujours dessinée, curseur où qu'il soit", visibility.isSubstituted(at("- item")))

print("\nCASES À COCHER CLIQUABLES")
check("deux cases relevées", hl.checkboxes.count == 2)
check("case vide repérée à la bonne position",
      hl.checkboxes.contains { $0.location == at("[ ] tâche", 1) })
check("case cochée repérée à la bonne position",
      hl.checkboxes.contains { $0.location == at("[x] tâche", 1) })

// Bascule : le clic ne fait que remplacer un caractère par un autre, ce qui
// laisse toutes les positions inchangées.
let clickable = NSTextStorage(string: sample)
let clickHighlighter = MarkdownHighlighter()
clickable.delegate = clickHighlighter
clickHighlighter.rehighlight(clickable)
let emptyBox = at("[ ] tâche", 1)
func drawn(_ h: MarkdownHighlighter, _ index: Int) -> Character? {
    h.substitutions.first { $0.range.location == index }?.character
}
check("avant clic : case vide", drawn(clickHighlighter, emptyBox) == Theme.uncheckedBox)
clickable.replaceCharacters(in: NSRange(location: emptyBox, length: 1), with: "x")
check("après clic : case cochée", drawn(clickHighlighter, emptyBox) == Theme.checkedBox)
check("longueur du document inchangée", clickable.length == (sample as NSString).length)
clickable.replaceCharacters(in: NSRange(location: emptyBox, length: 1), with: " ")
check("second clic : case revidée", drawn(clickHighlighter, emptyBox) == Theme.uncheckedBox)

print("\nEMPHASE À CHEVAL SUR DEUX LIGNES")
// Cas réel rencontré dans le README du projet : en Markdown, un simple retour à
// la ligne au milieu d'un paragraphe est une coupure douce, le gras le traverse.
let wrapped = NSTextStorage(string: "Il y a **le fichier\n`.md`, et rien d'autre**. Fin.\n\n## Suite\n")
let wrappedHighlighter = MarkdownHighlighter()
wrapped.delegate = wrappedHighlighter
wrappedHighlighter.rehighlight(wrapped)
let wns = wrapped.string as NSString
func wrappedFont(_ needle: String) -> NSFont {
    wrapped.attributes(at: wns.range(of: needle).location, effectiveRange: nil)[.font] as! NSFont
}
let wrappedVisibility = MarkerVisibilityController()
wrappedVisibility.update(markers: wrappedHighlighter.hiddenMarkers,
                         substitutions: wrappedHighlighter.substitutions,
                         enabled: wrappedHighlighter.markersAreComplete)
wrappedVisibility.setSelection(NSRange(location: wns.range(of: "Fin.").location, length: 0))
check("gras appliqué avant le retour à la ligne",
      wrappedFont("le fichier").fontDescriptor.symbolicTraits.contains(.bold))
check("gras appliqué après le retour à la ligne",
      wrappedFont("et rien").fontDescriptor.symbolicTraits.contains(.bold))
check("« ** » ouvrant masqué", wrappedVisibility.isHidden(wns.range(of: "**le").location))
check("« ** » fermant masqué", wrappedVisibility.isHidden(wns.range(of: "**. Fin").location))
check("texte après le gras non gras",
      !wrappedFont("Fin.").fontDescriptor.symbolicTraits.contains(.bold))
check("le titre suivant reste un titre", wrappedFont("## Suite").pointSize == 25)

// Une ligne vide ferme le paragraphe : aucune emphase ne doit la traverser.
let split = NSTextStorage(string: "Un **début\n\nune fin** ici\n")
let splitHighlighter = MarkdownHighlighter()
split.delegate = splitHighlighter
splitHighlighter.rehighlight(split)
let sns = split.string as NSString
let splitFont = split.attributes(at: sns.range(of: "début").location,
                                 effectiveRange: nil)[.font] as! NSFont
check("ligne vide : pas de gras à travers", !splitFont.fontDescriptor.symbolicTraits.contains(.bold))

print("\nCITATIONS ET COLONNE DE LECTURE")
check("un bloc de citation relevé", hl.quoteBlocks.count == 1)
check("bloc de citation à la bonne position",
      hl.quoteBlocks.first?.location == at("> citation"))
check("citation en retrait", paragraph0("> citation").firstLineHeadIndent == Theme.quoteIndent)

// Lignes de citation consécutives : la barre doit être continue, donc les
// lignes fusionnées en un seul bloc.
let quotes = NSTextStorage(string: "> une\n> deux\n\ntexte\n> trois\n")
let quoteHighlighter = MarkdownHighlighter()
quotes.delegate = quoteHighlighter
quoteHighlighter.rehighlight(quotes)
check("lignes consécutives fusionnées", quoteHighlighter.quoteBlocks.count == 2)
check("premier bloc couvre les deux lignes", quoteHighlighter.quoteBlocks.first?.length == 13)

print("\nGÉOMÉTRIE DU BLOC DE CODE")

check("délimitation réduite à une bande fine",
      paragraph0("```swift").maximumLineHeight == Theme.fencePadding)
check("bande jointive au code (aucun espacement)",
      paragraph0("```swift").paragraphSpacing == 0)
check("lignes de code jointives entre elles",
      paragraph0("// bloc").paragraphSpacing == 0 && paragraph0("// bloc").paragraphSpacingBefore == 0)
check("lignes de code à hauteur normale",
      paragraph0("// bloc").maximumLineHeight == 0)
check("séparation après le bloc", paragraph0("```\n[lien]").paragraphSpacing > 0)
check("deux délimitations relevées", hl.fenceLines.count == 2)

// Le curseur posé sur la délimitation lui rend sa hauteur, sinon le texte
// révélé serait tronqué par la bande de 7 points.
let fenceCaret = MarkdownHighlighter()
let fenceStorage = NSTextStorage(string: sample)
fenceStorage.delegate = fenceCaret
fenceCaret.caretLocation = (sample as NSString).range(of: "```swift").location + 2
fenceCaret.rehighlight(fenceStorage)
let openedFence = fenceStorage.attributes(at: fenceCaret.caretLocation, effectiveRange: nil)[.paragraphStyle] as! NSParagraphStyle
check("curseur sur la délimitation → hauteur rendue", openedFence.maximumLineHeight == 0)

print("\nTABLEAUX")
// Trois alignements différents, du gras dans une cellule, et une ligne pleine de
// barres qui n'est pas un tableau faute de ligne d'alignement.
let tableSource = """
Avant le tableau.

| Brique | Détail | Version |
|---|:---:|---:|
| Thème | Astra **Pro** | 4.13.4 |
| Extensions | Woo | 10 |

Après. | ceci n'est pas un tableau |
"""
let table = NSTextStorage(string: tableSource)
let tableHighlighter = MarkdownHighlighter()
table.delegate = tableHighlighter
tableHighlighter.rehighlight(table)

let tns = tableSource as NSString
func tAt(_ needle: String, _ o: Int = 0) -> Int { tns.range(of: needle).location + o }
func tAttrs(_ needle: String, _ o: Int = 0) -> [NSAttributedString.Key: Any] {
    table.attributes(at: tAt(needle, o), effectiveRange: nil)
}
func tFont(_ needle: String, _ o: Int = 0) -> NSFont { tAttrs(needle, o)[.font] as! NSFont }
func tParagraph(_ needle: String, _ o: Int = 0) -> NSParagraphStyle {
    tAttrs(needle, o)[.paragraphStyle] as! NSParagraphStyle
}

let tableVisibility = MarkerVisibilityController()
tableVisibility.update(markers: tableHighlighter.hiddenMarkers,
                       substitutions: tableHighlighter.substitutions,
                       stops: tableHighlighter.columnStops,
                       enabled: tableHighlighter.markersAreComplete)
tableVisibility.setSelection(NSRange(location: tAt("Avant"), length: 0))

/// Abscisse imposée par la barre qui ouvre la cellule où se trouve `needle`.
func stopBefore(_ needle: String) -> CGFloat? {
    var index = tAt(needle) - 1
    while index > 0, tns.character(at: index) != 0x7C { index -= 1 }
    return tableVisibility.advance(at: index)
}

check("en-tête en gras", tFont("Brique").fontDescriptor.symbolicTraits.contains(.bold))
check("corps en graisse normale", !tFont("Thème").fontDescriptor.symbolicTraits.contains(.bold))
check("gras interprété dans une cellule",
      tFont("Pro**").fontDescriptor.symbolicTraits.contains(.bold))
check("« ** » masqué dans une cellule", tableVisibility.isHidden(tAt("**Pro**")))
check("rangées jointives", tParagraph("Thème").paragraphSpacing == 0)
check("espacement après la dernière rangée", tParagraph("Extensions").paragraphSpacing > 0)

check("ligne d'alignement réduite à une bande",
      tParagraph("|---|").maximumLineHeight == Theme.tableRuleHeight)
check("ligne d'alignement masquée", tableVisibility.isHidden(tAt("|---|")))
check("un filet d'en-tête relevé", tableHighlighter.tableRules.count == 1)
check("largeur du filet renseignée", (tableHighlighter.tableRules.first?.width ?? 0) > 0)

check("barre de tête masquée", tableVisibility.isHidden(tAt("| Thème")))
check("espace de remplissage masqué", tableVisibility.isHidden(tAt("| Thème", 1)))
check("barre de queue masquée", tableVisibility.isHidden(tAt("4.13.4 |", 7)))
check("barre intérieure convertie en avance", stopBefore("Détail") != nil)
check("première colonne : toutes les rangées démarrent au bord",
      [tAt("| Brique"), tAt("| Thème"), tAt("| Extensions")]
          .allSatisfy { tableVisibility.isHidden($0) })
check("colonne centrée : la cellule étroite démarre plus loin",
      (stopBefore("Woo") ?? 0) > (stopBefore("Astra") ?? 0))
check("colonne à droite : chaque cellule cale sa fin sur la colonne",
      (stopBefore("10 |") ?? 0) > (stopBefore("4.13.4") ?? 0)
          && (stopBefore("4.13.4") ?? 0) > (stopBefore("Version") ?? 0))

// Sans ligne d'alignement, des barres verticales ne sont que des barres.
check("texte à barres non transformé en tableau",
      !tableVisibility.isHidden(tAt("| ceci")) && stopBefore("ceci") == nil)
check("… et il garde le paragraphe courant",
      tParagraph("Après.").paragraphSpacing == Theme.paragraph().paragraphSpacing)

tableVisibility.setSelection(NSRange(location: tAt("Astra"), length: 0))
check("curseur dans la rangée → les barres redeviennent des barres",
      stopBefore("Astra") == nil && !tableVisibility.isHidden(tAt("| Thème")))
check("… sans déplacer les autres rangées", stopBefore("Woo") != nil)

// Le curseur sur la ligne d'alignement lui rend sa hauteur, comme à une
// délimitation de bloc de code.
let ruleCaret = MarkdownHighlighter()
let ruleStorage = NSTextStorage(string: tableSource)
ruleStorage.delegate = ruleCaret
ruleCaret.caretLocation = tAt("|---|") + 2
ruleCaret.rehighlight(ruleStorage)
check("curseur sur la ligne d'alignement → hauteur rendue",
      (ruleStorage.attributes(at: ruleCaret.caretLocation,
                              effectiveRange: nil)[.paragraphStyle] as! NSParagraphStyle)
          .maximumLineHeight == 0)
check("ligne d'alignement reconnue comme réduite", ruleCaret.isOnCollapsedLine(tAt("|---|")))

// Une colonne alignée à gauche amène toutes ses rangées exactement au même point,
// quelle que soit la largeur de ce qui précède.
let aligned = NSTextStorage(string: "| Un | x |\n|---|---|\n| Trois | yyyy |\n")
let alignedHighlighter = MarkdownHighlighter()
aligned.delegate = alignedHighlighter
alignedHighlighter.rehighlight(aligned)
let alignedStops = alignedHighlighter.columnStops.map(\.x)
check("colonne à gauche : même abscisse sur toutes les rangées",
      alignedStops.count == 2 && alignedStops[0] == alignedStops[1])
check("l'abscisse tient compte de la cellule la plus large",
      (alignedStops.first ?? 0) > 0)

// Mise en page réelle : on assemble une pile TextKit et on relit l'abscisse à
// laquelle le texte a effectivement été posé. C'est le seul moyen de vérifier
// que la barre verticale, devenue caractère de contrôle, avance bien jusqu'à la
// colonne — le reste ne teste que l'intention.
print("\nTABLEAUX — mise en page réelle")
let laidText = "Avant.\n\n| Un | x |\n|---|---|\n| Trois | yyyy |\n"
let laid = NSTextStorage(string: laidText)
let laidHighlighter = MarkdownHighlighter()
laid.delegate = laidHighlighter
let laidLayout = NSLayoutManager()
laid.addLayoutManager(laidLayout)
let laidContainer = NSTextContainer(size: CGSize(width: 600, height: 10_000))
laidLayout.addTextContainer(laidContainer)
let laidVisibility = MarkerVisibilityController()
laidLayout.delegate = laidVisibility
laidHighlighter.rehighlight(laid)
laidVisibility.update(markers: laidHighlighter.hiddenMarkers,
                      substitutions: laidHighlighter.substitutions,
                      stops: laidHighlighter.columnStops,
                      enabled: laidHighlighter.markersAreComplete)
laidVisibility.setSelection(NSRange(location: 0, length: 0))
laidLayout.ensureLayout(for: laidContainer)

let lns = laidText as NSString
func drawnX(_ needle: String) -> CGFloat {
    let glyphs = laidLayout.glyphRange(forCharacterRange: lns.range(of: needle),
                                       actualCharacterRange: nil)
    return laidLayout.boundingRect(forGlyphRange: glyphs, in: laidContainer).minX
}
// Le conteneur pose le texte après une marge intérieure : les abscisses des
// colonnes, elles, se comptent depuis le bord du texte.
let padding = laidContainer.lineFragmentPadding
check("première colonne posée au bord du texte",
      abs(drawnX("Un") - padding) < 0.5 && abs(drawnX("Trois") - padding) < 0.5)
check("deuxième colonne posée exactement à l'abscisse calculée",
      abs(drawnX("x |") - padding - (laidHighlighter.columnStops.first?.x ?? 0)) < 0.5)
check("deuxième colonne alignée d'une rangée à l'autre",
      abs(drawnX("x |") - drawnX("yyyy")) < 0.5)

// Découpage : barres facultatives aux extrémités, barre échappée conservée.
let bare = "a | b\n--- | ---\nc | d\n" as NSString
if let parsed = MarkdownTable.detect(in: bare, from: bare.lineRange(for: NSRange(location: 0, length: 0)),
                                     limit: bare.length) {
    check("tableau sans barres aux extrémités reconnu", parsed.columnCount == 2)
    check("une rangée de corps", parsed.body.count == 1)
    check("aucune barre de tête", parsed.header.leadingBar == nil)
} else {
    check("tableau sans barres aux extrémités reconnu", false)
}
let escaped = "| a \\| b | c |\n|---|---|\n" as NSString
check("barre échappée non prise pour un séparateur",
      MarkdownTable.detect(in: escaped, from: escaped.lineRange(for: NSRange(location: 0, length: 0)),
                           limit: escaped.length)?.columnCount == 2)

print("\nCOMPARAISON DE VERSIONS")
check("version plus récente détectée", SemanticVersion.isNewer("0.2.0", than: "0.1.0"))
check("version identique ignorée", !SemanticVersion.isNewer("0.1.0", than: "0.1.0"))
check("version plus ancienne ignorée", !SemanticVersion.isNewer("0.1.0", than: "0.2.0"))
check("préfixe « v » ignoré", SemanticVersion.isNewer("v1.0.0", than: "0.9.9"))
check("comparaison numérique, pas alphabétique", SemanticVersion.isNewer("0.10.0", than: "0.9.0"))
check("longueurs différentes complétées par des zéros",
      !SemanticVersion.isNewer("1.2", than: "1.2.0") && SemanticVersion.isNewer("1.2.1", than: "1.2"))
check("suffixe de pré-version tronqué", !SemanticVersion.isNewer("1.0.0-beta.1", than: "1.0.0"))
check("composant illisible traité comme zéro", !SemanticVersion.isNewer("1.0.x", than: "1.0.0"))

print("\nÉDITION — les marqueurs suivent le décalage")
// Régression : insérer un caractère décale tout ce qui suit. Le relevé doit
// suivre — et la vue redemander la génération des glyphes jusqu'à la fin du
// document, sans quoi les marqueurs sont masqués aux anciennes positions.
let edited = NSTextStorage(string: "# Titre\n- **gras** ici\n")
let editedHighlighter = MarkdownHighlighter()
edited.delegate = editedHighlighter
editedHighlighter.rehighlight(edited)
func openingBold(_ h: MarkdownHighlighter) -> Int? {
    // Le « # » du titre fait lui aussi deux caractères : on ne garde que ce qui
    // se trouve après la première ligne.
    h.hiddenMarkers.first { $0.marker.length == 2 && $0.marker.location > 7 }?.marker.location
}
check("« ** » relevé avant édition", openingBold(editedHighlighter) == 10)
edited.replaceCharacters(in: NSRange(location: 7, length: 0), with: "s")
check("« ** » relevé après insertion", openingBold(editedHighlighter) == 11)
check("position de l'édition mémorisée", editedHighlighter.lastEditLocation == 7)

print("\nMODE TEXTE BRUT")
hl.isStyled = false
hl.rehighlight(storage)
visibility.update(markers: hl.hiddenMarkers, substitutions: hl.substitutions,
                  enabled: hl.isStyled && hl.markersAreComplete)
check("tout en monospace", font("Titre 1").isFixedPitch && font("gras").isFixedPitch)
check("aucune coloration", color("# Titre") == Theme.text && color("lien") == Theme.text)
check("titre à la taille courante", font("Titre 1").pointSize == Theme.monoSize)
check("aucun masquage", !visibility.isHidden(at("# Titre")) && !visibility.isHidden(at("**gras**")))

print("\n\(ok) réussis, \(ko) échoués")
exit(ko == 0 ? 0 : 1)
