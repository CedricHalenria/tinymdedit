import AppKit

/// Applique la mise en forme Markdown directement sur le texte source.
///
/// Principe : il n'y a **qu'un seul** texte, la source Markdown. On ne convertit
/// jamais rien : on se contente de poser des attributs d'affichage (fonte, couleur,
/// indentation) par-dessus. Les marqueurs (`##`, `**`, `-`) restent donc présents
/// dans le document et éditables — ils sont juste affichés en couleur discrète.
///
/// En mode texte brut, on pose un unique jeu d'attributs monospace sur tout le
/// document : aucune coloration, on voit le fichier tel qu'il est sur le disque.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    /// `true` = mise en page, `false` = texte brut.
    var isStyled: Bool = true

    /// Au-delà de cette taille, on ne restyle plus tout le document à chaque frappe
    /// mais seulement les paragraphes touchés (voir `rehighlight(_:in:)`).
    private let fullPassLimit = 200_000

    // MARK: - Expressions régulières

    private static func rx(_ pattern: String) -> NSRegularExpression {
        // Les motifs sont des constantes littérales : un échec ici est un bug de
        // développement, pas une erreur d'exécution possible.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    // Blocs (appliqués ligne par ligne)
    private static let headingRx = rx(#"^(#{1,6})([ \t]+)(.*)$"#)
    private static let fenceRx = rx(#"^[ \t]{0,3}(`{3,}|~{3,})"#)
    private static let quoteRx = rx(#"^[ \t]{0,3}(>+)[ \t]?"#)
    private static let listRx = rx(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)"#)
    private static let ruleRx = rx(#"^[ \t]{0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})[ \t]*$"#)
    private static let taskRx = rx(#"^[ \t]*[-*+][ \t]+(\[[ xX]\])"#)

    // Fragments en ligne
    private static let codeSpanRx = rx(#"(`+)([^`\n]|[^`\n].*?[^`\n])\1"#)
    private static let boldItalicRx = rx(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#)
    private static let boldRx = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicRx = rx(#"(?<![*_\w\\])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])"#)
    private static let strikeRx = rx(#"(~~)(?=\S)(.+?)(?<=\S)\1"#)
    private static let linkRx = rx(#"(!?\[)([^\]\n]*)(\]\()([^)\s]*)([^)\n]*)(\))"#)
    private static let autoLinkRx = rx(#"(<)((?:https?|mailto):[^>\s]+)(>)"#)

    // MARK: - NSTextStorageDelegate

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // On ne réagit qu'aux modifications de caractères : sans ce garde-fou,
        // nos propres changements d'attributs relanceraient la méthode en boucle.
        guard editedMask.contains(.editedCharacters) else { return }

        if textStorage.length <= fullPassLimit {
            rehighlight(textStorage)
        } else {
            let paragraphs = (textStorage.string as NSString).paragraphRange(for: editedRange)
            rehighlight(textStorage, in: paragraphs)
        }
    }

    // MARK: - Passe de stylage

    /// Restyle l'intégralité du document.
    func rehighlight(_ storage: NSTextStorage) {
        rehighlight(storage, in: NSRange(location: 0, length: storage.length))
    }

    /// Restyle une portion du document (étendue aux paragraphes complets).
    func rehighlight(_ storage: NSTextStorage, in requested: NSRange) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }

        let range = ns.paragraphRange(for: NSRange(
            location: min(requested.location, ns.length),
            length: min(requested.length, ns.length - min(requested.location, ns.length))
        ))

        // 1. On repart d'une base propre sur toute la zone.
        storage.setAttributes(baseAttributes, range: range)

        // En texte brut, on s'arrête là : monospace uniforme, zéro coloration.
        guard isStyled else { return }

        // 2. On détermine si la zone démarre à l'intérieur d'un bloc de code
        //    ouvert plus haut dans le document.
        var insideFence = fenceIsOpen(before: range.location, in: ns)

        // 3. Puis on style ligne par ligne.
        var cursor = range.location
        while cursor < NSMaxRange(range) {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let line = ns.substring(with: lineRange)

            if Self.fenceRx.firstMatch(in: line, range: line.fullRange) != nil {
                // La ligne de délimitation elle-même (``` ou ~~~).
                storage.addAttributes([
                    .font: Theme.mono(),
                    .foregroundColor: Theme.marker,
                    .backgroundColor: Theme.codeBackground
                ], range: lineRange)
                insideFence.toggle()
            } else if insideFence {
                storage.addAttributes([
                    .font: Theme.mono(),
                    .foregroundColor: Theme.text,
                    .backgroundColor: Theme.codeBackground
                ], range: lineRange)
            } else {
                styleBlock(storage, line: line, lineRange: lineRange)
            }

            cursor = NSMaxRange(lineRange)
            if lineRange.length == 0 { break } // sécurité anti-boucle infinie
        }
    }

    // MARK: - Blocs

    /// Style une ligne hors bloc de code : titre, citation, liste, filet ou paragraphe,
    /// puis applique les styles en ligne (gras, italique, code, liens…).
    private func styleBlock(_ storage: NSTextStorage, line: String, lineRange: NSRange) {
        let full = line.fullRange
        let offset = lineRange.location
        // Zone de contenu sur laquelle on cherchera ensuite les styles en ligne.
        var inlineScope = full

        if let m = Self.headingRx.firstMatch(in: line, range: full) {
            let level = m.range(at: 1).length
            storage.addAttributes([
                .font: Theme.heading(level),
                .paragraphStyle: Theme.paragraph(spacingBefore: level <= 2 ? 14 : 10, spacingAfter: 6)
            ], range: lineRange)
            // Les dièses gardent la taille du titre mais s'effacent en couleur.
            storage.addAttribute(.foregroundColor, value: Theme.marker,
                                 range: m.range(at: 1).shifted(by: offset))
            inlineScope = m.range(at: 3)

        } else if let m = Self.quoteRx.firstMatch(in: line, range: full) {
            storage.addAttributes([
                .font: Theme.bodyItalic,
                .foregroundColor: Theme.secondary,
                .paragraphStyle: Theme.paragraph(headIndent: 20, firstLineHeadIndent: 20)
            ], range: lineRange)
            storage.addAttribute(.foregroundColor, value: Theme.accent,
                                 range: m.range(at: 1).shifted(by: offset))
            inlineScope = NSRange(location: m.range.length, length: full.length - m.range.length)

        } else if Self.ruleRx.firstMatch(in: line, range: full) != nil {
            storage.addAttributes([
                .foregroundColor: Theme.marker,
                .paragraphStyle: Theme.paragraph(spacingBefore: 8)
            ], range: lineRange)
            inlineScope = NSRange(location: 0, length: 0)

        } else if let m = Self.listRx.firstMatch(in: line, range: full) {
            let indent = CGFloat(m.range(at: 1).length) * 12 + 22
            storage.addAttribute(.paragraphStyle,
                                 value: Theme.paragraph(headIndent: indent, spacingAfter: 3),
                                 range: lineRange)
            // La puce ou le numéro prend la couleur d'accent.
            storage.addAttribute(.foregroundColor, value: Theme.accent,
                                 range: m.range(at: 2).shifted(by: offset))
            // Case à cocher `- [ ]` / `- [x]`.
            if let task = Self.taskRx.firstMatch(in: line, range: full) {
                storage.addAttribute(.foregroundColor, value: Theme.marker,
                                     range: task.range(at: 1).shifted(by: offset))
            }
            inlineScope = NSRange(location: m.range.length, length: full.length - m.range.length)
        }

        guard inlineScope.length > 0 else { return }
        styleInline(storage, line: line, scope: inlineScope, offset: offset)
    }

    // MARK: - Fragments en ligne

    private func styleInline(_ storage: NSTextStorage, line: String, scope: NSRange, offset: Int) {
        // Le code en ligne est prioritaire : son contenu ne doit pas être
        // réinterprété comme du gras ou de l'italique.
        var codeRanges: [NSRange] = []
        Self.codeSpanRx.enumerateMatches(in: line, range: scope) { m, _, _ in
            guard let m else { return }
            codeRanges.append(m.range)
        }

        func isFree(_ range: NSRange) -> Bool {
            !codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        /// Applique une fonte au fragment complet et estompe les marqueurs qui l'encadrent.
        func emphasise(_ regex: NSRegularExpression, font: NSFont, extraAttributes: [NSAttributedString.Key: Any] = [:]) {
            regex.enumerateMatches(in: line, range: scope) { m, _, _ in
                guard let m, isFree(m.range) else { return }
                var attrs = extraAttributes
                attrs[.font] = font
                storage.addAttributes(attrs, range: m.range.shifted(by: offset))

                let markerLength = m.range(at: 1).length
                storage.addAttribute(.foregroundColor, value: Theme.marker,
                                     range: NSRange(location: m.range.location + offset,
                                                    length: markerLength))
                storage.addAttribute(.foregroundColor, value: Theme.marker,
                                     range: NSRange(location: NSMaxRange(m.range) + offset - markerLength,
                                                    length: markerLength))
            }
        }

        emphasise(Self.boldItalicRx, font: Theme.bodyBoldItalic)
        emphasise(Self.boldRx, font: Theme.bodyBold)
        emphasise(Self.italicRx, font: Theme.bodyItalic)
        emphasise(Self.strikeRx, font: Theme.body, extraAttributes: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: Theme.secondary
        ])

        // Liens : le libellé en couleur d'accent souligné, l'URL en retrait visuel.
        Self.linkRx.enumerateMatches(in: line, range: scope) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            storage.addAttributes([
                .foregroundColor: Theme.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: m.range(at: 2).shifted(by: offset))
            for group in [1, 3, 6] {
                storage.addAttribute(.foregroundColor, value: Theme.marker,
                                     range: m.range(at: group).shifted(by: offset))
            }
            storage.addAttributes([
                .foregroundColor: Theme.secondary,
                .font: Theme.mono(size: Theme.monoSize - 1)
            ], range: m.range(at: 4).shifted(by: offset))
        }

        Self.autoLinkRx.enumerateMatches(in: line, range: scope) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            storage.addAttributes([
                .foregroundColor: Theme.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: m.range(at: 2).shifted(by: offset))
        }

        // Enfin le code en ligne, appliqué en dernier pour rester prioritaire.
        for range in codeRanges {
            storage.addAttributes([
                .font: Theme.mono(),
                .foregroundColor: Theme.codeText,
                .backgroundColor: Theme.codeBackground
            ], range: range.shifted(by: offset))
        }
    }

    // MARK: - Utilitaires

    /// Attributs de base, réappliqués avant chaque passe pour effacer le style précédent.
    var baseAttributes: [NSAttributedString.Key: Any] {
        isStyled
            ? [.font: Theme.body, .foregroundColor: Theme.text, .paragraphStyle: Theme.paragraph()]
            : [.font: Theme.mono(), .foregroundColor: Theme.text, .paragraphStyle: Theme.rawParagraph]
    }

    /// Détermine si un bloc de code est ouvert juste avant `location`, en comptant
    /// les délimiteurs rencontrés depuis le début du document. Utile quand on ne
    /// restyle qu'une portion d'un très gros fichier.
    private func fenceIsOpen(before location: Int, in ns: NSString) -> Bool {
        guard location > 0 else { return false }
        var open = false
        var cursor = 0
        while cursor < location {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let line = ns.substring(with: lineRange)
            if Self.fenceRx.firstMatch(in: line, range: line.fullRange) != nil {
                open.toggle()
            }
            cursor = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        return open
    }
}

// MARK: - Petites commodités

extension String {
    /// Plage couvrant toute la chaîne, en unités NSString (UTF-16).
    var fullRange: NSRange {
        NSRange(location: 0, length: (self as NSString).length)
    }
}

extension NSRange {
    /// Décale la plage, pour passer des coordonnées d'une ligne à celles du document.
    func shifted(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}
