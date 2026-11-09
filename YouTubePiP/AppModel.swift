import SwiftUI

/// Dono dos dois navegadores. Coordena a reproducao entre as abas e o ciclo de vida da cena.
@MainActor
final class AppModel: ObservableObject {
    let youtube: BrowserViewModel
    let youtubeMusic: BrowserViewModel

    private var browsers: [BrowserViewModel] { [youtube, youtubeMusic] }

    init() {
        // A tela bloqueada e uma so; as abas se revezam no controle dela.
        let nowPlaying = NowPlayingController()
        youtube = BrowserViewModel(service: .youtube, nowPlayingController: nowPlaying)
        youtubeMusic = BrowserViewModel(service: .youtubeMusic, nowPlayingController: nowPlaying)

        for browser in browsers {
            browser.onPlaybackStarted = { [weak self, weak browser] in
                guard let self, let browser else { return }
                self.playbackStarted(in: browser)
            }
        }
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

    /// Garante que apenas uma aba toque por vez.
    private func playbackStarted(in source: BrowserViewModel) {
        for browser in browsers where browser !== source {
            browser.pauseAllMedia()
        }
    }
}
