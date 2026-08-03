import AppKit

/// Masque les marqueurs Markdown à l'affichage, sans jamais toucher au document.
///
/// La technique : `NSLayoutManager` demande à son délégué de produire les glyphes
/// d'une plage de texte. On y déclare les glyphes des marqueurs comme **nuls** —
/// ils ne sont alors ni dessinés, ni comptés dans la largeur de la ligne. Les
/// caractères, eux, sont toujours là : le fichier est intact et la sélection les
/// traverse normalement.
///
/// Les marqueurs d'un élément réapparaissent dès que le curseur entre dedans,
/// afin de rester éditables — un titre reste un titre qu'on peut dégrader en
/// sous-titre, un gras reste un gras qu'on peut défaire.
final class MarkerVisibilityController: NSObject, NSLayoutManagerDelegate {

    /// Désactivé en mode texte brut, ou quand le relevé des marqueurs est partiel.
    var isEnabled = false

    private var markers: [MarkdownHighlighter.MarkerRange] = []
    private var allSubstitutions: [MarkdownHighlighter.GlyphSubstitution] = []

    /// Index des caractères effectivement masqués et substitués, recalculés à
    /// chaque changement de texte ou de sélection.
    private var hidden = IndexSet()
    private var substituted: [Int: Character] = [:]

    private(set) var selection = NSRange(location: 0, length: 0)
    private var glyphCache: [String: CGGlyph] = [:]

    // MARK: - Mise à jour

    func update(
        markers: [MarkdownHighlighter.MarkerRange],
        substitutions: [MarkdownHighlighter.GlyphSubstitution],
        enabled: Bool
    ) {
        self.markers = markers
        self.allSubstitutions = substitutions
        self.isEnabled = enabled
        recompute()
    }

    /// Renvoie `true` si le changement de sélection modifie ce qui est masqué —
    /// donc s'il faut redemander la génération des glyphes.
    @discardableResult
    func setSelection(_ range: NSRange) -> Bool {
        let previous = hidden
        selection = range
        recompute()
        return previous != hidden
    }

    private func recompute() {
        var newHidden = IndexSet()
        var newSubstituted: [Int: Character] = [:]

        if isEnabled {
            for marker in markers where !reveals(marker.element) {
                guard marker.marker.length > 0 else { continue }
                newHidden.insert(integersIn: marker.marker.location ..< marker.marker.upperBound)
            }
            for substitution in allSubstitutions {
                // Une substitution rattachée à un élément s'efface quand le
                // curseur y entre : on doit revoir la syntaxe pour l'éditer.
                if let element = substitution.element, reveals(element) { continue }
                newSubstituted[substitution.range.location] = substitution.character
            }
        }

        hidden = newHidden
        substituted = newSubstituted
    }

    /// Le caractère à cet index est-il masqué à l'affichage ?
    func isHidden(_ characterIndex: Int) -> Bool {
        hidden.contains(characterIndex)
    }

    /// Le caractère à cet index est-il actuellement redessiné autrement ?
    func isSubstituted(_ characterIndex: Int) -> Bool {
        substituted[characterIndex] != nil
    }

    /// Le curseur touche-t-il cet élément ? Les bornes sont inclusives, pour que
    /// poser le curseur juste avant ou juste après suffise à révéler les marqueurs.
    private func reveals(_ element: NSRange) -> Bool {
        selection.location <= element.upperBound && selection.upperBound >= element.location
    }

    // MARK: - NSLayoutManagerDelegate

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        // 0 = « je ne fais rien de particulier, applique le comportement par défaut ».
        guard isEnabled, !hidden.isEmpty || !substituted.isEmpty else { return 0 }

        let count = glyphRange.length
        var newProps = Array(UnsafeBufferPointer(start: props, count: count))
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var changed = false

        for i in 0 ..< count {
            let characterIndex = charIndexes[i]
            if hidden.contains(characterIndex) {
                newProps[i] = .null
                changed = true
            } else if let character = substituted[characterIndex],
                      let glyph = glyph(for: character, in: font) {
                newGlyphs[i] = glyph
                changed = true
            }
        }

        guard changed else { return 0 }

        layoutManager.setGlyphs(
            &newGlyphs,
            properties: &newProps,
            characterIndexes: UnsafeMutablePointer(mutating: charIndexes),
            font: font,
            forGlyphRange: glyphRange
        )
        return count
    }

    /// Glyphe d'un caractère dans la fonte d'un fragment donné, mis en cache.
    /// Renvoie `nil` si la fonte ne contient pas ce caractère — auquel cas on
    /// laisse le glyphe d'origine plutôt que d'afficher une case vide.
    private func glyph(for character: Character, in font: NSFont) -> CGGlyph? {
        let key = "\(font.fontName)-\(font.pointSize)-\(character)"
        if let cached = glyphCache[key] {
            return cached == 0 ? nil : cached
        }
        var characters = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let found = CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, characters.count)
        let glyph = (found && characters.count == 1) ? (glyphs.first ?? 0) : 0
        glyphCache[key] = glyph
        return glyph == 0 ? nil : glyph
    }
}
