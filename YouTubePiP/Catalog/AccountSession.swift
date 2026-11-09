import Foundation
import WebKit
import YouTubePiPCore

/// Login da conta do YouTube, reaproveitado da WebView.
///
/// Os cookies de `youtube.com` sao lidos do armazenamento da WebView, ficam so na memoria
/// (no `YouTubeCatalog`) e sao enviados apenas nas chamadas ao YouTube. Nada e salvo nem registrado.
@MainActor
final class AccountSession: ObservableObject {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(AccountProfile)
    }

    @Published private(set) var state: State = .unknown

    private let catalog: YouTubeCatalog
    private var lastCookieHeader: String?
    private var refreshTask: Task<Void, Never>?

    init(catalog: YouTubeCatalog = .shared) {
        self.catalog = catalog
    }

    var profile: AccountProfile? {
        if case .signedIn(let profile) = state { return profile }
        return nil
    }

    var isSignedIn: Bool { profile != nil }

    /// Pagina de login do Google; ao terminar, volta para o YouTube na WebView.
    static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2F")!

    /// Rele os cookies (depois de cada navegacao e ao voltar para o app). Agrupa chamadas seguidas.
    func scheduleRefresh(delay: UInt64 = 1_000_000_000) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let header = AuthCookies.header(from: cookies.map {
            AuthCookies.Cookie(name: $0.name, value: $0.value, domain: $0.domain)
        })

        // Nada mudou desde a ultima leitura valida.
        if header == lastCookieHeader, state != .unknown { return }
        lastCookieHeader = header
        await catalog.setCookies(header)

        guard header != nil else {
            state = .signedOut
            return
        }

        do {
            if let profile = try await catalog.profile() {
                state = .signedIn(profile)
            } else {
                // Cookies antigos/expirados: trata como sem login.
                await catalog.setCookies(nil)
                state = .signedOut
            }
        } catch {
            // Sem rede: mantem o estado anterior e tenta de novo na proxima leitura.
            lastCookieHeader = nil
            if state == .unknown { state = .signedOut }
        }
    }
}
