import AppKit

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
func attrs(_ needle: String, _ offsetInNeedle: Int = 0) -> [NSAttributedString.Key: Any] {
    let r = ns.range(of: needle)
    return storage.attributes(at: r.location + offsetInNeedle, effectiveRange: nil)
}
func font(_ needle: String, _ o: Int = 0) -> NSFont { attrs(needle, o)[.font] as! NSFont }
func color(_ needle: String, _ o: Int = 0) -> NSColor? { attrs(needle, o)[.foregroundColor] as? NSColor }

print("MODE MISE EN PAGE")
check("titre en grand (27pt)", font("Titre 1").pointSize == 27)
check("marqueur ## en gris", color("# Titre") == Theme.marker)
check("gras appliqué", font("gras").fontDescriptor.symbolicTraits.contains(.bold))
check("marqueur ** en gris", color("**gras**") == Theme.marker)
check("italique appliqué", font("italique").fontDescriptor.symbolicTraits.contains(.italic))
check("code en ligne monospace", font("`code`", 1).isFixedPitch)
check("puce en couleur d'accent", color("- item", 0) == Theme.accent)
check("citation en italique", font("citation").fontDescriptor.symbolicTraits.contains(.italic))
check("bloc de code monospace", font("bloc **non**").isFixedPitch)
check("gras NON interprété dans le bloc", !font("**non**", 2).fontDescriptor.symbolicTraits.contains(.bold))
check("libellé de lien en accent", color("lien") == Theme.accent)
check("texte courant normal", font("Du texte").pointSize == Theme.bodySize)

print("\nMODE TEXTE BRUT")
hl.isStyled = false
hl.rehighlight(storage)
check("tout en monospace", font("Titre 1").isFixedPitch && font("gras").isFixedPitch)
check("aucune coloration", color("# Titre") == Theme.text && color("lien") == Theme.text)
check("titre à la taille courante", font("Titre 1").pointSize == Theme.monoSize)

print("\n\(ok) réussis, \(ko) échoués")
exit(ko == 0 ? 0 : 1)
