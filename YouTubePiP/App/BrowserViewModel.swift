import Foundation
import UIKit
import WebKit
import YouTubePiPCore

/// Uma aba (YouTube ou YouTube Music): navegacao da WebView e a passagem da reproducao
/// da pagina para o player nativo.
@MainActor
final class BrowserViewModel: ObservableObject {
    let service: MediaService
    let playback: PlaybackController
    let bridge: WebMediaBridge

    /// Chamado quando esta aba comeca a tocar (pagina ou nativo), para pausar a outra aba.
    var onPlaybackStarted: (() -> Void)?

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    /// Progresso estimado do carregamento da pagina (0...1).
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var errorMessage: String?
    @Published var statusMessage: String?
    @Published private(set) var mediaDiagnostics: String?
    @Published private(set) var hasMediaCandidate = false

    private weak var webView: WKWebView?
    private var progressObservation: NSKeyValueObservation?
    /// Pagina pedida antes de a WebView existir (aba ainda nao aberta).
    private var pendingPageURL: URL?
    private var diagnosticsSnapshot: PageMediaSnapshot?
    private var isCapturing = false
    /// Videos que o player nativo nao conseguiu tocar; ficam na pagina para nao entrar em loop.
    private var webOnlyVideoIDs = Set<String>()

    init(service: MediaService, nowPlaying: NowPlayingController, settings: AppSettings, history: HistoryStore) {
        self.service = service
        playback = PlaybackController(service: service, nowPlaying: nowPlaying, settings: settings, history: history)
        bridge = WebMediaBridge(audioOnly: service.audioOnly)

        bridge.onEvent = { [weak self] event in
            self?.handlePageEvent(event)
        }
        playback.onEvent = { [weak self] event in
            self?.handlePlaybackEvent(event)
        }
    }

    var audioOnly: Bool { service.audioOnly }
    var supportsPictureInPicture: Bool { !audioOnly }

    // MARK: - Navegacao

    func attach(_ webView: WKWebView) {
        self.webView = webView
        bridge.webView = webView
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            let progress = change.newValue ?? 0
            Task { @MainActor [weak self] in self?.loadingProgress = progress }
        }

        if let pendingPageURL {
            self.pendingPageURL = nil
            webView.load(URLRequest(url: pendingPageURL))
        } else if webView.url == nil {
            loadHome()
        }
    }

    /// Abre um link vindo de fora: toca direto no player nativo e mostra a pagina do video.
    func open(_ link: YouTubeLink) {
        clearMessages()
        if let videoID = link.videoID {
            playback.start(track: MediaTrack(videoID: videoID), startTime: link.startTime, playlistID: link.playlistID)
        }
        if let webView {
            webView.load(URLRequest(url: link.pageURL))
        } else {
            pendingPageURL = link.pageURL
        }
    }

    /// Abre o link do YouTube que estiver na area de transferencia.
    func openCopiedLink() {
        guard let text = UIPasteboard.general.string, let link = YouTubeLink.firstLink(in: text) else {
            statusMessage = String(localized: "Nenhum link do YouTube foi copiado.")
            return
        }
        LinkRouter.shared.open(link)
    }

    func loadHome() {
        clearMessages()
        webView?.load(URLRequest(url: service.homeURL))
    }

    func reload() {
        clearMessages()
        if webView?.url == nil {
            loadHome()
        } else {
            webView?.reload()
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func navigationStarted(in webView: WKWebView) {
        isLoading = true
        errorMessage = nil
        updateNavigationState(webView)
    }

    func navigationFinished(in webView: WKWebView) {
        isLoading = false
        bridge.applyPageAdjustments()
        updateNavigationState(webView)
    }

    func navigationFailed(in webView: WKWebView, error: Error) {
        isLoading = false
        updateNavigationState(webView)

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        errorMessage = String(localized: "Não foi possível carregar o \(service.displayName). Verifique sua conexão e tente novamente.")
    }

    private func updateNavigationState(_ webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    /// Mensagem passageira atual (da aba ou do player).
    var transientMessage: String? { statusMessage ?? playback.message }

    func dismissTransientMessage() {
        statusMessage = nil
        playback.message = nil
    }

    private func clearMessages() {
        errorMessage = nil
        statusMessage = nil
        mediaDiagnostics = nil
    }

    // MARK: - Pagina -> player nativo

    private func handlePageEvent(_ event: WebMediaBridge.Event) {
        switch event {
        case .playing(let videoID):
            handlePagePlaybackStarted(videoID: videoID)
        case .paused:
            break
        case .pictureInPicture:
            // PiP da propria pagina: o app usa o PiP do player nativo.
            break
        }
    }

    /// A pagina comecou a tocar. Com o app em primeiro plano (o iOS so permite iniciar audio assim),
    /// o conteudo passa para o player nativo, que segue em segundo plano e em PiP.
    private func handlePagePlaybackStarted(videoID: String) {
        guard !videoID.isEmpty, !webOnlyVideoIDs.contains(videoID) else {
            onPlaybackStarted?()
            return
        }

        if playback.isActive, playback.currentVideoID == videoID {
            // O player da pagina voltou a tocar o mesmo conteudo; o nativo continua.
            bridge.pauseMedia()
            return
        }

        guard UIApplication.shared.applicationState == .active, !isCapturing else { return }

        bridge.pauseMedia()
        Task { await captureAndPlay() }
    }

    private func captureAndPlay() async {
        isCapturing = true
        defer { isCapturing = false }

        do {
            let capture = try await bridge.capture()
            if let snapshot = capture.snapshot {
                playback.start(with: snapshot)
            } else {
                fallBackToPage(videoID: nil)
            }
        } catch {
            fallBackToPage(videoID: nil)
        }
    }

    private func handlePlaybackEvent(_ event: PlaybackController.Event) {
        switch event {
        case .started:
            onPlaybackStarted?()
        case .ready:
            bridge.pauseMedia()
        case .failed(let videoID):
            fallBackToPage(videoID: videoID)
        }
    }

    /// O player nativo nao conseguiu tocar: devolve a reproducao para a pagina.
    private func fallBackToPage(videoID: String?) {
        if let videoID {
            webOnlyVideoIDs.insert(videoID)
        }
        statusMessage = String(localized: "Não foi possível abrir no player nativo; tocando na página (sem segundo plano).")
        bridge.resumeMedia()
    }

    // MARK: - Comandos da interface

    func togglePictureInPicture() {
        guard playback.isActive else {
            statusMessage = String(localized: "Toque em um vídeo para abrir o player e usar o Picture in Picture.")
            return
        }
        if !playback.togglePictureInPicture() {
            statusMessage = String(localized: "O vídeo ainda está carregando. Tente o PiP de novo em instantes.")
        }
    }

    /// A outra aba comecou a tocar.
    func pauseAllMedia() {
        bridge.pauseMedia()
        playback.pauseForOtherTab()
    }

    func didEnterBackground() {
        playback.didEnterBackground()
    }

    func willEnterForeground() {
        playback.willEnterForeground()
    }

    // MARK: - Diagnostico

    func inspectCurrentMedia() {
        guard !isCapturing else { return }
        statusMessage = String(localized: "Inspecionando a fonte da mídia...")

        Task {
            isCapturing = true
            defer { isCapturing = false }
            do {
                let capture = try await bridge.capture()
                statusMessage = nil
                diagnosticsSnapshot = capture.snapshot
                hasMediaCandidate = capture.snapshot != nil
                mediaDiagnostics = capture.report
            } catch {
                statusMessage = String(localized: "Não foi possível inspecionar a mídia: \(error.localizedDescription)")
            }
        }
    }

    func playDiagnosticsSnapshot() {
        dismissMediaDiagnostics()
        guard let snapshot = diagnosticsSnapshot else {
            statusMessage = String(localized: "Nenhum vídeo ou música foi identificado. Toque para reproduzir e tente novamente.")
            return
        }
        playback.start(with: snapshot)
    }

    func dismissMediaDiagnostics() {
        mediaDiagnostics = nil
    }
}
