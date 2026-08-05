import AppKit

/// La vue texte de l'éditeur, avec une seule spécificité : les cases à cocher
/// répondent au clic.
///
/// Cocher une tâche est l'action la plus courante sur une liste ; passer par la
/// syntaxe `[ ]` → `[x]` pour cela serait absurde. Un clic sur la case bascule
/// donc le caractère dans le document, sans déplacer le curseur ni révéler la
/// ligne. La modification passe par `shouldChangeText` / `didChangeText`, ce qui
/// l'inscrit dans la pile d'annulation comme n'importe quelle frappe.
final class EditorTextView: NSTextView {

    /// Plages des caractères actuellement dessinés en case à cocher, fournies par
    /// la vue SwiftUI. Vide si le mode texte brut est actif.
    var clickableCheckboxes: () -> [NSRange] = { [] }

    /// Appelé avec l'index du caractère à basculer.
    var onToggleCheckbox: (Int) -> Void = { _ in }

    /// Blocs de citation, pour la barre verticale tracée dans la marge.
    var quoteBlocks: () -> [NSRange] = { [] }

    /// Filets d'en-tête de tableau, tracés dans la bande laissée par la ligne
    /// d'alignement.
    var tableRules: () -> [MarkdownHighlighter.TableRule] = { [] }

    /// Appelé quand la largeur réellement offerte au texte change. Les tableaux
    /// en dépendent : c'est elle qui décide si leurs colonnes tiennent.
    var onContentWidthChange: (CGFloat) -> Void = { _ in }

    // MARK: - Colonne de lecture

    /// Centre la colonne de texte et lui impose une largeur maximale : au-delà,
    /// les lignes deviennent trop longues pour que l'œil retrouve le début de la
    /// suivante. Les marges absorbent la largeur excédentaire.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(Theme.textInset.width, (newSize.width - Theme.maxContentWidth) / 2)
        // Le test évite de relancer la mise en page en boucle : modifier les
        // marges redimensionne la vue, ce qui rappelle cette méthode.
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: Theme.textInset.height)
        }
        // Ce qui reste au texte, une fois les marges et le retrait de fragment
        // retirés — l'abscisse d'une colonne de tableau se compte depuis là.
        let padding = textContainer?.lineFragmentPadding ?? 0
        onContentWidthChange(newSize.width - 2 * horizontal - 2 * padding)
    }

    // MARK: - Barre des citations et filets de tableau

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawTableRules(in: rect)
        Theme.quoteBar.setFill()
        for block in visible(quoteBlocks()) {
            guard var bar = boundingRect(for: block) else { continue }
            // La barre se place dans le retrait laissé libre à gauche du texte.
            bar.origin.x = textContainerOrigin.x + Theme.quoteIndent - 12
            bar.size.width = Theme.quoteBarWidth
            guard bar.intersects(rect) else { continue }
            NSBezierPath(
                roundedRect: bar,
                xRadius: Theme.quoteBarWidth / 2,
                yRadius: Theme.quoteBarWidth / 2
            ).fill()
        }
    }

    /// Le filet qui sépare l'en-tête d'un tableau de son corps. Il prend la place
    /// de la ligne `|---|---|`, effacée et réduite à une bande : la syntaxe
    /// disparaît, ce qu'elle disait reste.
    private func drawTableRules(in rect: NSRect) {
        let rules = tableRules()
        guard !rules.isEmpty else { return }
        Theme.tableRule.setFill()
        let visibleLines = visible(rules.map(\.header))
        for rule in rules where visibleLines.contains(where: { NSEqualRanges($0, rule.header) }) {
            // La ligne d'alignement n'a aucun glyphe dessiné : la mise en page ne
            // sait rien en dire. On part donc du bas de l'en-tête, et on descend
            // au milieu de la bande qu'elle occupe.
            guard let header = boundingRect(for: rule.header) else { continue }
            let line = NSRect(
                x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
                y: (header.maxY + (Theme.tableRuleHeight - Theme.tableRuleWidth) / 2).rounded(),
                width: rule.width,
                height: Theme.tableRuleWidth
            )
            guard line.intersects(rect) else { continue }
            line.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let index = checkbox(at: point) {
            onToggleCheckbox(index)
            return
        }
        super.mouseDown(with: event)
    }

    /// Main pointée au survol d'une case, pour signaler qu'elle est cliquable.
    override func resetCursorRects() {
        super.resetCursorRects()
        for range in visibleCheckboxes() {
            guard let rect = boundingRect(for: range) else { continue }
            addCursorRect(rect.insetBy(dx: -3, dy: -2), cursor: .pointingHand)
        }
    }

    // MARK: - Repérage

    private func checkbox(at point: NSPoint) -> Int? {
        for range in visibleCheckboxes() {
            guard let rect = boundingRect(for: range) else { continue }
            // Une case fait une douzaine de points de côté : on élargit un peu la
            // zone sensible pour ne pas exiger un clic au pixel près.
            if rect.insetBy(dx: -3, dy: -2).contains(point) { return range.location }
        }
        return nil
    }

    private func visibleCheckboxes() -> [NSRange] {
        visible(clickableCheckboxes())
    }

    /// Ne garde que les plages situées dans la partie affichée : calculer la
    /// géométrie d'une plage forcerait sinon la mise en page de tout le document.
    private func visible(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty, let layoutManager, let container = textContainer else { return [] }
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return ranges.filter { NSIntersectionRange($0, characters).length > 0 }
    }

    private func boundingRect(for range: NSRange) -> NSRect? {
        guard let layoutManager, let container = textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }
}
