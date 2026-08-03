import AppKit

// Banc d'essai du moteur de stylage et du masquage des marqueurs.
// Voir ./test.sh — ne nécessite ni Xcode ni XCTest.

let sample = """
# Titre 1
Du texte avec du **gras** et de l'*italique* et du `code`.
- item de liste
> citation
```
bloc **non** interprété
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
func at(_ needle: String, _ offsetInNeedle: Int = 0) -> Int {
    ns.range(of: needle).location + offsetInNeedle
}
func attrs(_ needle: String, _ offsetInNeedle: Int = 0) -> [NSAttributedString.Key: Any] {
    storage.attributes(at: at(needle, offsetInNeedle), effectiveRange: nil)
}
func font(_ needle: String, _ o: Int = 0) -> NSFont { attrs(needle, o)[.font] as! NSFont }
func color(_ needle: String, _ o: Int = 0) -> NSColor? { attrs(needle, o)[.foregroundColor] as? NSColor }

print("MODE MISE EN PAGE — attributs")
check("titre en grand (27pt)", font("Titre 1").pointSize == 27)
check("marqueur ## en gris", color("# Titre") == Theme.marker)
check("gras appliqué", font("gras").fontDescriptor.symbolicTraits.contains(.bold))
check("italique appliqué", font("italique").fontDescriptor.symbolicTraits.contains(.italic))
check("code en ligne monospace", font("`code`", 1).isFixedPitch)
check("code en ligne en vert", color("`code`", 1) == Theme.codeText)
check("code en ligne sans fond", attrs("`code`", 1)[.backgroundColor] == nil)
check("bloc de code avec fond", attrs("bloc **non**")[.backgroundColor] != nil)
check("puce en couleur d'accent", color("- item") == Theme.accent)
check("citation en italique", font("citation").fontDescriptor.symbolicTraits.contains(.italic))
check("bloc de code monospace", font("bloc **non**").isFixedPitch)
check("gras NON interprété dans le bloc", !font("**non**", 2).fontDescriptor.symbolicTraits.contains(.bold))
check("libellé de lien en accent", color("lien") == Theme.accent)
check("texte courant normal", font("Du texte").pointSize == Theme.bodySize)

print("\nMASQUAGE DES MARQUEURS — curseur à l'écart")
let visibility = MarkerVisibilityController()
visibility.update(markers: hl.hiddenMarkers, bullets: hl.bulletMarkers, enabled: hl.markersAreComplete)
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
check("puce relevée pour substitution", hl.bulletMarkers.contains { $0.location == at("- item") })

print("\nRÉVÉLATION AU CURSEUR")
visibility.setSelection(NSRange(location: at("Titre 1"), length: 0))
check("curseur dans le titre → « # » réapparaît", !visibility.isHidden(at("# Titre")))
check("… sans révéler le gras plus bas", visibility.isHidden(at("**gras**")))

visibility.setSelection(NSRange(location: at("**gras**", 3), length: 0))
check("curseur dans le gras → « ** » réapparaît", !visibility.isHidden(at("**gras**")))
check("… et le titre se remasque", visibility.isHidden(at("# Titre")))

visibility.setSelection(NSRange(location: at("**gras**"), length: 0))
check("curseur collé avant le gras → révélé aussi", !visibility.isHidden(at("**gras**")))

print("\nMODE TEXTE BRUT")
hl.isStyled = false
hl.rehighlight(storage)
visibility.update(markers: hl.hiddenMarkers, bullets: hl.bulletMarkers,
                  enabled: hl.isStyled && hl.markersAreComplete)
check("tout en monospace", font("Titre 1").isFixedPitch && font("gras").isFixedPitch)
check("aucune coloration", color("# Titre") == Theme.text && color("lien") == Theme.text)
check("titre à la taille courante", font("Titre 1").pointSize == Theme.monoSize)
check("aucun masquage", !visibility.isHidden(at("# Titre")) && !visibility.isHidden(at("**gras**")))

print("\n\(ok) réussis, \(ko) échoués")
exit(ko == 0 ? 0 : 1)
