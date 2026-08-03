import AppKit

// Génère l'icône de TinyMDEdit dans un .iconset, converti ensuite en .icns par
// make-icon.sh. L'icône est dessinée par du code plutôt que livrée en binaire :
// dans un dépôt open source, elle reste ainsi lisible et modifiable.
//
// Motif : la marque Markdown — un « M » suivi d'une flèche vers le bas — posée
// sur un carré arrondi sombre. La flèche reprend le vert terminal des blocs de
// code de l'application.

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// MARK: - Palette

let backgroundTop = NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)
let letterColor = NSColor.white
let arrowColor = NSColor(srgbRed: 0.24, green: 0.83, blue: 0.32, alpha: 1)

// MARK: - Dessin

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Le carré arrondi n'occupe pas toute la toile : macOS attend une marge
    // autour de l'icône, sans quoi elle paraît plus grosse que ses voisines.
    let inset = size * 0.085
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.2237   // proportion du « squircle » d'Apple

    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    NSGradient(starting: backgroundTop, ending: backgroundBottom)?
        .draw(in: shape, angle: -90)

    // Liseré clair sur le bord supérieur, pour détacher l'icône d'un fond sombre.
    shape.lineWidth = max(1, size * 0.004)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    shape.stroke()

    // Le « M », dessiné par la fonte système en graisse lourde.
    let letterHeight = plate.height * 0.46
    let font = NSFont.systemFont(ofSize: letterHeight, weight: .heavy)
    let letter = NSAttributedString(string: "M", attributes: [
        .font: font,
        .foregroundColor: letterColor,
        .kern: 0
    ])
    let letterSize = letter.size()

    // On centre sur la hauteur de capitale, pas sur la hauteur de ligne : celle-ci
    // réserve de la place pour les jambages, que le « M » n'utilise pas, et le
    // motif paraîtrait remonté.
    let capHeight = font.capHeight
    let descender = -font.descender

    // Flèche vers le bas : un fût surmontant une pointe triangulaire, exactement
    // à la hauteur du « M ».
    let arrowHeight = capHeight
    let arrowWidth = capHeight * 0.78
    let gap = plate.width * 0.05
    let contentWidth = letterSize.width + gap + arrowWidth

    let originX = plate.midX - contentWidth / 2
    let baseline = plate.midY - capHeight / 2
    letter.draw(at: NSPoint(x: originX, y: baseline - descender))

    let arrowLeft = originX + letterSize.width + gap
    let arrowBottom = baseline
    let headHeight = arrowHeight * 0.42
    let stemWidth = arrowWidth * 0.30

    arrowColor.setFill()
    NSBezierPath(rect: NSRect(
        x: arrowLeft + (arrowWidth - stemWidth) / 2,
        y: arrowBottom + headHeight,
        width: stemWidth,
        height: arrowHeight - headHeight
    )).fill()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowLeft, y: arrowBottom + headHeight))
    head.line(to: NSPoint(x: arrowLeft + arrowWidth, y: arrowBottom + headHeight))
    head.line(to: NSPoint(x: arrowLeft + arrowWidth / 2, y: arrowBottom))
    head.close()
    head.fill()

    return rep
}

// MARK: - Écriture du .iconset

/// Chaque entrée : taille en points, et facteur d'échelle.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2),
    (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let pixels = CGFloat(variant.points * variant.scale)
    let rep = drawIcon(size: pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Échec de l'encodage PNG\n".utf8))
        exit(1)
    }
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try! data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name))
}

print("\(variants.count) images écrites dans \(outputDirectory)")
