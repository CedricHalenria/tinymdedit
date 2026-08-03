import AppKit

/// Familles de langages reconnues dans les blocs de code.
///
/// On ne cherche pas à analyser chaque langage correctement — ce serait un
/// analyseur lexical par langage, à écrire et à maintenir. On regroupe plutôt les
/// langages par ce qui compte pour la coloration : comment on y écrit un
/// commentaire, et quels mots y sont des mots-clés.
enum CodeLanguage {
    case cLike      // swift, js, ts, java, c, c++, go, rust, kotlin, php, css…
    case hash       // python, ruby, shell, yaml, toml…
    case sql
    case lisp       // lisp, clojure, ini
    case markup     // html, xml
    case plain      // json, csv, texte — aucun commentaire
    case unknown

    /// Déduit la famille du mot placé après les trois accents graves.
    init(tag: String) {
        switch tag.lowercased() {
        case "swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "java",
             "c", "h", "cpp", "c++", "cs", "csharp", "go", "rust", "rs", "kotlin",
             "kt", "scala", "php", "dart", "css", "scss", "less", "groovy", "objc":
            self = .cLike
        case "python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "fish",
             "yaml", "yml", "toml", "makefile", "make", "dockerfile", "perl", "r",
             "elixir", "ex", "julia", "nix", "conf", "ini", "env":
            self = .hash
        case "sql", "postgres", "postgresql", "mysql", "sqlite":
            self = .sql
        case "lisp", "clojure", "clj", "scheme", "elisp":
            self = .lisp
        case "html", "xml", "svg", "vue", "svelte":
            self = .markup
        case "json", "csv", "txt", "text", "plain", "log", "diff":
            self = .plain
        case "":
            self = .unknown
        default:
            self = .unknown
        }
    }

    /// Préfixes ouvrant un commentaire jusqu'à la fin de la ligne.
    var lineComments: [String] {
        switch self {
        case .cLike: ["//"]
        // Sans indication de langage, on accepte les deux formes les plus
        // répandues : mieux vaut colorer un `#include` à tort que laisser tous
        // les commentaires shell en clair.
        case .unknown: ["//", "#"]
        case .hash: ["#"]
        case .sql: ["--"]
        case .lisp: [";"]
        case .markup, .plain: []
        }
    }

    /// Délimiteurs d'un commentaire pouvant courir sur plusieurs lignes.
    var blockComment: (open: String, close: String)? {
        switch self {
        case .cLike, .sql, .unknown: ("/*", "*/")
        case .markup: ("<!--", "-->")
        case .hash, .lisp, .plain: nil
        }
    }

    /// Caractères ouvrant une chaîne.
    var quotes: [unichar] {
        switch self {
        case .plain: []
        case .markup: [34, 39]              // " '
        default: [34, 39, 96]               // " ' `
        }
    }

    var keywords: Set<String> {
        switch self {
        case .plain: []
        case .hash: Self.common.union(Self.shell)
        default: Self.common
        }
    }

    /// Un jeu volontairement large, partagé par tous les langages : on vise
    /// l'effet visuel, pas l'exactitude grammaticale.
    private static let common: Set<String> = [
        "if", "else", "elif", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "return", "goto", "try", "catch", "except", "finally",
        "throw", "throws", "rethrows", "raise", "defer", "guard", "match", "when",
        "import", "from", "export", "package", "module", "require", "include",
        "using", "namespace", "extension", "typealias", "typedef",
        "class", "struct", "enum", "interface", "protocol", "trait", "impl",
        "extends", "implements", "inherits", "override", "abstract", "virtual",
        "func", "function", "fn", "def", "sub", "lambda", "proc", "method", "init",
        "deinit", "constructor", "operator", "get", "set",
        "let", "var", "const", "val", "mut", "static", "final", "readonly",
        "public", "private", "protected", "internal", "open", "sealed", "global",
        "new", "delete", "this", "self", "super", "async", "await", "yield",
        "true", "false", "null", "nil", "none", "undefined", "void",
        "in", "is", "as", "of", "and", "or", "not", "with", "where", "then",
        "int", "float", "double", "bool", "char", "string", "str", "bytes",
        "type", "auto", "unsafe", "pub", "use", "mod", "crate", "end",
    ]

    private static let shell: Set<String> = [
        "echo", "fi", "esac", "done", "until", "local", "readonly", "source",
        "alias", "unset", "shift", "exit", "trap", "eval", "exec", "printf",
    ]
}

/// Colore le contenu d'un bloc de code, ligne par ligne.
///
/// Le texte de base reste vert : la coloration ne fait que détacher commentaires,
/// chaînes, nombres et mots-clés. L'analyse est un simple balayage de gauche à
/// droite — assez pour ne jamais prendre un `//` situé dans une chaîne pour un
/// commentaire, ce qu'un empilement d'expressions régulières ferait.
enum CodeHighlighter {

    /// - Parameter inBlockComment: état reporté d'une ligne à l'autre, pour les
    ///   commentaires `/* */` qui courent sur plusieurs lignes.
    static func style(
        _ storage: NSTextStorage,
        line: String,
        lineRange: NSRange,
        language: CodeLanguage,
        inBlockComment: inout Bool
    ) {
        let ns = line as NSString
        let offset = lineRange.location
        var index = 0

        func paint(_ range: NSRange, _ color: NSColor, italic: Bool = false) {
            guard range.length > 0 else { return }
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if italic {
                attributes[.font] = NSFontManager.shared.convert(Theme.mono(), toHaveTrait: .italicFontMask)
            }
            storage.addAttributes(attributes, range: range.shifted(by: offset))
        }

        // Poursuite d'un commentaire de bloc ouvert sur une ligne précédente.
        if inBlockComment {
            guard let close = language.blockComment?.close else { inBlockComment = false; return }
            let found = ns.range(of: close)
            if found.location == NSNotFound {
                paint(NSRange(location: 0, length: ns.length), Theme.codeComment, italic: true)
                return
            }
            paint(NSRange(location: 0, length: found.upperBound), Theme.codeComment, italic: true)
            inBlockComment = false
            index = found.upperBound
        }

        while index < ns.length {
            let character = ns.character(at: index)

            // Commentaire jusqu'à la fin de la ligne.
            if let prefix = language.lineComments.first(where: { matches(ns, $0, at: index) }) {
                _ = prefix
                paint(NSRange(location: index, length: ns.length - index), Theme.codeComment, italic: true)
                return
            }

            // Commentaire de bloc.
            if let delimiters = language.blockComment, matches(ns, delimiters.open, at: index) {
                let searchStart = index + (delimiters.open as NSString).length
                let rest = NSRange(location: searchStart, length: ns.length - searchStart)
                let found = ns.range(of: delimiters.close, options: [], range: rest)
                if found.location == NSNotFound {
                    paint(NSRange(location: index, length: ns.length - index), Theme.codeComment, italic: true)
                    inBlockComment = true
                    return
                }
                paint(NSRange(location: index, length: found.upperBound - index), Theme.codeComment, italic: true)
                index = found.upperBound
                continue
            }

            // Chaîne de caractères, échappements compris.
            if language.quotes.contains(character) {
                var end = index + 1
                while end < ns.length {
                    let c = ns.character(at: end)
                    if c == 92 { end += 2; continue }            // barre oblique inverse
                    if c == character { end += 1; break }
                    if c == 10 || c == 13 { break }              // chaîne non fermée
                    end += 1
                }
                let clamped = min(end, ns.length)
                paint(NSRange(location: index, length: clamped - index), Theme.codeString)
                index = clamped
                continue
            }

            // Nombre — seulement s'il ne prolonge pas un identifiant.
            if isDigit(character), index == 0 || !isIdentifierPart(ns.character(at: index - 1)) {
                var end = index
                while end < ns.length, isDigit(ns.character(at: end)) || ns.character(at: end) == 46 {
                    end += 1
                }
                paint(NSRange(location: index, length: end - index), Theme.codeNumber)
                index = end
                continue
            }

            // Identifiant — mis en valeur si c'est un mot-clé.
            if isIdentifierStart(character) {
                var end = index
                while end < ns.length, isIdentifierPart(ns.character(at: end)) { end += 1 }
                let word = ns.substring(with: NSRange(location: index, length: end - index))
                if language.keywords.contains(word) {
                    paint(NSRange(location: index, length: end - index), Theme.codeKeyword)
                }
                index = end
                continue
            }

            index += 1
        }
    }

    // MARK: - Petits prédicats

    private static func matches(_ ns: NSString, _ needle: String, at index: Int) -> Bool {
        let length = (needle as NSString).length
        guard length > 0, index + length <= ns.length else { return false }
        return ns.compare(needle, options: [], range: NSRange(location: index, length: length)) == .orderedSame
    }

    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private static func isIdentifierStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127
    }

    private static func isIdentifierPart(_ c: unichar) -> Bool {
        isIdentifierStart(c) || isDigit(c)
    }
}
