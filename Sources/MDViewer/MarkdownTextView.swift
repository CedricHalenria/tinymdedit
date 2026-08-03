import SwiftUI
import AppKit

/// Pont SwiftUI ↔ AppKit autour d'un `NSTextView`.
///
/// On garde `NSTextView` plutôt que le `TextEditor` de SwiftUI parce qu'il donne
/// accès au `NSTextStorage` — indispensable pour styler le texte à la frappe — et
/// qu'il apporte gratuitement l'annulation, la barre de recherche, le correcteur
/// orthographique et le comportement clavier standard de macOS.
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

        // Bascule volontairement sur TextKit 1 : la coloration syntaxique via
        // NSTextStorageDelegate y est nettement plus prévisible.
        _ = textView.layoutManager

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
        weak var textView: NSTextView?
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// Force une passe de stylage complète (changement de mode, texte remplacé).
        func restyle() {
            guard let storage = textView?.textStorage else { return }
            highlighter.rehighlight(storage)
        }
    }
}
