import Foundation

/// Comparaison de numéros de version, isolée du reste pour rester vérifiable.
///
/// Volontairement tolérante : un composant non numérique vaut zéro, un « v » de
/// tête est ignoré, et une version plus courte est complétée par des zéros —
/// « 1.2 » et « 1.2.0 » désignent la même version.
enum SemanticVersion {

    /// `candidate` est-elle strictement plus récente que `current` ?
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = components(candidate)
        let old = components(current)

        for index in 0 ..< max(new.count, old.count) {
            let left = index < new.count ? new[index] : 0
            let right = index < old.count ? old[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        // On s'arrête au premier suffixe de pré-version (« 1.2.0-beta.1 ») : la
        // comparer finement n'apporterait rien ici, on ne publie pas de bêtas.
        if let dash = text.firstIndex(of: "-") {
            text = String(text[text.startIndex ..< dash])
        }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }
}
