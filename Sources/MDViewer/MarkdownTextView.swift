import SwiftUI
import AppKit

/// Pont SwiftUI ↔ AppKit autour d'un `NSTextView`.
///
/// On garde `NSTextView` plutôt que le `TextEditor` de SwiftUI parce qu'il donne
/// accès au `NSTextStorage` et au `NSLayoutManager` — indispensables pour styler
/// le texte à la frappe et masquer les marqueurs — et qu'il apporte gratuitement
/// l'annulation, la barre de recherche, le correcteur orthographique et le
/// comportement clavier standard de macOS.
struct MarkdownTextView: NSViewRepresentable {

    @Binding var text: String
    var isStyled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Bascule volontairement sur TextKit 1 : le masquage de glyphes passe par
        // NSLayoutManager, qui n'a pas d'équivalent direct en TextKit 2.
        let layoutManager = textView.layoutManager
        layoutManager?.delegate = context.coordinator.visibility

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter

        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.textContainerInset = Theme.textInset
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        context.coordinator.textView = textView
        context.coordinator.highlighter.isStyled = isStyled

        textView.string = text
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes
        context.coordinator.restyle()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Le texte n'est réinjecté que s'il diffère réellement : sinon on
        // ferait sauter le curseur à chaque frappe.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
            context.coordinator.restyle()
        }

        if context.coordinator.highlighter.isStyled != isStyled {
            context.coordinator.highlighter.isStyled = isStyled
            textView.typingAttributes = context.coordinator.highlighter.baseAttributes
            context.coordinator.restyle()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let highlighter = MarkdownHighlighter()
        let visibility = MarkerVisibilityController()
        weak var textView: NSTextView?
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            // Le highlighter vient de relever de nouveaux marqueurs pendant
            // `didProcessEditing` : on les transmet et on redemande les glyphes.
            syncVisibility()

            // Depuis la modification jusqu'à la fin du document : insérer ou
            // supprimer un caractère décale toutes les positions qui suivent, et
            // les glyphes déjà calculés plus bas correspondraient alors aux
            // anciennes positions — marqueurs masqués de travers.
            guard let storage = textView.textStorage else { return }
            let from = min(highlighter.lastEditLocation ?? 0, storage.length)
            invalidateGlyphs(in: NSRange(location: from, length: storage.length - from))
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let previous = visibility.selection
            // Rien à faire si le déplacement du curseur ne change pas ce qui est masqué.
            guard visibility.setSelection(textView.selectedRange()) else { return }
            invalidateGlyphs(around: previous)
            invalidateGlyphs(around: textView.selectedRange())
        }

        /// Force une passe de stylage complète (changement de mode, texte remplacé).
        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            highlighter.rehighlight(storage)
            visibility.setSelection(textView.selectedRange())
            syncVisibility()
            invalidateGlyphs(in: NSRange(location: 0, length: storage.length))
        }

        private func syncVisibility() {
            visibility.update(
                markers: highlighter.hiddenMarkers,
                substitutions: highlighter.substitutions,
                enabled: highlighter.isStyled && highlighter.markersAreComplete
            )
        }

        /// Redemande la génération des glyphes autour d'une position, en couvrant
        /// le paragraphe entier — un marqueur ne s'étend jamais au-delà.
        private func invalidateGlyphs(around range: NSRange) {
            guard let storage = textView?.textStorage else { return }
            let ns = storage.string as NSString
            guard ns.length > 0 else { return }
            let clamped = NSRange(location: min(range.location, ns.length), length: 0)
            invalidateGlyphs(in: ns.paragraphRange(for: clamped))
        }

        private func invalidateGlyphs(in range: NSRange) {
            guard let layoutManager = textView?.layoutManager, range.length > 0 else { return }
            layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
    }
}
