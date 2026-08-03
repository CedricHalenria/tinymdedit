import SwiftUI
import AppKit

/// Recherche de nouvelles versions.
///
/// L'app n'installe rien elle-même : elle interroge l'API publique des releases
/// du dépôt, compare le numéro de version, et se contente d'ouvrir la page de
/// téléchargement dans le navigateur. Aucun identifiant n'est transmis, aucune
/// donnée n'est collectée, et la vérification automatique se désactive depuis le
/// menu de l'application.
@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let page: URL
    }

    /// Version disponible, si elle est plus récente que celle qui tourne.
    @Published private(set) var available: Release?
    /// Bandeau écarté par l'utilisateur pour cette version.
    @Published var dismissed = false
    @Published private(set) var isChecking = false

    /// Clé de la préférence, également lue par le menu.
    static let automaticKey = "verifierLesMisesAJour"
    private static let lastCheckKey = "derniereVerificationDesMisesAJour"

    private let endpoint = URL(string: "https://api.github.com/repos/CedricHalenria/tinymdedit/releases/latest")!
    private let interval: TimeInterval = 60 * 60 * 24

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Déclenchement

    /// Vérification silencieuse au lancement, au plus une fois par jour.
    func checkAutomaticallyIfNeeded() {
        guard UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true else { return }

        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < interval { return }

        Task { await check(announceResult: false) }
    }

    /// Vérification demandée depuis le menu : celle-ci rend toujours compte,
    /// même quand il n'y a rien de neuf.
    func checkNow() {
        Task { await check(announceResult: true) }
    }

    // MARK: - Interrogation

    private func check(announceResult: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        do {
            let release = try await fetchLatest()
            if SemanticVersion.isNewer(release.version, than: currentVersion) {
                if available != release {
                    dismissed = false
                }
                available = release
            } else {
                available = nil
                if announceResult { announceUpToDate() }
            }
        } catch {
            available = nil
            if announceResult { announceFailure(error) }
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        // L'API GitHub exige un en-tête d'identification du client. Il ne
        // contient que le nom de l'application, aucune donnée personnelle.
        request.setValue("TinyMDEdit/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.serveurIndisponible
        }

        struct Payload: Decodable {
            let tagName: String
            let htmlURL: String
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let page = URL(string: payload.htmlURL) else { throw UpdateError.reponseIllisible }
        return Release(version: payload.tagName, page: page)
    }

    enum UpdateError: LocalizedError {
        case serveurIndisponible
        case reponseIllisible

        var errorDescription: String? {
            switch self {
            case .serveurIndisponible: "Le serveur des versions est injoignable."
            case .reponseIllisible: "La réponse du serveur n'a pas pu être lue."
            }
        }
    }

    // MARK: - Retours à l'utilisateur

    func openDownloadPage() {
        guard let page = available?.page else { return }
        NSWorkspace.shared.open(page)
    }

    /// Une alerte plutôt qu'un bandeau : sans nouveauté à annoncer, il n'y a rien
    /// à laisser affiché, et l'utilisateur attend une réponse à sa demande.
    private func announceUpToDate() {
        let alert = NSAlert()
        alert.messageText = "TinyMDEdit est à jour"
        alert.informativeText = "Vous utilisez la version \(currentVersion), la plus récente."
        alert.addButton(withTitle: "Parfait")
        alert.runModal()
    }

    private func announceFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Impossible de vérifier les mises à jour"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Fermer")
        alert.runModal()
    }
}

// MARK: - Bandeau

/// Bandeau discret, affiché seulement quand une version plus récente existe.
struct UpdateBanner: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        if let release = checker.available, !checker.dismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                Text("La version \(release.version) est disponible.")
                    .font(.callout)
                Spacer(minLength: 8)
                Button("Télécharger") { checker.openDownloadPage() }
                Button {
                    checker.dismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Masquer")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}
