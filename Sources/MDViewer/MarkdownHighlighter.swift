import AppKit

/// Applique la mise en forme Markdown directement sur le texte source.
///
/// Principe : il n'y a **qu'un seul** texte, la source Markdown. On ne convertit
/// jamais rien, on ne modifie jamais un caractère : on pose des attributs
/// d'affichage (fonte, couleur, indentation) par-dessus, et on relève les plages
/// de marqueurs (`##`, `**`, `[`, …) que la vue devra masquer à l'affichage.
///
/// En mode texte brut, on pose un unique jeu d'attributs monospace sur tout le
/// document : aucune coloration, aucun masquage, le fichier tel qu'il est.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    /// `true` = mise en page, `false` = texte brut.
    var isStyled: Bool = true

    /// Une plage de marqueurs à masquer, et l'élément Markdown auquel elle
    /// appartient. Quand le curseur entre dans `element`, les marqueurs
    /// redeviennent visibles pour rester éditables.
    struct MarkerRange {
        let marker: NSRange
        let element: NSRange
    }

    /// Un caractère du document à dessiner sous une autre forme : le tiret d'une
    /// liste devient « • », l'espace d'un `[ ]` devient « ☐ ». Le document, lui,
    /// n'est pas touché. Si `element` est renseigné, la substitution est annulée
    /// quand le curseur y entre, pour qu'on retrouve la syntaxe éditable.
    struct GlyphSubstitution {
        let range: NSRange
        let character: Character
        let element: NSRange?
    }

    /// Marqueurs masquables relevés lors de la dernière passe complète.
    private(set) var hiddenMarkers: [MarkerRange] = []
    /// Caractères à redessiner autrement.
    private(set) var substitutions: [GlyphSubstitution] = []
    /// `false` quand la dernière passe était partielle : les plages relevées sont
    /// alors incomplètes et le masquage doit être désactivé.
    private(set) var markersAreComplete = false

    /// Au-delà de cette taille, on ne restyle plus tout le document à chaque frappe
    /// mais seulement les paragraphes touchés — et on renonce au masquage, qui
    /// exige une vision d'ensemble du document.
    private let fullPassLimit = 200_000

    /// Vrai pendant une passe complète, quand on relève les marqueurs.
    private var collecting = false

    // MARK: - Expressions régulières

    private static func rx(_ pattern: String) -> NSRegularExpression {
        // Les motifs sont des constantes littérales : un échec ici est un bug de
        // développement, pas une erreur d'exécution possible.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    // Blocs (appliqués ligne par ligne)
    private static let headingRx = rx(#"^(#{1,6})([ \t]+)(.*)$"#)
    private static let fenceRx = rx(#"^[ \t]{0,3}(`{3,}|~{3,})"#)
    private static let quoteRx = rx(#"^[ \t]{0,3}(>+)([ \t]?)"#)
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

    /// Restyle l'intégralité du document et relève les marqueurs masquables.
    func rehighlight(_ storage: NSTextStorage) {
        hiddenMarkers.removeAll(keepingCapacity: true)
        substitutions.removeAll(keepingCapacity: true)
        collecting = isStyled
        markersAreComplete = isStyled
        rehighlight(storage, in: NSRange(location: 0, length: storage.length))
        collecting = false
    }

    /// Restyle une portion du document (étendue aux paragraphes complets).
    func rehighlight(_ storage: NSTextStorage, in requested: NSRange) {
        if !collecting {
            // Passe partielle : les marqueurs relevés ne couvriraient qu'une
            // fraction du document, le masquage serait incohérent.
            markersAreComplete = false
        }

        let ns = storage.string as NSString
        guard ns.length > 0 else { return }

        let start = min(requested.location, ns.length)
        let range = ns.paragraphRange(for: NSRange(
            location: start,
            length: min(requested.length, ns.length - start)
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
                // La ligne de délimitation (``` ou ~~~, avec son éventuel nom de
                // langage) s'efface : le fond coloré signale déjà le bloc, et la
                // ligne devenue vide lui tient lieu de marge intérieure.
                storage.addAttributes([
                    .font: Theme.mono(),
                    .foregroundColor: Theme.marker,
                    .backgroundColor: Theme.codeBlockBackground
                ], range: lineRange)
                let fence = contentRange(of: line, in: lineRange)
                hide(fence, element: fence)
                insideFence.toggle()
            } else if insideFence {
                storage.addAttributes([
                    .font: Theme.mono(),
                    .foregroundColor: Theme.codeText,
                    .backgroundColor: Theme.codeBlockBackground
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
        // L'élément d'un bloc s'arrête avant le saut de ligne : sinon, poser le
        // curseur au début de la ligne suivante révélerait les marqueurs du bloc
        // précédent — un « # » qui réapparaît quand on clique sous un titre.
        let element = contentRange(of: line, in: lineRange)
        // Zone de contenu sur laquelle on cherchera ensuite les styles en ligne.
        var inlineScope = full

        if let m = Self.headingRx.firstMatch(in: line, range: full) {
            let level = m.range(at: 1).length
            storage.addAttributes([
                .font: Theme.heading(level),
                .paragraphStyle: Theme.paragraph(spacingBefore: level <= 2 ? 16 : 12, spacingAfter: 6)
            ], range: lineRange)
            // Les dièses gardent la taille du titre mais s'effacent en couleur,
            // pour le cas où ils sont réaffichés (curseur dans le titre).
            storage.addAttribute(.foregroundColor, value: Theme.marker,
                                 range: m.range(at: 1).shifted(by: offset))
            // « # » et l'espace qui suit disparaissent : la hiérarchie est déjà
            // portée par la taille du titre.
            hide(NSRange(location: 0, length: m.range(at: 2).upperBound).shifted(by: offset),
                 element: element)
            inlineScope = m.range(at: 3)

        } else if let m = Self.quoteRx.firstMatch(in: line, range: full) {
            storage.addAttributes([
                .font: Theme.bodyItalic,
                .foregroundColor: Theme.secondary,
                .paragraphStyle: Theme.paragraph(headIndent: 22, firstLineHeadIndent: 22)
            ], range: lineRange)
            storage.addAttribute(.foregroundColor, value: Theme.accent,
                                 range: m.range(at: 1).shifted(by: offset))
            hide(m.range.shifted(by: offset), element: element)
            inlineScope = NSRange(location: m.range.length, length: full.length - m.range.length)

        } else if Self.ruleRx.firstMatch(in: line, range: full) != nil {
            // Le filet reste visible : c'est lui-même l'élément graphique.
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
            let bullet = m.range(at: 2)

            if let task = Self.taskRx.firstMatch(in: line, range: full) {
                // Case à cocher : le tiret de liste et les crochets disparaissent,
                // seule la case reste — c'est elle qui porte l'information.
                let brackets = task.range(at: 1)
                let inner = NSRange(location: brackets.location + 1, length: 1)
                let isChecked = (line as NSString).substring(with: inner).lowercased() == "x"

                storage.addAttribute(.font, value: Theme.symbol, range: inner.shifted(by: offset))
                hide(NSRange(location: bullet.location,
                             length: brackets.location - bullet.location).shifted(by: offset),
                     element: element)
                hide(NSRange(location: brackets.location, length: 1).shifted(by: offset),
                     element: element)
                hide(NSRange(location: brackets.upperBound - 1, length: 1).shifted(by: offset),
                     element: element)
                substitute(inner.shifted(by: offset),
                           with: isChecked ? Theme.checkedBox : Theme.uncheckedBox,
                           element: element)

            } else if bullet.length == 1 {
                // Une puce porte du sens : on ne la masque pas, on la dessine
                // simplement en « • » plutôt qu'en tiret. Elle n'est jamais
                // révélée, `-` et `•` désignant la même chose pour le lecteur.
                substitute(bullet.shifted(by: offset), with: Theme.bullet, element: nil)
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

        /// Applique une fonte au fragment complet, estompe les marqueurs qui
        /// l'encadrent et les enregistre comme masquables.
        func emphasise(_ regex: NSRegularExpression, font: NSFont, extraAttributes: [NSAttributedString.Key: Any] = [:]) {
            regex.enumerateMatches(in: line, range: scope) { m, _, _ in
                guard let m, isFree(m.range) else { return }
                var attrs = extraAttributes
                attrs[.font] = font
                let element = m.range.shifted(by: offset)
                storage.addAttributes(attrs, range: element)

                let markerLength = m.range(at: 1).length
                let opening = NSRange(location: element.location, length: markerLength)
                let closing = NSRange(location: element.upperBound - markerLength, length: markerLength)
                storage.addAttribute(.foregroundColor, value: Theme.marker, range: opening)
                storage.addAttribute(.foregroundColor, value: Theme.marker, range: closing)
                hide(opening, element: element)
                hide(closing, element: element)
            }
        }

        emphasise(Self.boldItalicRx, font: Theme.bodyBoldItalic)
        emphasise(Self.boldRx, font: Theme.bodyBold)
        emphasise(Self.italicRx, font: Theme.bodyItalic)
        emphasise(Self.strikeRx, font: Theme.body, extraAttributes: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: Theme.secondary
        ])

        // Liens : seul le libellé reste, souligné en couleur d'accent.
        Self.linkRx.enumerateMatches(in: line, range: scope) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            let element = m.range.shifted(by: offset)
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
            // Crochets, parenthèses, URL et titre éventuel : tout disparaît.
            for group in [1, 3, 4, 5, 6] {
                hide(m.range(at: group).shifted(by: offset), element: element)
            }
        }

        Self.autoLinkRx.enumerateMatches(in: line, range: scope) { m, _, _ in
            guard let m, isFree(m.range) else { return }
            let element = m.range.shifted(by: offset)
            storage.addAttributes([
                .foregroundColor: Theme.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: m.range(at: 2).shifted(by: offset))
            hide(m.range(at: 1).shifted(by: offset), element: element)
            hide(m.range(at: 3).shifted(by: offset), element: element)
        }

        // Enfin le code en ligne, appliqué en dernier pour rester prioritaire.
        for range in codeRanges {
            guard let m = Self.codeSpanRx.firstMatch(in: line, range: range) else { continue }
            let element = range.shifted(by: offset)
            // Pas de fond ici : la fonte monospace et le vert suffisent, et un
            // rectangle coloré au milieu d'une phrase alourdit la lecture.
            storage.addAttributes([
                .font: Theme.mono(),
                .foregroundColor: Theme.codeText
            ], range: element)
            // Les accents graves disparaissent.
            let ticks = m.range(at: 1).length
            hide(NSRange(location: element.location, length: ticks), element: element)
            hide(NSRange(location: element.upperBound - ticks, length: ticks), element: element)
        }
    }

    // MARK: - Utilitaires

    /// Attributs de base, réappliqués avant chaque passe pour effacer le style précédent.
    var baseAttributes: [NSAttributedString.Key: Any] {
        isStyled
            ? [.font: Theme.body, .foregroundColor: Theme.text, .paragraphStyle: Theme.paragraph()]
            : [.font: Theme.mono(), .foregroundColor: Theme.text, .paragraphStyle: Theme.rawParagraph]
    }

    /// Enregistre une plage de marqueurs comme masquable.
    private func hide(_ marker: NSRange, element: NSRange) {
        guard collecting, marker.length > 0 else { return }
        hiddenMarkers.append(MarkerRange(marker: marker, element: element))
    }

    /// Enregistre un caractère à redessiner sous une autre forme.
    private func substitute(_ range: NSRange, with character: Character, element: NSRange?) {
        guard collecting, range.length == 1 else { return }
        substitutions.append(GlyphSubstitution(range: range, character: character, element: element))
    }

    /// La ligne sans son saut de ligne final.
    private func contentRange(of line: String, in lineRange: NSRange) -> NSRange {
        let ns = line as NSString
        var length = ns.length
        while length > 0 {
            let character = ns.character(at: length - 1)
            guard character == 0x0A || character == 0x0D else { break }
            length -= 1
        }
        return NSRange(location: lineRange.location, length: length)
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
