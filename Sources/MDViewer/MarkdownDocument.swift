import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Type Markdown historique de Daring Fireball, déclaré dans notre Info.plist.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
}

/// Le document : rien de plus qu'une chaîne de caractères.
///
/// C'est tout l'intérêt de l'approche « édition stylée sur la source » : ce qui est
/// à l'écran et ce qui est sur le disque sont le même texte, octet pour octet.
struct MarkdownDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // On accepte l'UTF-8 (cas normal) et on se rabat sur le jeu de caractères
        // hérité plutôt que d'échouer sur un vieux fichier.
        if let string = String(data: data, encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .isoLatin1) {
            text = string
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
