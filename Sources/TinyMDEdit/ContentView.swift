import SwiftUI

enum Settings {
    /// Le mode d'affichage est une préférence globale, partagée par toutes les fenêtres.
    static let styledKey = "affichageMiseEnPage"
}

struct ContentView: View {

    @Binding var document: MarkdownDocument
    @AppStorage(Settings.styledKey) private var isStyled = true
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        MarkdownTextView(text: $document.text, isStyled: isStyled)
            .frame(minWidth: 420, minHeight: 300)
            .safeAreaInset(edge: .top, spacing: 0) {
                UpdateBanner(checker: updates)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Affichage", selection: $isStyled) {
                        Image(systemName: "textformat.size")
                            .help("Mise en page")
                            .tag(true)
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .help("Texte brut")
                            .tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Basculer entre mise en page et texte brut (⇧⌘M)")
                }
            }
    }
}
