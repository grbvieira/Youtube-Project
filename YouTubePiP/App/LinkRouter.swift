import AppIntents
import Foundation
import YouTubePiPCore

/// Recebe links do YouTube vindos de fora (esquema `ytpip://`, Atalhos, link copiado)
/// e os entrega ao `AppModel`.
@MainActor
final class LinkRouter: ObservableObject {
    static let shared = LinkRouter()

    @Published private(set) var pendingLink: YouTubeLink?

    /// Retorna `false` se a URL nao for um link do YouTube reconhecido.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = YouTubeLink.parse(url) else { return false }
        open(link)
        return true
    }

    func open(_ link: YouTubeLink) {
        pendingLink = link
    }

    func consume() -> YouTubeLink? {
        defer { pendingLink = nil }
        return pendingLink
    }
}

/// Atalho "Abrir no YouTube PiP": recebe um link (por exemplo, pela folha de compartilhar
/// do app Atalhos) e abre no app, ja no player nativo.
struct OpenYouTubeLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir no YouTube PiP"
    static let description = IntentDescription("Abre um link do YouTube ou do YouTube Music no player do app.")
    static let openAppWhenRun = true

    @Parameter(title: "Link")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult {
        guard LinkRouter.shared.open(url) else {
            throw OpenLinkError.notYouTube
        }
        return .result()
    }

    enum OpenLinkError: Error, CustomLocalizedStringResourceConvertible {
        case notYouTube

        var localizedStringResource: LocalizedStringResource {
            "Este link não é do YouTube nem do YouTube Music."
        }
    }
}

struct YouTubePiPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenYouTubeLinkIntent(),
            phrases: ["Abrir link no \(.applicationName)"],
            shortTitle: "Abrir link",
            systemImageName: "play.rectangle"
        )
    }
}
