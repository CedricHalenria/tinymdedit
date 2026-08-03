import SwiftUI

@main
struct TinyMDEditApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
                .task { UpdateChecker.shared.checkAutomaticallyIfNeeded() }
        }
        .defaultSize(width: 820, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                MisesAJourCommands()
            }
            CommandGroup(before: .toolbar) {
                AffichageCommands()
                Divider()
            }
        }
    }
}

/// Recherche de mises à jour, et son interrupteur.
private struct MisesAJourCommands: View {
    @AppStorage(UpdateChecker.automaticKey) private var automatique = true
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        Button("Rechercher les mises à jour…") { updates.checkNow() }
            .disabled(updates.isChecking)
        Toggle("Vérifier automatiquement", isOn: $automatique)
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
