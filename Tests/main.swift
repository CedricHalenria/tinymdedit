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
