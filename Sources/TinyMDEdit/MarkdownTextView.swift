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
        // Pile TextKit 1 assemblée à la main : le masquage de glyphes passe par
        // NSLayoutManager, qui n'a pas d'équivalent en TextKit 2, et les cases à
        // cocher cliquables demandent notre propre sous-classe de NSTextView.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        layoutManager.delegate = context.coordinator.visibility

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.minSize = CGSize.zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.clickableCheckboxes = { [weak coordinator = context.coordinator] in
            coordinator?.clickableCheckboxes() ?? []
        }
        textView.onToggleCheckbox = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleCheckbox(at: index)
        }
        textView.quoteBlocks = { [weak coordinator = context.coordinator] in
            guard let coordinator, coordinator.highlighter.isStyled else { return [] }
            return coordinator.highlighter.quoteBlocks
        }
        textView.tableRules = { [weak coordinator = context.coordinator] in
            guard let coordinator, coordinator.highlighter.isStyled,
                  coordinator.highlighter.markersAreComplete else { return [] }
            // Le filet ne se trace que sous une ligne d'alignement effacée : le
            // curseur posé dessus lui rend sa syntaxe, donc sa hauteur.
            return coordinator.highlighter.tableRules.filter {
                coordinator.visibility.isHidden($0.element.location)
            }
        }

        textView.onContentWidthChange = { [weak coordinator = context.coordinator] width in
            coordinator?.setContentWidth(width)
        }

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
            let selection = textView.selectedRange()

            // Entrer ou sortir d'une ligne réduite à une bande (délimitation de
            // bloc de code, ligne d'alignement d'un tableau) change sa hauteur :
            // c'est un attribut, donc une passe de stylage complète.
            let wasCollapsed = highlighter.isOnCollapsedLine(previous.location)
            let isCollapsed = highlighter.isOnCollapsedLine(selection.location)
            highlighter.caretLocation = selection.location
            if wasCollapsed != isCollapsed {
                restyle()
                return
            }

            // Sinon, rien à faire si le déplacement ne change pas ce qui est masqué.
            guard visibility.setSelection(selection) else { return }
            invalidateGlyphs(around: previous)
            invalidateGlyphs(around: selection)
        }

        /// La fenêtre a changé de largeur. Seuls les tableaux s'en soucient : eux
        /// seuls sont mis en page en fonction de la place disponible.
        func setContentWidth(_ width: CGFloat) {
            guard highlighter.setContentWidth(width) else { return }
            // On est au milieu d'un cycle de mise en page : restyler ici
            // réentrerait dans le gestionnaire. On attend le tour suivant.
            DispatchQueue.main.async { [weak self] in self?.restyle() }
        }

        /// Force une passe de stylage complète (changement de mode, texte remplacé).
        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            highlighter.caretLocation = textView.selectedRange().location
            highlighter.rehighlight(storage)
            visibility.setSelection(textView.selectedRange())
            syncVisibility()
            invalidateGlyphs(in: NSRange(location: 0, length: storage.length))
            textView.window?.invalidateCursorRects(for: textView)
            textView.needsDisplay = true
        }

        /// Cases réellement dessinées en case à cocher — donc cliquables. Une
        /// ligne dont le curseur a révélé la syntaxe n'en fait plus partie.
        func clickableCheckboxes() -> [NSRange] {
            guard highlighter.isStyled, highlighter.markersAreComplete else { return [] }
            return highlighter.checkboxes.filter { visibility.isSubstituted($0.location) }
        }

        /// Bascule `[ ]` ↔ `[x]` sans déplacer le curseur ni révéler la ligne.
        func toggleCheckbox(at index: Int) {
            guard let textView, let storage = textView.textStorage,
                  index < storage.length else { return }

            let range = NSRange(location: index, length: 1)
            let current = (storage.string as NSString).substring(with: range)
            let replacement = current.lowercased() == "x" ? " " : "x"

            // Passer par shouldChangeText/didChangeText inscrit la bascule dans
            // la pile d'annulation, au même titre qu'une frappe au clavier.
            let selection = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            storage.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()

            // Le curseur doit rester exactement où il était : le laisser atterrir
            // sur la ligne cochée y révélerait la syntaxe, et la ligne se
            // réindenterait sous le clic.
            textView.setSelectedRange(selection)

            // Un clic est rare : on se paie une passe complète plutôt que la mise
            // à jour partielle du cas « frappe au clavier », pour ne laisser aucun
            // reliquat de mise en page.
            restyle()
        }

        private func syncVisibility() {
            visibility.update(
                markers: highlighter.hiddenMarkers,
                substitutions: highlighter.substitutions,
                stops: highlighter.columnStops,
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
