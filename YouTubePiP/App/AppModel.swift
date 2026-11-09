import Combine
import SwiftUI
import YouTubePiPCore

/// Dono das abas e dos servicos compartilhados. Coordena a reproducao entre as abas,
/// o ciclo de vida da cena e os links abertos de fora.
@MainActor
final class AppModel: ObservableObject {
    @Published var selectedService: MediaService = .youtube

    let settings = AppSettings()
    let history = HistoryStore()
    let youtube: BrowserViewModel
    let youtubeMusic: BrowserViewModel

    private var browsers: [BrowserViewModel] { [youtube, youtubeMusic] }
    private var linkObserver: AnyCancellable?

    init() {
        // A tela bloqueada e uma so; as abas se revezam no controle dela.
        let nowPlaying = NowPlayingController()
        youtube = BrowserViewModel(service: .youtube, nowPlaying: nowPlaying, settings: settings, history: history)
        youtubeMusic = BrowserViewModel(service: .youtubeMusic, nowPlaying: nowPlaying, settings: settings, history: history)

        for browser in browsers {
            browser.onPlaybackStarted = { [weak self, weak browser] in
                guard let self, let browser else { return }
                self.playbackStarted(in: browser)
            }
        }

        linkObserver = LinkRouter.shared.$pendingLink
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.openPendingLink() }
    }

    func viewModel(for service: MediaService) -> BrowserViewModel {
        switch service {
        case .youtube: return youtube
        case .youtubeMusic: return youtubeMusic
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            browsers.forEach { $0.didEnterBackground() }
        case .active:
            browsers.forEach { $0.willEnterForeground() }
        default:
            // .inactive tambem ocorre com a Central de Controle e notificacoes: nada a fazer.
            break
        }
    }

    /// Link do YouTube Music abre na aba Music; os demais, na aba YouTube.
    private func openPendingLink() {
        guard let link = LinkRouter.shared.consume() else { return }
        let service: MediaService = link.isMusic ? .youtubeMusic : .youtube
        selectedService = service
        viewModel(for: service).open(link)
    }

    /// Garante que apenas uma aba toque por vez.
    private func playbackStarted(in source: BrowserViewModel) {
        for browser in browsers where browser !== source {
            browser.pauseAllMedia()
        }
    }
}
