import AppKit

/// Fontes, couleurs et métriques de l'éditeur.
/// Tout est centralisé ici pour pouvoir ajuster le rendu en un seul endroit.
enum Theme {

    // MARK: - Tailles

    static let bodySize: CGFloat = 15
    static let monoSize: CGFloat = 13.5

    /// Marges intérieures de la zone de texte (style TextEdit, respirant).
    static let textInset = NSSize(width: 28, height: 22)

    // MARK: - Fontes

    static var body: NSFont {
        .systemFont(ofSize: bodySize)
    }

    static var bodyBold: NSFont {
        .systemFont(ofSize: bodySize, weight: .semibold)
    }

    static var bodyItalic: NSFont {
        NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
    }

    static var bodyBoldItalic: NSFont {
        NSFontManager.shared.convert(bodyBold, toHaveTrait: .italicFontMask)
    }

    static func mono(size: CGFloat = monoSize) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// La fonte système ne contient pas ☐ (U+2610). Apple Symbols, si — et avec
    /// ☑ à la même largeur, ce qui garantit que cocher une case ne décale rien.
    private static let symbolFont = NSFont(name: "Apple Symbols", size: bodySize)

    /// Fonte à appliquer au caractère qui porte une case à cocher.
    static var symbol: NSFont { symbolFont ?? body }

    /// Case vide — repli sur le carré générique si Apple Symbols manquait.
    static var uncheckedBox: Character { symbolFont != nil ? "☐" : "□" }
    static let checkedBox: Character = "☑"
    /// Puce des listes à puces.
    static let bullet: Character = "•"

    /// Taille des titres `#` à `######`.
    static func heading(_ level: Int) -> NSFont {
        let sizes: [CGFloat] = [27, 23, 20, 18, 16, 15]
        let clamped = min(max(level, 1), 6)
        return .systemFont(ofSize: sizes[clamped - 1], weight: .bold)
    }

    // MARK: - Couleurs

    /// Couleur du texte courant.
    static let text = NSColor.textColor
    /// Couleur des marqueurs Markdown (`##`, `**`, `-`, …) : présents mais discrets.
    static let marker = NSColor.tertiaryLabelColor
    /// Texte secondaire (citations, URL des liens).
    static let secondary = NSColor.secondaryLabelColor
    /// Couleur d'accent du système, pour les liens et les puces.
    static let accent = NSColor.controlAccentColor
    /// Fond des blocs de code délimités par ``` — utile pour marquer l'étendue
    /// d'une zone multi-lignes. Le code *en ligne*, lui, n'a pas de fond : la
    /// fonte monospace et la couleur suffisent à le distinguer.
    static let codeBlockBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)

    /// Texte du code : vert terminal, décliné pour rester lisible sur fond clair
    /// comme sur fond sombre.
    static let codeText = NSColor(name: "codeText") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.24, green: 0.83, blue: 0.32, alpha: 1)
            : NSColor(srgbRed: 0.06, green: 0.45, blue: 0.13, alpha: 1)
    }

    // MARK: - Paragraphes

    /// Style de paragraphe de base (mode mise en page).
    static func paragraph(
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 8
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.25
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        return style
    }

    /// Style de paragraphe du mode texte brut : compact, sans fioriture.
    static var rawParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        return style
    }
}
