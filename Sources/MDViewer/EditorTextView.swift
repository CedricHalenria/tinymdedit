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

    /// Ne considère que les cases situées dans la partie visible : calculer la
    /// géométrie d'une case forcerait sinon la mise en page de tout le document.
    private func visibleCheckboxes() -> [NSRange] {
        let checkboxes = clickableCheckboxes()
        guard !checkboxes.isEmpty,
              let layoutManager, let container = textContainer else { return [] }

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let visible = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        return checkboxes.filter { NSLocationInRange($0.location, visible) }
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
