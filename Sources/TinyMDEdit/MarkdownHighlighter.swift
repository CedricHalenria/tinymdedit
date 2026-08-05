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

    /// Une barre verticale de tableau à ne pas dessiner, mais à remplacer par une
    /// avance jusqu'à l'abscisse `x` — comptée depuis le bord gauche du texte.
    /// C'est ce qui aligne les colonnes sans ajouter un espace au fichier.
    /// Comme les marqueurs, l'avance cesse quand le curseur entre dans `element`.
    struct ColumnStop {
        let range: NSRange
        let x: CGFloat
        let element: NSRange
    }

    /// Le filet qui sépare l'en-tête d'un tableau de son corps. Il prend la place
    /// de la ligne `|---|---|`, masquée et réduite à une bande — mais c'est sur
    /// l'en-tête qu'il s'ancre : une ligne dont aucun glyphe n'est dessiné n'a
    /// pas de géométrie que la vue puisse interroger.
    struct TableRule {
        /// La ligne d'alignement : le filet ne se trace que si elle est masquée.
        let element: NSRange
        /// La ligne d'en-tête, sous laquelle le filet se pose.
        let header: NSRange
        let width: CGFloat
    }

    /// Marqueurs masquables relevés lors de la dernière passe complète.
    private(set) var hiddenMarkers: [MarkerRange] = []
    /// Caractères à redessiner autrement.
    private(set) var substitutions: [GlyphSubstitution] = []
    /// Barres de tableau à convertir en avance vers la colonne suivante.
    private(set) var columnStops: [ColumnStop] = []
    /// `false` quand la dernière passe était partielle : les plages relevées sont
    /// alors incomplètes et le masquage doit être désactivé.
    private(set) var markersAreComplete = false

    /// Au-delà de cette taille, on ne restyle plus tout le document à chaque frappe
    /// mais seulement les paragraphes touchés — et on renonce au masquage, qui
    /// exige une vision d'ensemble du document.
    private let fullPassLimit = 200_000

    /// Vrai pendant une passe complète, quand on relève les marqueurs.
    private var collecting = false

    /// Début de la dernière modification de caractères. Tout ce qui suit voit ses
    /// positions décalées : la vue doit y redemander la génération des glyphes.
    private(set) var lastEditLocation: Int?

    /// Position du curseur, que la vue tient à jour. Une ligne de délimitation de
    /// bloc de code est réduite à une bande fine tant qu'elle est masquée, et
    /// reprend sa hauteur normale quand le curseur s'y pose — sans quoi le texte
    /// révélé serait tronqué.
    var caretLocation: Int = -1

    /// Lignes de délimitation des blocs de code relevées à la dernière passe.
    private(set) var fenceLines: [NSRange] = []

    /// Filets d'en-tête de tableau, que la vue trace dans la bande laissée par la
    /// ligne d'alignement.
    private(set) var tableRules: [TableRule] = []

    /// Largeur réellement offerte au texte, que la vue tient à jour. Les tableaux
    /// sont seuls à en dépendre : c'est elle qui décide si leurs colonnes tiennent.
    /// La valeur de départ est une estimation prudente, le temps que la vue soit
    /// disposée.
    private(set) var contentWidth: CGFloat = Theme.maxContentWidth - Theme.textInset.width

    /// Vrai si la dernière passe complète a rencontré au moins un tableau. Sans
    /// tableau, redimensionner la fenêtre ne change rien à la mise en page.
    private(set) var hasTable = false

    /// Enregistre la largeur offerte au texte. Renvoie `true` s'il faut restyler,
    /// c'est-à-dire si la largeur a changé et que le document contient un tableau.
    func setContentWidth(_ width: CGFloat) -> Bool {
        guard width > 0, abs(width - contentWidth) > 0.5 else { return false }
        contentWidth = width
        return hasTable
    }

    /// Caractères portant une case à cocher — celui entre les crochets d'un
    /// `[ ]` ou `[x]`. La vue s'en sert pour rendre les cases cliquables.
    private(set) var checkboxes: [NSRange] = []

    /// Citations, lignes consécutives fusionnées en un seul bloc : la vue y trace
    /// une barre verticale continue plutôt qu'un trait par ligne.
    private(set) var quoteBlocks: [NSRange] = []

    /// Le curseur est-il posé sur une ligne réduite à une bande — délimitation de
    /// bloc de code ou ligne d'alignement d'un tableau ? Y entrer lui rend sa
    /// hauteur, sans quoi le texte révélé serait tronqué.
    func isOnCollapsedLine(_ location: Int) -> Bool {
        let lines = fenceLines + tableRules.map(\.element)
        return lines.contains { location >= $0.location && location <= $0.upperBound }
    }

    // MARK: - Expressions régulières

    private static func rx(
        _ pattern: String,
        _ options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        // Les motifs sont des constantes littérales : un échec ici est un bug de
        // développement, pas une erreur d'exécution possible.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Les emphases traversent les retours à la ligne : en Markdown, un simple
    /// saut de ligne au milieu d'un paragraphe est une coupure douce, et
    /// `**deux\nlignes**` est bien du gras.
    private static let acrossLines: NSRegularExpression.Options = [.dotMatchesLineSeparators]

    // Blocs (appliqués ligne par ligne)
    private static let headingRx = rx(#"^(#{1,6})([ \t]+)(.*)$"#)
    private static let fenceRx = rx(#"^[ \t]{0,3}(`{3,}|~{3,})[ \t]*([A-Za-z0-9_+#.-]*)"#)
    private static let quoteRx = rx(#"^[ \t]{0,3}(>+)([ \t]?)"#)
    private static let listRx = rx(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)"#)
    private static let ruleRx = rx(#"^[ \t]{0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})[ \t]*$"#)
    private static let taskRx = rx(#"^[ \t]*[-*+][ \t]+(\[[ xX]\])"#)
    /// Une ligne déjà prise par un autre bloc n'ouvre jamais un tableau, quelles
    /// que soient les barres verticales qu'elle contient.
    private static let notATableRx = rx(#"^[ \t]{0,3}(#{1,6}[ \t]|>|([-*+]|\d{1,9}[.)])[ \t])"#)

    // Fragments en ligne
    private static let codeSpanRx = rx(#"(`+)([^`\n]|[^`\n].*?[^`\n])\1"#)
    private static let boldItalicRx = rx(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#, acrossLines)
    private static let boldRx = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, acrossLines)
    private static let italicRx = rx(#"(?<![*_\w\\])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])"#, acrossLines)
    private static let strikeRx = rx(#"(~~)(?=\S)(.+?)(?<=\S)\1"#, acrossLines)
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
        lastEditLocation = editedRange.location

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
        columnStops.removeAll(keepingCapacity: true)
        fenceLines.removeAll(keepingCapacity: true)
        tableRules.removeAll(keepingCapacity: true)
        checkboxes.removeAll(keepingCapacity: true)
        quoteBlocks.removeAll(keepingCapacity: true)
        hasTable = false
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
        //    ouvert plus haut dans le document, et dans quel langage.
        var (insideFence, language) = openFence(before: range.location, in: ns)
        var inBlockComment = false

        // 3. Puis on style ligne par ligne. Les styles en ligne, eux, ne sont pas
        //    appliqués tout de suite : on accumule le contenu des lignes d'un même
        //    paragraphe pour que gras, italique et liens puissent traverser les
        //    retours à la ligne.
        var pendingInline: NSRange?

        func flushInline() {
            defer { pendingInline = nil }
            guard let scope = pendingInline, scope.length > 0 else { return }
            styleInline(storage, text: ns.substring(with: scope), offset: scope.location)
        }

        var cursor = range.location
        while cursor < NSMaxRange(range) {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let line = ns.substring(with: lineRange)

            // Un tableau se traite d'un bloc : la largeur de ses colonnes se lit
            // sur toutes ses lignes à la fois, jamais sur une seule.
            if !insideFence, line.contains("|"),
               Self.notATableRx.firstMatch(in: line, range: line.fullRange) == nil,
               let table = MarkdownTable.detect(in: ns, from: lineRange, limit: NSMaxRange(range)) {
                flushInline()
                styleTable(storage, ns, table)
                cursor = table.end
                continue
            }

            if let fenceMatch = Self.fenceRx.firstMatch(in: line, range: line.fullRange) {
                flushInline()
                // La ligne de délimitation (``` ou ~~~, avec son éventuel nom de
                // langage) s'efface, et sa hauteur est réduite à une bande fine :
                // le fond coloré signale déjà le bloc, la bande lui tient lieu de
                // marge intérieure. Le curseur posé dessus la rouvre à sa taille
                // normale, pour pouvoir changer le langage.
                let fence = contentRange(of: line, in: lineRange)
                let hasCaret = caretLocation >= fence.location && caretLocation <= fence.upperBound
                let closing = insideFence
                storage.addAttributes([
                    .font: Theme.mono(),
                    .foregroundColor: Theme.marker,
                    .backgroundColor: Theme.codeBlockBackground,
                    .paragraphStyle: hasCaret
                        ? Theme.codeParagraph
                        : Theme.collapsedFenceParagraph(spacingAfter: closing ? 10 : 0)
                ], range: lineRange)
                hide(fence, element: fence)
                if collecting { fenceLines.append(fence) }
                // Le mot qui suit les accents graves choisit le jeu de règles de
                // coloration ; la ligne de fermeture, elle, referme le bloc.
                language = insideFence
                    ? .unknown
                    : CodeLanguage(tag: (line as NSString).substring(with: fenceMatch.range(at: 2)))
                inBlockComment = false
                insideFence.toggle()
            } else if insideFence {
                flushInline()
                storage.addAttributes([
                    .font: Theme.mono(),
                    .foregroundColor: Theme.codeText,
                    .backgroundColor: Theme.codeBlockBackground,
                    .paragraphStyle: Theme.codeParagraph
                ], range: lineRange)
                CodeHighlighter.style(storage, line: line, lineRange: lineRange,
                                      language: language, inBlockComment: &inBlockComment)
            } else {
                let block = styleBlock(storage, line: line, lineRange: lineRange)
                switch block.kind {
                case .blank:
                    // Une ligne vide ferme le paragraphe : aucune emphase ne la traverse.
                    flushInline()

                case .heading, .rule:
                    // Toujours seuls sur leur ligne : ils n'ouvrent aucun paragraphe.
                    flushInline()
                    if block.scope.length > 0 {
                        styleInline(storage, text: ns.substring(with: block.scope),
                                    offset: block.scope.location)
                    }

                case .quote, .list:
                    // Ouvrent un paragraphe que les lignes suivantes prolongent.
                    flushInline()
                    pendingInline = block.scope

                case .plain:
                    if let pending = pendingInline, pending.upperBound == block.scope.location {
                        pendingInline = NSUnionRange(pending, block.scope)
                    } else {
                        flushInline()
                        pendingInline = block.scope
                    }
                }
            }

            cursor = NSMaxRange(lineRange)
            if lineRange.length == 0 { break } // sécurité anti-boucle infinie
        }

        flushInline()
    }

    // MARK: - Blocs

    /// Nature d'une ligne, qui décide si elle prolonge le paragraphe en cours.
    enum BlockKind {
        case plain, heading, quote, list, rule, blank
    }

    /// Style une ligne hors bloc de code : titre, citation, liste, filet ou
    /// paragraphe. Renvoie sa nature et la portée sur laquelle l'appelant devra
    /// appliquer les styles en ligne — hors marqueur de bloc, en coordonnées du
    /// document.
    @discardableResult
    private func styleBlock(
        _ storage: NSTextStorage,
        line: String,
        lineRange: NSRange
    ) -> (kind: BlockKind, scope: NSRange) {
        let full = line.fullRange
        let offset = lineRange.location
        // L'élément d'un bloc s'arrête avant le saut de ligne : sinon, poser le
        // curseur au début de la ligne suivante révélerait les marqueurs du bloc
        // précédent — un « # » qui réapparaît quand on clique sous un titre.
        let element = contentRange(of: line, in: lineRange)
        // Zone de contenu sur laquelle l'appelant cherchera les styles en ligne.
        var inlineScope = full
        var kind = BlockKind.plain

        if element.length == 0 {
            // Ligne vide : elle ferme le paragraphe en cours.
            return (.blank, NSRange(location: lineRange.location, length: 0))
        }

        if let m = Self.headingRx.firstMatch(in: line, range: full) {
            kind = .heading
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
            kind = .quote
            storage.addAttributes([
                .font: Theme.bodyItalic,
                .foregroundColor: Theme.secondary,
                .paragraphStyle: Theme.paragraph(headIndent: Theme.quoteIndent,
                                                 firstLineHeadIndent: Theme.quoteIndent,
                                                 spacingAfter: 4)
            ], range: lineRange)
            storage.addAttribute(.foregroundColor, value: Theme.accent,
                                 range: m.range(at: 1).shifted(by: offset))
            hide(m.range.shifted(by: offset), element: element)
            appendQuote(lineRange)
            inlineScope = NSRange(location: m.range.length, length: full.length - m.range.length)

        } else if Self.ruleRx.firstMatch(in: line, range: full) != nil {
            kind = .rule
            // Le filet reste visible : c'est lui-même l'élément graphique.
            storage.addAttributes([
                .foregroundColor: Theme.marker,
                .paragraphStyle: Theme.paragraph(spacingBefore: 8)
            ], range: lineRange)
            inlineScope = NSRange(location: 0, length: 0)

        } else if let m = Self.listRx.firstMatch(in: line, range: full) {
            kind = .list
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
                if collecting { checkboxes.append(inner.shifted(by: offset)) }

            } else if bullet.length == 1 {
                // Une puce porte du sens : on ne la masque pas, on la dessine
                // simplement en « • » plutôt qu'en tiret. Elle n'est jamais
                // révélée, `-` et `•` désignant la même chose pour le lecteur.
                substitute(bullet.shifted(by: offset), with: Theme.bullet, element: nil)
            }
            inlineScope = NSRange(location: m.range.length, length: full.length - m.range.length)
        }

        return (kind, inlineScope.shifted(by: offset))
    }

    // MARK: - Tableaux

    /// Ce que devient un tableau à l'écran.
    ///
    /// Les colonnes alignées supposent que le tableau tienne dans la colonne de
    /// lecture : le texte est **un flux unique**, une cellule ne peut donc pas se
    /// replier dans sa colonne pendant que la suivante l'attend à droite. Quand
    /// plus rien ne tient, on renonce à la grille plutôt que de laisser les
    /// rangées se disloquer.
    private enum TableLayout {
        /// Colonnes alignées, à la taille du corps de texte (`scale` valant 1) ou
        /// à une taille réduite quand c'est le seul moyen de tenir.
        case columns(scale: CGFloat)
        /// Trop large même réduit : les rangées se replient comme du texte
        /// ordinaire, et les barres deviennent de simples séparateurs.
        case wrapped
    }

    /// Style un tableau entier : en-tête en gras, rangées jointives, ligne
    /// d'alignement réduite à un filet — et, quand la place le permet, colonnes
    /// alignées.
    ///
    /// L'alignement ne doit rien à des espaces ajoutés au fichier : on mesure la
    /// largeur réelle de chaque cellule une fois stylée, on en déduit l'abscisse
    /// de chaque colonne, et chaque barre verticale devient une avance jusque-là.
    private func styleTable(_ storage: NSTextStorage, _ ns: NSString, _ table: MarkdownTable) {
        // Les marqueurs relevés à partir d'ici sont ceux du tableau : eux seuls
        // comptent quand on mesure la largeur rendue d'une cellule.
        let markerFloor = hiddenMarkers.count
        if collecting { hasTable = true }

        // 1. Les rangées : fonte, puis styles en ligne cellule par cellule — une
        //    emphase ne traverse jamais une barre verticale. La géométrie, elle,
        //    attend de savoir si les colonnes tiennent.
        for (index, row) in table.rows.enumerated() {
            storage.addAttribute(.font, value: index == 0 ? Theme.bodyBold : Theme.body,
                                 range: row.line)
            for bar in row.bars {
                storage.addAttribute(.foregroundColor, value: Theme.marker, range: bar)
            }
            for cell in row.cells where cell.content.length > 0 {
                styleInline(storage, text: ns.substring(with: cell.content),
                            offset: cell.content.location)
            }
        }

        // 2. La ligne d'alignement : de la syntaxe pure, jamais du contenu. Elle
        //    s'efface et se réduit à une bande où la vue trace le filet ; le
        //    curseur posé dessus lui rend sa hauteur pour rester éditable.
        let delimiter = table.delimiter
        let hasCaret = caretLocation >= delimiter.element.location
            && caretLocation <= delimiter.element.upperBound
        storage.addAttributes([
            .foregroundColor: Theme.marker,
            .paragraphStyle: hasCaret
                ? Theme.tableParagraph()
                : Theme.collapsedParagraph(height: Theme.tableRuleHeight)
        ], range: delimiter.line)
        hide(delimiter.element, element: delimiter.element)

        // 3. Les mesures, puis la mise en page. Elles n'ont de sens qu'en passe
        //    complète : le masquage est de toute façon désactivé autrement.
        let columns = table.columnCount
        guard collecting, columns > 0 else {
            styleTableRows(storage, table, layout: .columns(scale: 1))
            return
        }

        let (layout, widths, cellWidths) = fit(storage, table, markersFrom: markerFloor)
        styleTableRows(storage, table, layout: layout)

        switch layout {
        case .columns(let scale):
            if scale != 1 {
                scaleFonts(storage, in: NSRange(location: table.header.line.location,
                                                length: table.end - table.header.line.location),
                           by: scale)
            }
            alignColumns(table, widths: widths, cellWidths: cellWidths)
        case .wrapped:
            wrapRows(table)
        }
    }

    /// Cherche la mise en page qui tient dans la colonne de lecture : d'abord à
    /// taille normale, puis en réduisant la fonte du tableau — et, si même le
    /// plancher ne suffit pas, en renonçant aux colonnes.
    ///
    /// La largeur rendue ne suit pas *exactement* la taille de la fonte : on
    /// remesure à chaque essai plutôt que de faire confiance à une règle de trois.
    private func fit(
        _ storage: NSTextStorage,
        _ table: MarkdownTable,
        markersFrom floor: Int
    ) -> (layout: TableLayout, widths: [CGFloat], cellWidths: [[CGFloat]]) {
        // Place qui reste aux colonnes une fois prises les gouttières minimales.
        let room = contentWidth - Theme.tableMinGutter * CGFloat(table.columnCount - 1)
        let floorScale = Theme.tableMinFontSize / Theme.bodySize

        var scale: CGFloat = 1
        var (widths, cellWidths) = measure(storage, table, markersFrom: floor, scale: scale)
        var total = widths.reduce(0, +)

        // La règle de trois vise un cheveu en deçà de la place disponible : viser
        // la limite exacte ferait osciller la correction sans jamais passer
        // dessous. Deux tours suffisent en pratique, la boucle s'arrête d'ailleurs
        // dès qu'elle n'a plus rien à gagner.
        var attempts = 0
        while total > room, room > 0, total > 0, attempts < 4 {
            attempts += 1
            let next = max(floorScale, scale * (room - 1) / total)
            guard next < scale else { break }   // au plancher : inutile d'insister
            scale = next
            (widths, cellWidths) = measure(storage, table, markersFrom: floor, scale: scale)
            total = widths.reduce(0, +)
        }

        // Toujours trop large : la grille est perdue d'avance, on replie.
        return (total <= room ? .columns(scale: scale) : .wrapped, widths, cellWidths)
    }

    /// Largeur rendue de chaque cellule, et largeur de chaque colonne — celle de
    /// sa cellule la plus large.
    private func measure(
        _ storage: NSTextStorage,
        _ table: MarkdownTable,
        markersFrom floor: Int,
        scale: CGFloat
    ) -> (widths: [CGFloat], cellWidths: [[CGFloat]]) {
        var widths = [CGFloat](repeating: 0, count: table.columnCount)
        var cellWidths: [[CGFloat]] = []
        for row in table.rows {
            var measured: [CGFloat] = []
            for (column, cell) in row.cells.enumerated() {
                let width = renderedWidth(storage, cell.content, markersFrom: floor, scale: scale)
                measured.append(width)
                if column < widths.count { widths[column] = max(widths[column], width) }
            }
            cellWidths.append(measured)
        }
        return (widths, cellWidths)
    }

    /// Géométrie des rangées : jointives en colonnes, aérées et retraitées quand
    /// le tableau est replié — une rangée y occupe alors plusieurs lignes.
    private func styleTableRows(_ storage: NSTextStorage, _ table: MarkdownTable, layout: TableLayout) {
        let isWrapped: Bool
        if case .wrapped = layout { isWrapped = true } else { isWrapped = false }

        for (index, row) in table.rows.enumerated() {
            let isLast = row.line.upperBound >= table.end
            storage.addAttribute(.paragraphStyle, value: Theme.tableParagraph(
                spacingBefore: index == 0 ? 6 : 0,
                spacingAfter: isLast ? 12 : (isWrapped ? 6 : 0),
                headIndent: isWrapped ? Theme.tableWrappedIndent : 0
            ), range: row.line)
        }
    }

    /// Chaque barre verticale devient une avance jusqu'au début de sa colonne, et
    /// les espaces de remplissage du fichier disparaissent : c'est l'avance qui
    /// place le texte, au point près.
    private func alignColumns(_ table: MarkdownTable, widths: [CGFloat], cellWidths: [[CGFloat]]) {
        let columns = table.columnCount

        // La gouttière prend ce qui reste, sans dépasser sa valeur nominale ni
        // descendre sous le minimum — `fit` a garanti que ce minimum tient.
        var gutter = Theme.tableGutter
        if columns > 1 {
            let free = contentWidth - widths.reduce(0, +)
            gutter = min(gutter, max(Theme.tableMinGutter, free / CGFloat(columns - 1)))
        }

        var starts = [CGFloat](repeating: 0, count: columns)
        for column in 1 ..< max(columns, 1) {
            starts[column] = starts[column - 1] + widths[column - 1] + gutter
        }

        for (index, row) in table.rows.enumerated() {
            for (column, cell) in row.cells.enumerated() where column < columns {
                // Le contenu se pose à gauche, au centre ou à droite de sa
                // colonne, selon ce qu'en dit la ligne d'alignement.
                let slack = max(0, widths[column] - cellWidths[index][column])
                let target: CGFloat
                switch table.alignments[column] {
                case .leading: target = starts[column]
                case .center: target = starts[column] + slack / 2
                case .trailing: target = starts[column] + slack
                }

                // La barre qui ouvre la cellule porte l'avance ; celle du bord
                // gauche n'a le plus souvent rien à rattraper et disparaît.
                if let bar = row.bar(before: column) {
                    if target > 0.5 {
                        stop(bar, at: target, element: row.element)
                    } else {
                        hide(bar, element: row.element)
                    }
                }
                hide(NSRange(location: cell.range.location,
                             length: cell.content.location - cell.range.location),
                     element: row.element)
                hide(NSRange(location: cell.content.upperBound,
                             length: cell.range.upperBound - cell.content.upperBound),
                     element: row.element)
            }
            if let trailing = row.trailingBar, row.cells.count <= columns {
                hide(trailing, element: row.element)
            }
        }

        tableRules.append(TableRule(
            element: table.delimiter.element,
            header: table.header.element,
            width: starts[columns - 1] + widths[columns - 1]
        ))
    }

    /// Tableau replié. Aucune avance : la rangée se replie comme un paragraphe
    /// ordinaire, à la taille de lecture, et ses lignes suivantes sont retirées.
    ///
    /// Les barres deviennent de fins séparateurs — sans elles on ne verrait plus
    /// où une cellule finit. Celle de tête reste : elle marque le début de chaque
    /// rangée, que le retrait détache du reste. Celle de queue s'efface, elle ne
    /// séparerait plus rien. Le remplissage, lui, se réduit à une espace : le
    /// texte ne doit pas se retrouver troué au milieu d'une ligne.
    private func wrapRows(_ table: MarkdownTable) {
        for row in table.rows {
            for bar in (row.leadingBar.map { [$0] } ?? []) + row.innerBars {
                substitute(bar, with: Theme.tableSeparator, element: row.element)
            }
            if let trailing = row.trailingBar { hide(trailing, element: row.element) }

            for (column, cell) in row.cells.enumerated() {
                // Une espace de chaque côté d'un séparateur suffit ; le reste du
                // remplissage disparaît. En fin de rangée, la barre effacée ne
                // laisse rien à séparer.
                let keepBefore = row.bar(before: column) != nil ? 1 : 0
                let keepAfter = column < row.cells.count - 1 ? 1 : 0
                let before = cell.content.location - cell.range.location
                let after = cell.range.upperBound - cell.content.upperBound
                hide(NSRange(location: cell.range.location + keepBefore,
                             length: max(0, before - keepBefore)),
                     element: row.element)
                hide(NSRange(location: cell.content.upperBound,
                             length: max(0, after - keepAfter)),
                     element: row.element)
            }
        }

        // Le filet court sur toute la colonne de lecture : replié, le tableau n'a
        // plus de largeur propre.
        tableRules.append(TableRule(
            element: table.delimiter.element,
            header: table.header.element,
            width: contentWidth
        ))
    }

    /// Multiplie la taille de chaque fonte d'une plage, traits conservés : c'est
    /// ainsi qu'un tableau trop large se réduit sans perdre ses gras ni son code.
    private func scaleFonts(_ text: NSMutableAttributedString, in range: NSRange, by scale: CGFloat) {
        guard scale != 1, range.length > 0 else { return }
        text.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let resized = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale)
            text.addAttribute(.font, value: resized ?? font, range: subrange)
        }
    }

    /// Largeur qu'occupera réellement une cellule à l'écran : son texte stylé,
    /// privé des marqueurs que l'affichage masquera. La mesure ignore la position
    /// du curseur — une ligne révélée ne doit pas faire bouger tout le tableau.
    ///
    /// `scale` permet de mesurer ce que donnerait le tableau réduit, sans avoir à
    /// toucher au document pour l'essayer.
    private func renderedWidth(
        _ storage: NSTextStorage,
        _ range: NSRange,
        markersFrom floor: Int,
        scale: CGFloat = 1
    ) -> CGFloat {
        guard range.length > 0 else { return 0 }
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        // De la fin vers le début : retirer un marqueur ne doit pas décaler les
        // positions de ceux qui restent à retirer.
        let markers = hiddenMarkers[floor...]
            .filter { NSIntersectionRange($0.marker, range).length > 0 }
            .sorted { $0.marker.location > $1.marker.location }
        for marker in markers {
            let common = NSIntersectionRange(marker.marker, range)
            text.deleteCharacters(in: NSRange(location: common.location - range.location,
                                              length: common.length))
        }
        scaleFonts(text, in: NSRange(location: 0, length: text.length), by: scale)
        return ceil(text.size().width)
    }

    // MARK: - Fragments en ligne

    /// `text` peut couvrir plusieurs lignes : c'est ce qui permet à une emphase
    /// de traverser un retour à la ligne au sein d'un même paragraphe.
    private func styleInline(_ storage: NSTextStorage, text line: String, offset: Int) {
        let scope = line.fullRange
        // Le code en ligne est prioritaire : son contenu ne doit pas être
        // réinterprété comme du gras ou de l'italique.
        var codeRanges: [NSRange] = []
        Self.codeSpanRx.enumerateMatches(in: line, range: scope) { m, _, _ in
            guard let m else { return }
            codeRanges.append(m.range)
        }

        /// Un délimiteur situé à l'intérieur d'un fragment de code n'en est pas
        /// un : `` `a**b` `` ne contient pas de gras. On ne teste que les
        /// délimiteurs, jamais le contenu — une emphase a parfaitement le droit
        /// d'englober un fragment de code.
        func isFree(_ range: NSRange) -> Bool {
            !codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        /// Applique une fonte au fragment complet, estompe les marqueurs qui
        /// l'encadrent et les enregistre comme masquables.
        func emphasise(_ regex: NSRegularExpression, font: NSFont, extraAttributes: [NSAttributedString.Key: Any] = [:]) {
            regex.enumerateMatches(in: line, range: scope) { m, _, _ in
                guard let m else { return }
                let markerLength = m.range(at: 1).length
                let localOpening = NSRange(location: m.range.location, length: markerLength)
                let localClosing = NSRange(location: m.range.upperBound - markerLength,
                                           length: markerLength)
                guard isFree(localOpening), isFree(localClosing) else { return }

                var attrs = extraAttributes
                attrs[.font] = font
                let element = m.range.shifted(by: offset)
                storage.addAttributes(attrs, range: element)

                let opening = localOpening.shifted(by: offset)
                let closing = localClosing.shifted(by: offset)
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
            guard let m, isFree(m.range(at: 1)), isFree(m.range(at: 3)) else { return }
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
            guard let m, isFree(m.range(at: 1)), isFree(m.range(at: 3)) else { return }
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

    /// Ajoute une ligne de citation, en la fusionnant avec le bloc précédent si
    /// elle le prolonge — la barre verticale doit être continue.
    private func appendQuote(_ lineRange: NSRange) {
        guard collecting else { return }
        if let last = quoteBlocks.last, last.upperBound == lineRange.location {
            quoteBlocks[quoteBlocks.count - 1] = NSUnionRange(last, lineRange)
        } else {
            quoteBlocks.append(lineRange)
        }
    }

    /// Enregistre une barre verticale à remplacer par une avance jusqu'à `x`.
    private func stop(_ bar: NSRange, at x: CGFloat, element: NSRange) {
        guard collecting, bar.length == 1 else { return }
        columnStops.append(ColumnStop(range: bar, x: x, element: element))
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

    /// Détermine si un bloc de code est ouvert juste avant `location` — et dans
    /// quel langage — en comptant les délimiteurs rencontrés depuis le début du
    /// document. Utile quand on ne restyle qu'une portion d'un très gros fichier.
    private func openFence(before location: Int, in ns: NSString) -> (Bool, CodeLanguage) {
        guard location > 0 else { return (false, .unknown) }
        var open = false
        var language = CodeLanguage.unknown
        var cursor = 0
        while cursor < location {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let line = ns.substring(with: lineRange)
            if let match = Self.fenceRx.firstMatch(in: line, range: line.fullRange) {
                language = open
                    ? .unknown
                    : CodeLanguage(tag: (line as NSString).substring(with: match.range(at: 2)))
                open.toggle()
            }
            cursor = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        return (open, language)
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
