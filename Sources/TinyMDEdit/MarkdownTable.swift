import Foundation

/// Analyse d'un tableau Markdown (syntaxe GitHub) : découpe des lignes en
/// cellules et lecture de la ligne d'alignement.
///
/// Ce type ne fait que **lire** le texte. Le rendu appartient au styleur : les
/// barres verticales n'y sont pas simplement masquées comme les autres
/// marqueurs, elles sont converties en une avance jusqu'au début de la colonne
/// suivante. C'est ce qui aligne les colonnes sans ajouter un seul espace au
/// fichier.
struct MarkdownTable {

    enum Alignment { case leading, center, trailing }

    struct Cell {
        /// La cellule entière, espaces de remplissage compris.
        let range: NSRange
        /// Son contenu utile, débarrassé des espaces qui l'entourent.
        let content: NSRange
    }

    struct Row {
        /// La ligne entière, saut de ligne compris.
        let line: NSRange
        /// La ligne sans son saut de ligne — l'élément que le curseur révèle.
        let element: NSRange
        /// Barre de tête, quand la ligne en a une.
        let leadingBar: NSRange?
        /// Barres intérieures : une avant chaque cellule sauf la première.
        let innerBars: [NSRange]
        /// Barre de queue, quand la ligne en a une.
        let trailingBar: NSRange?
        let cells: [Cell]

        var bars: [NSRange] {
            (leadingBar.map { [$0] } ?? []) + innerBars + (trailingBar.map { [$0] } ?? [])
        }

        /// La barre qui précède la cellule d'indice `column`, s'il y en a une.
        func bar(before column: Int) -> NSRange? {
            if column == 0 { return leadingBar }
            let index = column - 1
            return index < innerBars.count ? innerBars[index] : nil
        }
    }

    let header: Row
    /// La ligne `|---|:--:|` : de la syntaxe pure, jamais du contenu.
    let delimiter: Row
    let body: [Row]
    let alignments: [Alignment]

    /// L'en-tête et le corps — tout ce qui porte du texte.
    var rows: [Row] { [header] + body }
    var columnCount: Int { alignments.count }
    /// Position du document où le tableau s'achève.
    var end: Int { (body.last ?? delimiter).line.upperBound }

    // MARK: - Détection

    /// Reconnaît un tableau dont l'en-tête est la ligne `headerLine`. Un tableau
    /// se signale par sa deuxième ligne : elle ne contient que des tirets, des
    /// deux-points et des barres, et compte exactement autant de cellules que
    /// l'en-tête. Sans elle, une ligne pleine de `|` reste du texte ordinaire.
    ///
    /// `limit` borne la lecture : lors d'une passe partielle, on ne style jamais
    /// au-delà de la zone demandée.
    static func detect(in ns: NSString, from headerLine: NSRange, limit: Int) -> MarkdownTable? {
        guard headerLine.upperBound < limit, let header = row(in: ns, at: headerLine) else { return nil }

        let delimiterLine = ns.lineRange(for: NSRange(location: headerLine.upperBound, length: 0))
        guard delimiterLine.upperBound <= limit,
              let delimiter = row(in: ns, at: delimiterLine),
              delimiter.cells.count == header.cells.count,
              let alignments = alignments(of: delimiter, in: ns) else { return nil }

        // Le corps court jusqu'à la première ligne qui ne contient plus de barre
        // — ligne vide comprise, qui referme le tableau.
        var body: [Row] = []
        var cursor = delimiterLine.upperBound
        while cursor < limit {
            let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
            guard line.length > 0, line.upperBound <= limit,
                  let row = row(in: ns, at: line) else { break }
            body.append(row)
            cursor = line.upperBound
        }

        return MarkdownTable(header: header, delimiter: delimiter, body: body, alignments: alignments)
    }

    /// Découpe une ligne sur ses barres verticales. Renvoie `nil` si la ligne
    /// n'en contient aucune : ce n'est alors pas une ligne de tableau.
    static func row(in ns: NSString, at line: NSRange) -> Row? {
        let element = content(of: line, in: ns)
        guard element.length > 0 else { return nil }

        var bars: [Int] = []
        var index = element.location
        while index < element.upperBound {
            switch ns.character(at: index) {
            case 0x5C: index += 1        // « \ » : la barre qui suit est échappée, elle reste du texte
            case 0x7C: bars.append(index)
            default: break
            }
            index += 1
        }
        guard !bars.isEmpty else { return nil }

        func isBlank(_ from: Int, _ to: Int) -> Bool {
            for i in from ..< to where ns.character(at: i) != 0x20 && ns.character(at: i) != 0x09 {
                return false
            }
            return true
        }

        // Les barres de tête et de queue n'ouvrent pas de cellule : elles ne font
        // que dessiner le bord du tableau, et le Markdown les rend facultatives.
        var first = 0
        var last = bars.count - 1
        var leadingBar: NSRange?
        var trailingBar: NSRange?

        if isBlank(element.location, bars[0]) {
            leadingBar = NSRange(location: bars[0], length: 1)
            first = 1
        }
        if last >= first, isBlank(bars[last] + 1, element.upperBound) {
            trailingBar = NSRange(location: bars[last], length: 1)
            last -= 1
        }

        let innerBars = first <= last
            ? bars[first ... last].map { NSRange(location: $0, length: 1) }
            : []

        var cells: [Cell] = []
        var start = leadingBar?.upperBound ?? element.location
        for bar in innerBars {
            cells.append(cell(in: ns, from: start, to: bar.location))
            start = bar.upperBound
        }
        cells.append(cell(in: ns, from: start, to: trailingBar?.location ?? element.upperBound))

        return Row(line: line, element: element, leadingBar: leadingBar,
                   innerBars: innerBars, trailingBar: trailingBar, cells: cells)
    }

    // MARK: - Utilitaires

    /// Une cellule ne contient que du texte : `:---:` mis à part, ce qui l'entoure
    /// est du remplissage, que l'affichage remplace par un alignement calculé.
    private static let delimiterCellRx = try! NSRegularExpression(pattern: #"^:?-+:?$"#)

    private static func alignments(of row: Row, in ns: NSString) -> [Alignment]? {
        var result: [Alignment] = []
        for cell in row.cells {
            guard cell.content.length > 0 else { return nil }
            let text = ns.substring(with: cell.content)
            guard delimiterCellRx.firstMatch(in: text, range: text.fullRange) != nil else { return nil }
            let left = text.hasPrefix(":")
            let right = text.hasSuffix(":")
            result.append(left && right ? .center : (right ? .trailing : .leading))
        }
        return result
    }

    private static func cell(in ns: NSString, from: Int, to: Int) -> Cell {
        var start = from
        var end = to
        while start < end, ns.character(at: start) == 0x20 || ns.character(at: start) == 0x09 {
            start += 1
        }
        while end > start, ns.character(at: end - 1) == 0x20 || ns.character(at: end - 1) == 0x09 {
            end -= 1
        }
        return Cell(range: NSRange(location: from, length: to - from),
                    content: NSRange(location: start, length: end - start))
    }

    /// La ligne sans son saut de ligne final.
    private static func content(of line: NSRange, in ns: NSString) -> NSRange {
        var end = line.upperBound
        while end > line.location {
            let character = ns.character(at: end - 1)
            guard character == 0x0A || character == 0x0D else { break }
            end -= 1
        }
        return NSRange(location: line.location, length: end - line.location)
    }
}
