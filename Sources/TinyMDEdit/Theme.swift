import AppKit

/// Fontes, couleurs et métriques de l'éditeur.
/// Tout est centralisé ici pour pouvoir ajuster le rendu en un seul endroit.
enum Theme {

    // MARK: - Tailles

    static let bodySize: CGFloat = 16.5
    static let monoSize: CGFloat = 14

    /// Marges intérieures minimales de la zone de texte.
    static let textInset = NSSize(width: 32, height: 28)

    /// Largeur maximale de la colonne de texte. Au-delà, la ligne devient trop
    /// longue pour que l'œil retrouve facilement le début de la suivante : on
    /// centre la colonne et on laisse le reste en marge.
    static let maxContentWidth: CGFloat = 740

    /// Barre verticale des citations : épaisseur et retrait par rapport au texte.
    static let quoteBarWidth: CGFloat = 3
    static let quoteIndent: CGFloat = 24

    /// Tableaux. La gouttière est l'espace laissé entre deux colonnes ; elle se
    /// resserre jusqu'à `tableMinGutter` quand le tableau menace de déborder de
    /// la colonne de lecture.
    static let tableGutter: CGFloat = 26
    static let tableMinGutter: CGFloat = 10
    /// Filet sous l'en-tête : épaisseur, et hauteur de la bande qui l'accueille
    /// — celle de la ligne `|---|`, réduite à sa portion utile.
    static let tableRuleWidth: CGFloat = 1
    static let tableRuleHeight: CGFloat = 13

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
        let sizes: [CGFloat] = [30, 25, 21.5, 19, 17.5, 16.5]
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
    /// Barre verticale à gauche des citations.
    static let quoteBar = NSColor.quaternaryLabelColor
    /// Filet qui sépare l'en-tête d'un tableau de son corps.
    static let tableRule = NSColor.separatorColor
    /// Fond des blocs de code délimités par ``` — utile pour marquer l'étendue
    /// d'une zone multi-lignes. Le code *en ligne*, lui, n'a pas de fond : la
    /// fonte monospace et la couleur suffisent à le distinguer.
    static let codeBlockBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)

    /// Texte du code : vert terminal, décliné pour rester lisible sur fond clair
    /// comme sur fond sombre.
    static let codeText = dynamic(
        dark: NSColor(srgbRed: 0.24, green: 0.83, blue: 0.32, alpha: 1),
        light: NSColor(srgbRed: 0.06, green: 0.45, blue: 0.13, alpha: 1),
        name: "codeText"
    )

    /// Coloration à l'intérieur des blocs de code. Le vert reste la couleur de
    /// base ; ces teintes ne font qu'en détacher ce qui mérite de l'être.
    static let codeComment = NSColor.secondaryLabelColor
    static let codeString = dynamic(
        dark: NSColor(srgbRed: 0.96, green: 0.72, blue: 0.36, alpha: 1),
        light: NSColor(srgbRed: 0.64, green: 0.38, blue: 0.02, alpha: 1),
        name: "codeString"
    )
    static let codeNumber = dynamic(
        dark: NSColor(srgbRed: 0.45, green: 0.80, blue: 0.95, alpha: 1),
        light: NSColor(srgbRed: 0.08, green: 0.42, blue: 0.62, alpha: 1),
        name: "codeNumber"
    )
    static let codeKeyword = dynamic(
        dark: NSColor(srgbRed: 0.85, green: 0.56, blue: 0.96, alpha: 1),
        light: NSColor(srgbRed: 0.52, green: 0.18, blue: 0.68, alpha: 1),
        name: "codeKeyword"
    )

    /// Couleur déclinée selon l'apparence claire ou sombre du système.
    private static func dynamic(dark: NSColor, light: NSColor, name: NSColor.Name) -> NSColor {
        NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - Paragraphes

    /// Style de paragraphe de base (mode mise en page).
    static func paragraph(
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 12
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.5
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        return style
    }

    /// Hauteur de la bande qui tient lieu de marge en haut et en bas d'un bloc.
    static let fencePadding: CGFloat = 7

    /// Ligne de code : jointive à la suivante, sans espacement de paragraphe,
    /// pour que le fond du bloc forme une surface continue.
    static var codeParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.15
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        return style
    }

    /// Ligne de délimitation dont le texte est masqué : réduite à une bande fine
    /// qui prolonge le fond du bloc et lui sert de marge intérieure.
    static func collapsedFenceParagraph(spacingAfter: CGFloat = 0) -> NSParagraphStyle {
        collapsedParagraph(height: fencePadding, spacingAfter: spacingAfter)
    }

    /// Ligne entièrement masquée, réduite à une bande de la hauteur voulue.
    static func collapsedParagraph(height: CGFloat, spacingAfter: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = 0
        return style
    }

    /// Ligne de tableau : jointive à la suivante, pour que les rangées forment
    /// une grille et non une succession de paragraphes.
    static func tableParagraph(
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    /// Style de paragraphe du mode texte brut : compact, sans fioriture.
    static var rawParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        return style
    }
}
