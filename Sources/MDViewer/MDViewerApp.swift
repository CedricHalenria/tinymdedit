import SwiftUI

@main
struct MDViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .defaultSize(width: 820, height: 720)
        .commands {
            CommandGroup(before: .toolbar) {
                AffichageCommands()
                Divider()
            }
        }
    }
}

/// Entrée de menu doublant le sélecteur de la barre d'outils, avec son raccourci.
private struct AffichageCommands: View {
    @AppStorage(Settings.styledKey) private var isStyled = true

    var body: some View {
        Toggle("Afficher la mise en page", isOn: $isStyled)
            .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}
