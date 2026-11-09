import Foundation
import Combine
import UIKit
import WebKit

@MainActor
final class BrowserViewModel: ObservableObject {
    let service: MediaService

    weak var webView: WKWebView?

    /// Chamado quando esta aba comeca a tocar (web ou nativo), para pausar a outra aba.
    var onPlaybackStarted: (() -> Void)?

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pipMessage: String?
    @Published var mediaDiagnostics: String?
    @Published private(set) var hasNativeAudioCandidate = false
    /// Ha uma faixa/video no player nativo (tocando, pausado ou carregando).
    @Published private(set) var isNativeAudioActive = false
    @Published private(set) var isNativeAudioPlaying = false
    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var nowPlayingTitle = ""
    @Published private(set) var nowPlayingArtist = ""
    @Published private(set) var nativeElapsed: TimeInterval = 0
    @Published private(set) var nativeDuration: TimeInterval = 0
    @Published private(set) var canSkipToNext = false

    private(set) var isWebMediaPlaying = false

    /// O player nativo. Para videos, `nativePlayer.videoView` e exibido no topo da aba.
    let nativePlayer = NativePlayer()

    private let audioResolver = YouTubeAudioResolver()
    private let nowPlayingController: NowPlayingController
    private var nativeAudioCapture: NativeAudioCapture?
    private var isPreparingNativeAudio = false
    private var nativeQueue: [NativeAudioTrack] = []
    private var currentQueueIndex = 0
    private var queueGeneration = UUID()
    private var retriedVideoIDs = Set<String>()
    /// Videos que o player nativo nao conseguiu tocar; ficam na pagina para nao entrar em loop.
    private var webOnlyVideoIDs = Set<String>()
    private var queueTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var populateTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(service: MediaService, nowPlayingController: NowPlayingController) {
        self.service = service
        self.nowPlayingController = nowPlayingController

        nativePlayer.onEvent = { [weak self] event in
            self?.handleNativePlayerEvent(event)
        }

        AudioSessionManager.shared.observe { [weak self] event in
            self?.handleAudioSessionEvent(event)
        }
    }

    var serviceName: String { service.rawValue }
    var homeURL: URL { service.homeURL }
    var audioOnly: Bool { service.audioOnly }
    var supportsPictureInPicture: Bool { !audioOnly }
    /// O painel de video nativo deve aparecer.
    var showsNativeVideo: Bool { !audioOnly && isNativeAudioActive }

    private var currentNativeVideoID: String? {
        nativeQueue.indices.contains(currentQueueIndex) ? nativeQueue[currentQueueIndex].videoID : nil
    }

    // MARK: - Navegacao

    func attach(_ webView: WKWebView) {
        self.webView = webView

        if webView.url == nil {
            loadHome()
        }
    }

    func loadHome() {
        errorMessage = nil
        pipMessage = nil
        mediaDiagnostics = nil
        webView?.load(URLRequest(url: homeURL))
    }

    func reload() {
        errorMessage = nil
        pipMessage = nil
        mediaDiagnostics = nil

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
        if audioOnly {
            prepareAudioOnlyMode()
        } else {
            prepareVideoElements()
        }
        updateNavigationState(webView)
    }

    func navigationFailed(in webView: WKWebView, error: Error) {
        isLoading = false
        updateNavigationState(webView)

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        errorMessage = "Nao foi possivel carregar o \(serviceName). Verifique sua conexao e tente novamente."
    }

    private func updateNavigationState(_ webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    // MARK: - Eventos da pagina

    /// Recebe eventos enviados por `mediaEventsScript` (play/pause/PiP).
    func handleMediaEvent(_ body: Any) {
        guard let event = body as? [String: Any], let type = event["type"] as? String else { return }

        switch type {
        case "playing":
            isWebMediaPlaying = true
            handleWebPlaybackStarted(videoID: (event["videoID"] as? String) ?? "")
        case "paused":
            isWebMediaPlaying = false
        case "pip":
            // PiP da propria pagina (so acontece quando o player nativo nao foi usado).
            if !nativePlayer.hasItem {
                isPictureInPictureActive = event["active"] as? Bool ?? false
            }
        default:
            break
        }
    }

    /// A pagina comecou a tocar. Com o app em primeiro plano (o iOS so permite iniciar
    /// audio assim), o video/musica passa para o player nativo, que segue em segundo plano e PiP.
    private func handleWebPlaybackStarted(videoID: String) {
        guard !videoID.isEmpty, !webOnlyVideoIDs.contains(videoID) else {
            onPlaybackStarted?()
            return
        }

        if isNativeAudioActive, currentNativeVideoID == videoID {
            // O player da pagina voltou a tocar o mesmo conteudo; o nativo continua.
            pauseWebMedia()
            return
        }

        guard UIApplication.shared.applicationState == .active else { return }

        pauseWebMedia()
        captureCurrentMedia(showDiagnostics: false, startNativePlayback: true)
    }

    // MARK: - Ciclo de vida / coordenacao

    func didEnterBackground() {
        nativePlayer.didEnterBackground()
    }

    func willEnterForeground() {
        nativePlayer.willEnterForeground()
    }

    /// Pausa tudo nesta aba (usado quando a outra aba comeca a tocar).
    func pauseAllMedia() {
        pauseWebMedia()
        if nativePlayer.isPictureInPictureActive {
            nativePlayer.stopPictureInPicture()
        }
        pauseNativeAudioPlayback()
    }

    // MARK: - Picture in Picture

    func startPictureInPicture() {
        if nativePlayer.hasItem {
            if nativePlayer.isPictureInPictureActive {
                nativePlayer.stopPictureInPicture()
            } else if !nativePlayer.startPictureInPicture() {
                pipMessage = "O video ainda esta carregando. Tente o PiP de novo em instantes."
            }
            return
        }

        pipMessage = "Toque em um video para abrir o player e usar o Picture in Picture."
    }

    func prepareVideoElements() {
        webView?.evaluateJavaScript(Self.prepareVideoElementsScript)
    }

    func prepareAudioOnlyMode() {
        webView?.evaluateJavaScript(Self.audioOnlyScript)
    }

    // MARK: - Captura da midia da pagina

    func inspectCurrentMedia() {
        captureCurrentMedia(showDiagnostics: true, startNativePlayback: false)
    }

    private func captureCurrentMedia(showDiagnostics: Bool, startNativePlayback: Bool) {
        guard !isPreparingNativeAudio else { return }

        guard let webView else {
            pipMessage = "A pagina ainda nao esta pronta para inspecionar a midia."
            return
        }

        isPreparingNativeAudio = startNativePlayback
        nativeAudioCapture = nil
        hasNativeAudioCandidate = false
        pipMessage = showDiagnostics ? "Inspecionando a fonte da midia..." : nil
        webView.evaluateJavaScript(Self.mediaDiagnosticsScript) { [weak self] result, error in
            let json = result as? String
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleCapturedMedia(
                    json: json,
                    error: error,
                    showDiagnostics: showDiagnostics,
                    startNativePlayback: startNativePlayback
                )
            }
        }
    }

    private func handleCapturedMedia(
        json: String?,
        error: Error?,
        showDiagnostics: Bool,
        startNativePlayback: Bool
    ) {
        isPreparingNativeAudio = false

        if let error {
            if startNativePlayback {
                resumeWebMediaAfterNativeFailure(videoID: nil)
            } else {
                pipMessage = "Nao foi possivel inspecionar a midia: \(error.localizedDescription)"
            }
            return
        }

        guard
            let data = json?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let formattedData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let report = String(data: formattedData, encoding: .utf8)
        else {
            if startNativePlayback {
                resumeWebMediaAfterNativeFailure(videoID: nil)
            } else {
                pipMessage = "A pagina retornou um diagnostico de midia invalido."
            }
            return
        }

        pipMessage = nil
        nativeAudioCapture = Self.nativeAudioCapture(from: object)
        hasNativeAudioCandidate = nativeAudioCapture != nil

        if showDiagnostics {
            mediaDiagnostics = report
        }

        if startNativePlayback {
            if nativeAudioCapture != nil {
                startNativeAudioPlayback()
            } else {
                resumeWebMediaAfterNativeFailure(videoID: nil)
            }
        }
    }

    func dismissMediaDiagnostics() {
        mediaDiagnostics = nil
    }

    // MARK: - Player nativo

    func startNativeAudioPlayback() {
        guard let capture = nativeAudioCapture else {
            pipMessage = "Nenhum video ou musica foi identificado. Toque para reproduzir e tente novamente."
            return
        }

        resetNativeQueue()
        configureQueue(from: capture)
        isNativeAudioActive = true
        // Ativa a sessao agora, com o app em primeiro plano: o iOS nao deixa iniciar audio em segundo plano.
        activateAudioSession()
        onPlaybackStarted?()
        resolveAndPlayTrack(
            at: currentQueueIndex,
            startTime: capture.currentTime,
            fallbackURL: capture.fallbackStreamURL
        )
        if audioOnly {
            // Filas de playlist/radio fazem sentido no YouTube Music; no YouTube toca so o video aberto.
            populateQueueIfNeeded(capture.playlistID)
        }
    }

    private func configureQueue(from capture: NativeAudioCapture) {
        var seenIDs = Set<String>()
        let pageQueue = audioOnly ? capture.queue : []
        nativeQueue = pageQueue.filter { seenIDs.insert($0.videoID).inserted }

        if let index = nativeQueue.firstIndex(where: { $0.videoID == capture.currentTrack.videoID }) {
            nativeQueue[index] = capture.currentTrack.mergingMetadata(from: nativeQueue[index])
            currentQueueIndex = index
        } else {
            nativeQueue.insert(capture.currentTrack, at: 0)
            currentQueueIndex = 0
        }
        publishCurrentTrack()
    }

    private func playTrack(at index: Int, startTime: TimeInterval = 0) {
        guard nativeQueue.indices.contains(index) else {
            finishNativeQueue()
            return
        }

        let track = nativeQueue[index]
        guard let streamURL = track.streamURL else {
            resolveAndPlayTrack(at: index, startTime: startTime)
            return
        }

        currentQueueIndex = index
        activateAudioSession()
        isNativeAudioActive = true
        isNativeAudioPlaying = false
        pipMessage = nil
        publishCurrentTrack()
        updateNowPlaying(isPlaying: false, elapsedTime: startTime)
        nativePlayer.load(url: streamURL, startTime: startTime, audioOnly: audioOnly)
    }

    func toggleNativeAudioPlayback() {
        guard nativePlayer.hasItem else { return }

        if nativePlayer.isPlaying {
            pauseNativeAudioPlayback()
        } else {
            resumeNativeAudioPlayback()
        }
    }

    func skipToNextTrack() {
        playNextTrack()
    }

    func seekNative(to time: TimeInterval) {
        seekNativeAudio(to: time)
    }

    private func resumeNativeAudioPlayback() {
        guard nativePlayer.hasItem else { return }
        activateAudioSession()
        nativePlayer.play()
        isNativeAudioPlaying = true
        bindNowPlaying()
        updateNowPlaying(isPlaying: true)
        onPlaybackStarted?()
    }

    private func pauseNativeAudioPlayback() {
        guard nativePlayer.hasItem else { return }
        nativePlayer.pause()
        isNativeAudioPlaying = false
        updateNowPlaying(isPlaying: false)
    }

    private func seekNativeAudio(to time: TimeInterval) {
        guard nativePlayer.hasItem else { return }
        let duration = nativePlayer.duration
        let target = max(0, duration > 0 ? min(time, duration) : time)
        nativePlayer.seek(to: target)
        nativeElapsed = target
        updateNowPlaying(isPlaying: nativePlayer.isPlaying, elapsedTime: target)
    }

    private func playNextTrack() {
        guard currentQueueIndex + 1 < nativeQueue.count else { return }
        playTrack(at: currentQueueIndex + 1)
    }

    private func playPreviousTrack() {
        if nativePlayer.currentTime > 5 || currentQueueIndex == 0 {
            seekNativeAudio(to: 0)
        } else {
            playTrack(at: currentQueueIndex - 1)
        }
    }

    /// Fecha o player nativo. A pagina continua pausada.
    func stopNativeAudioPlayback() {
        resetNativeQueue()
    }

    private func resetNativeQueue() {
        queueGeneration = UUID()
        queueTask?.cancel()
        prefetchTask?.cancel()
        populateTask?.cancel()
        queueTask = nil
        prefetchTask = nil
        populateTask = nil
        nativePlayer.stop()
        isNativeAudioActive = false
        isNativeAudioPlaying = false
        isPictureInPictureActive = false
        nativeQueue = []
        currentQueueIndex = 0
        retriedVideoIDs = []
        nativeElapsed = 0
        nativeDuration = 0
        publishCurrentTrack()
        clearNowPlayingIfOwned()
        endBackgroundTask()
    }

    private func finishNativeQueue() {
        nativePlayer.stop()
        isNativeAudioActive = false
        isNativeAudioPlaying = false
        isPictureInPictureActive = false
        clearNowPlayingIfOwned()
        endBackgroundTask()
    }

    /// Resolve a URL pelo `videoID` (YouTubeKit) e toca. `fallbackURL` e a URL observada
    /// na pagina, usada apenas se a resolucao falhar.
    private func resolveAndPlayTrack(at index: Int, startTime: TimeInterval, fallbackURL: URL? = nil) {
        guard nativeQueue.indices.contains(index) else {
            finishNativeQueue()
            return
        }

        nativePlayer.stop()
        isNativeAudioPlaying = false
        currentQueueIndex = index
        let generation = queueGeneration
        let track = nativeQueue[index]
        pipMessage = "Preparando \(track.title.isEmpty ? "o player" : track.title)..."
        publishCurrentTrack()
        updateNowPlaying(isPlaying: false, elapsedTime: startTime)
        // Sem audio tocando, o iOS pode suspender o app antes de a faixa ficar pronta.
        beginBackgroundTaskIfNeeded()

        queueTask?.cancel()
        queueTask = Task { [weak self, audioResolver] in
            let result: Result<NativeAudioTrack, Error>
            do {
                result = .success(try await audioResolver.resolve(track))
            } catch {
                result = .failure(error)
            }

            guard
                let self,
                !Task.isCancelled,
                self.queueGeneration == generation,
                self.nativeQueue.indices.contains(index)
            else { return }

            switch result {
            case .success(let resolved):
                self.nativeQueue[index] = resolved
                self.playTrack(at: index, startTime: startTime)
            case .failure(let error):
                if let fallbackURL {
                    var fallbackTrack = track
                    fallbackTrack.streamURL = fallbackURL
                    self.nativeQueue[index] = fallbackTrack
                    self.playTrack(at: index, startTime: startTime)
                    return
                }

                if index + 1 < self.nativeQueue.count {
                    self.pipMessage = "Nao foi possivel preparar a faixa: \(error.localizedDescription)"
                    self.playTrack(at: index + 1)
                } else {
                    self.resumeWebMediaAfterNativeFailure(videoID: track.videoID)
                }
            }
        }
    }

    private func populateQueueIfNeeded(_ playlistID: String?) {
        guard nativeQueue.count <= 1, nativeQueue.indices.contains(currentQueueIndex) else { return }
        let generation = queueGeneration
        let currentTrack = nativeQueue[currentQueueIndex]

        populateTask?.cancel()
        populateTask = Task { [weak self, audioResolver] in
            // Se a playlist for privada ou gerada, a fila do DOM continua valendo.
            guard let playlistTracks = try? await audioResolver.queueTracks(
                currentTrack: currentTrack,
                playlistID: playlistID
            ) else { return }

            guard let self, !Task.isCancelled, self.queueGeneration == generation else { return }
            self.mergePlaylistTracks(playlistTracks, currentVideoID: currentTrack.videoID)
            self.prefetchUpcomingTracks()
        }
    }

    private func mergePlaylistTracks(_ playlistTracks: [NativeAudioTrack], currentVideoID: String) {
        guard !playlistTracks.isEmpty, nativeQueue.indices.contains(currentQueueIndex) else { return }
        // Usa a versao mais recente da faixa atual (pode ja ter sido resolvida).
        let currentTrack = nativeQueue[currentQueueIndex]
        guard currentTrack.videoID == currentVideoID else { return }

        var merged = playlistTracks
        if let index = merged.firstIndex(where: { $0.videoID == currentTrack.videoID }) {
            merged[index] = currentTrack.mergingMetadata(from: merged[index])
            nativeQueue = merged
            currentQueueIndex = index
        } else {
            nativeQueue = [currentTrack] + merged.filter { $0.videoID != currentTrack.videoID }
            currentQueueIndex = 0
        }
        publishCurrentTrack()
        updateNowPlaying(isPlaying: nativePlayer.isPlaying)
    }

    private func prefetchUpcomingTracks() {
        guard !nativeQueue.isEmpty else { return }
        let generation = queueGeneration
        let lowerBound: Int = min(currentQueueIndex + 1, nativeQueue.count)
        let upperBound: Int = min(nativeQueue.count, currentQueueIndex + 6)
        let upcoming: ArraySlice<NativeAudioTrack> = nativeQueue[lowerBound..<max(upperBound, lowerBound)]
        let tracks: [NativeAudioTrack] = upcoming.filter { $0.streamURL == nil }
        guard !tracks.isEmpty else { return }

        prefetchTask?.cancel()
        prefetchTask = Task { [weak self, audioResolver] in
            for track in tracks {
                guard !Task.isCancelled else { return }
                guard let resolved = try? await audioResolver.resolve(track) else { continue }
                guard let self, !Task.isCancelled, self.queueGeneration == generation else { return }
                // A fila pode ter sido reordenada pela playlist; localiza a faixa pelo ID.
                if let index = self.nativeQueue.firstIndex(where: { $0.videoID == track.videoID }),
                   self.nativeQueue[index].streamURL == nil {
                    self.nativeQueue[index] = resolved
                }
            }
        }
    }

    private func publishCurrentTrack() {
        let track = nativeQueue.indices.contains(currentQueueIndex) ? nativeQueue[currentQueueIndex] : nil
        nowPlayingTitle = track?.title ?? ""
        nowPlayingArtist = track?.artist ?? ""
        canSkipToNext = currentQueueIndex + 1 < nativeQueue.count
    }

    // MARK: - Eventos do player nativo

    private func handleNativePlayerEvent(_ event: NativePlayer.Event) {
        switch event {
        case .ready:
            pauseWebMedia()
            isNativeAudioActive = true
            isNativeAudioPlaying = true
            pipMessage = nil
            nativeDuration = nativePlayer.duration
            bindNowPlaying()
            updateNowPlaying(isPlaying: true)
            onPlaybackStarted?()
            // O audio ja mantem o app vivo em segundo plano.
            endBackgroundTask()
            prefetchUpcomingTracks()
        case .playbackStateChanged:
            guard nativePlayer.hasItem else { return }
            isNativeAudioPlaying = nativePlayer.isPlaying
            nowPlayingController.updatePlayback(
                elapsedTime: nativePlayer.currentTime,
                duration: nativePlayer.duration,
                isPlaying: nativePlayer.isPlaying
            )
        case .timeChanged:
            guard nativePlayer.hasItem else { return }
            nativeElapsed = nativePlayer.currentTime
            let duration = nativePlayer.duration
            if duration > 0, duration != nativeDuration {
                nativeDuration = duration
            }
        case .finished:
            if currentQueueIndex + 1 < nativeQueue.count {
                playNextTrack()
            } else {
                isNativeAudioPlaying = false
                updateNowPlaying(isPlaying: false)
            }
        case .failed(let error):
            handleNativePlaybackFailure(error)
        case .pictureInPictureChanged:
            isPictureInPictureActive = nativePlayer.isPictureInPictureActive
        }
    }

    private func handleNativePlaybackFailure(_ error: Error?) {
        let failedIndex = currentQueueIndex
        let elapsed = nativePlayer.currentTime
        guard nativeQueue.indices.contains(failedIndex) else { return }

        // URLs do googlevideo expiram: tenta resolver de novo uma vez antes de desistir.
        let videoID = nativeQueue[failedIndex].videoID
        if retriedVideoIDs.insert(videoID).inserted {
            nativeQueue[failedIndex].streamURL = nil
            resolveAndPlayTrack(at: failedIndex, startTime: elapsed)
            return
        }

        if failedIndex + 1 < nativeQueue.count {
            pipMessage = "A faixa atual falhou; tocando a proxima."
            playNextTrack()
        } else {
            resumeWebMediaAfterNativeFailure(videoID: videoID)
            if let error {
                pipMessage = "O player nativo nao conseguiu tocar: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Tela bloqueada

    /// A tela bloqueada e compartilhada pelas abas; quem toca assume os comandos.
    private func bindNowPlaying() {
        nowPlayingController.owner = ObjectIdentifier(self)
        nowPlayingController.onPlay = { [weak self] in self?.resumeNativeAudioPlayback() }
        nowPlayingController.onPause = { [weak self] in self?.pauseNativeAudioPlayback() }
        nowPlayingController.onNext = { [weak self] in self?.playNextTrack() }
        nowPlayingController.onPrevious = { [weak self] in self?.playPreviousTrack() }
        nowPlayingController.onSeek = { [weak self] time in self?.seekNativeAudio(to: time) }
    }

    private func clearNowPlayingIfOwned() {
        guard nowPlayingController.owner == ObjectIdentifier(self) else { return }
        nowPlayingController.owner = nil
        nowPlayingController.clear()
    }

    private func updateNowPlaying(isPlaying: Bool, elapsedTime: TimeInterval? = nil) {
        guard nativeQueue.indices.contains(currentQueueIndex) else { return }
        guard nowPlayingController.owner == nil || nowPlayingController.owner == ObjectIdentifier(self) else { return }
        let track = nativeQueue[currentQueueIndex]
        let elapsed = elapsedTime ?? nativePlayer.currentTime
        let playerDuration = nativePlayer.duration
        let duration = playerDuration > 0 ? playerDuration : (track.duration ?? 0)
        nowPlayingController.update(
            track: track,
            fallbackTitle: serviceName,
            elapsedTime: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            canGoNext: currentQueueIndex + 1 < nativeQueue.count,
            canGoPrevious: currentQueueIndex > 0 || elapsed > 0
        )
    }

    // MARK: - Sessao de audio e segundo plano

    private func activateAudioSession() {
        do {
            try AudioSessionManager.shared.activate()
        } catch {
            pipMessage = "Nao foi possivel ativar o audio em segundo plano: \(error.localizedDescription)"
        }
    }

    private func handleAudioSessionEvent(_ event: AudioSessionManager.Event) {
        guard nativePlayer.hasItem else { return }

        switch event {
        case .interruptionBegan:
            wasPlayingBeforeInterruption = isNativeAudioPlaying
            pauseNativeAudioPlayback()
        case .interruptionEnded(let shouldResume):
            if shouldResume && wasPlayingBeforeInterruption {
                resumeNativeAudioPlayback()
            }
            wasPlayingBeforeInterruption = false
        case .outputDeviceUnavailable:
            // Fone desconectado: pausa, como os apps de musica do sistema.
            pauseNativeAudioPlayback()
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NativePlayerPreparation") { [weak self] in
            MainActor.assumeIsolated {
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Midia da pagina

    private func pauseWebMedia() {
        webView?.evaluateJavaScript(Self.pauseWebMediaScript)
    }

    /// O player nativo nao conseguiu tocar: devolve a reproducao para a pagina.
    private func resumeWebMediaAfterNativeFailure(videoID: String?) {
        let videoID = videoID ?? currentNativeVideoID
        resetNativeQueue()
        if let videoID {
            webOnlyVideoIDs.insert(videoID)
        }
        pipMessage = "Nao foi possivel abrir no player nativo; tocando na pagina (sem segundo plano)."
        webView?.evaluateJavaScript(Self.resumeWebMediaScript)
    }

    // MARK: - Parsing do diagnostico

    private static func nativeAudioCapture(from object: Any) -> NativeAudioCapture? {
        guard let report = object as? [String: Any] else { return nil }

        let activeElement = report["activeElement"] as? [String: Any]
        let metadataTime = (report["metadata"] as? [String: Any])?["currentTime"] as? Double
        let currentTime = metadataTime ?? activeElement?["currentTime"] as? Double ?? 0
        let duration = activeElement?["duration"] as? Double
        let resourceURLs = report["resourceURLs"] as? [String] ?? []
        let metadata = report["metadata"] as? [String: Any] ?? [:]
        let pageURL = (report["pageURL"] as? String).flatMap(URL.init(string:))
        let pageComponents = pageURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let currentVideoID = (metadata["videoID"] as? String).nonEmpty
            ?? pageComponents?.queryItems?.first(where: { $0.name == "v" })?.value
        let playlistID = (metadata["playlistID"] as? String).nonEmpty
            ?? pageComponents?.queryItems?.first(where: { $0.name == "list" })?.value

        guard let currentVideoID else { return nil }

        let currentTrack = NativeAudioTrack(
            videoID: currentVideoID,
            streamURL: nil,
            title: (metadata["title"] as? String).nonEmpty ?? "YouTube Music",
            artist: (metadata["artist"] as? String).nonEmpty ?? "",
            artworkURL: (metadata["artworkURL"] as? String).flatMap(URL.init(string:)),
            duration: duration
        )

        return NativeAudioCapture(
            currentTrack: currentTrack,
            fallbackStreamURL: latestAudioStreamURL(in: resourceURLs),
            currentTime: currentTime,
            playlistID: playlistID,
            queue: nativeQueue(from: report["queueItems"])
        )
    }

    private static func latestAudioStreamURL(in resourceURLs: [String]) -> URL? {
        for value in resourceURLs.reversed() {
            guard
                var components = URLComponents(string: value),
                components.host?.hasSuffix("googlevideo.com") == true,
                components.path.contains("videoplayback")
            else {
                continue
            }

            let queryItems = components.queryItems ?? []
            let mimeType = queryItems.first(where: { $0.name == "mime" })?.value ?? ""
            guard mimeType.lowercased().hasPrefix("audio/") else { continue }

            let requestOnlyParameters: Set<String> = ["range", "rn", "rbuf", "alr", "ump", "srfvp"]
            components.queryItems = queryItems.filter { !requestOnlyParameters.contains($0.name) }
            if let url = components.url {
                return url
            }
        }
        return nil
    }

    private static func nativeQueue(from object: Any?) -> [NativeAudioTrack] {
        guard let items = object as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let videoID = (item["videoID"] as? String).nonEmpty else { return nil }
            return NativeAudioTrack(
                videoID: videoID,
                streamURL: nil,
                title: (item["title"] as? String).nonEmpty ?? "",
                artist: (item["artist"] as? String).nonEmpty ?? "",
                artworkURL: (item["artworkURL"] as? String).flatMap(URL.init(string:)),
                duration: nil
            )
        }
    }

    // MARK: - Scripts

    static let mediaEventsHandlerName = "ytpipMedia"

    /// Envia para o app eventos de play/pause e de entrada/saida do PiP.
    /// Os eventos de midia nao propagam (bubble), por isso sao escutados na fase de captura.
    static let mediaEventsScript = """
    (() => {
        if (window.__ytpipMediaEvents) return;
        window.__ytpipMediaEvents = true;

        // O buffer padrao (~250 entradas) enche rapido e congela a lista de recursos.
        try { performance.setResourceTimingBufferSize(2000); } catch (error) {}

        const post = (payload) => {
            try { window.webkit.messageHandlers.\(mediaEventsHandlerName).postMessage(payload); } catch (error) {}
        };
        const urlVideoID = () => {
            try {
                const url = new URL(window.location.href);
                const parts = url.pathname.split('/');
                return url.searchParams.get('v') || (parts[1] === 'shorts' ? (parts[2] || '') : '');
            } catch (error) { return ''; }
        };
        // O player da pagina sabe o que esta realmente tocando; a URL pode estar atrasada.
        const playerVideoID = () => {
            try {
                const player = document.getElementById('movie_player');
                const data = player && player.getVideoData && player.getVideoData();
                return (data && data.video_id) || '';
            } catch (error) { return ''; }
        };
        // No YouTube Music a URL atualiza com atraso; no YouTube o player reporta o anuncio.
        const isMusic = window.location.hostname.startsWith('music.');
        const videoID = () => isMusic
            ? (playerVideoID() || urlVideoID())
            : (urlVideoID() || playerVideoID());
        const isMedia = (target) => target instanceof HTMLMediaElement;

        document.addEventListener('playing', (event) => {
            if (isMedia(event.target)) post({ type: 'playing', videoID: videoID() });
        }, true);
        ['pause', 'ended'].forEach((name) => document.addEventListener(name, (event) => {
            if (isMedia(event.target)) post({ type: 'paused', videoID: videoID() });
        }, true));
        document.addEventListener('enterpictureinpicture', () => post({ type: 'pip', active: true }), true);
        document.addEventListener('leavepictureinpicture', () => post({ type: 'pip', active: false }), true);
        document.addEventListener('webkitpresentationmodechanged', (event) => {
            const target = event.target;
            if (target instanceof HTMLVideoElement) {
                post({ type: 'pip', active: target.webkitPresentationMode === 'picture-in-picture' });
            }
        }, true);
    })();
    """

    static let prepareVideoElementsScript = """
    (() => {
        const prepare = () => {
            document.querySelectorAll('video').forEach((video) => {
                video.setAttribute('playsinline', '');
                video.setAttribute('webkit-playsinline', '');
                video.disablePictureInPicture = false;
            });
        };

        prepare();
        if (!window.__youtubePiPObserver) {
            window.__youtubePiPObserver = new MutationObserver(prepare);
            window.__youtubePiPObserver.observe(document.documentElement, { childList: true, subtree: true });
        }
    })();
    """

    static let audioOnlyScript = """
    (() => {
        const apply = () => {
            document.querySelectorAll('video').forEach((video) => {
                video.style.opacity = '0';
                video.style.pointerEvents = 'none';
                video.style.position = 'fixed';
                video.style.width = '1px';
                video.style.height = '1px';
                video.style.left = '-10px';
                video.style.top = '-10px';
            });
        };

        apply();
        if (!window.__youtubeMusicAudioOnlyObserver) {
            window.__youtubeMusicAudioOnlyObserver = new MutationObserver(apply);
            window.__youtubeMusicAudioOnlyObserver.observe(document.documentElement, { childList: true, subtree: true });
        }
    })();
    """

    private static let mediaDiagnosticsScript = #"""
    (() => {
        const elements = Array.from(document.querySelectorAll('audio, video'));
        const activeElement = elements.find((item) => !item.paused && item.readyState > 0)
            || elements.find((item) => item.readyState > 0)
            || elements[0]
            || null;

        const describe = (item, index) => ({
            index,
            type: item.tagName.toLowerCase(),
            currentSrc: item.currentSrc || '',
            src: item.getAttribute('src') || '',
            paused: item.paused,
            muted: item.muted,
            readyState: item.readyState,
            networkState: item.networkState,
            currentTime: Number.isFinite(item.currentTime) ? Number(item.currentTime.toFixed(3)) : null,
            duration: Number.isFinite(item.duration) ? Number(item.duration.toFixed(3)) : null
        });

        const cleanText = (value) => (value || '').replace(/\s+/g, ' ').trim();
        const textFrom = (root, selectors) => {
            for (const selector of selectors) {
                const element = root && root.querySelector(selector);
                const value = cleanText(element && (element.textContent || element.getAttribute('title')));
                if (value) return value;
            }
            return '';
        };
        const imageFrom = (root) => {
            const image = root && root.querySelector('img');
            return image ? (image.currentSrc || image.src || '') : '';
        };
        const videoIDFromURL = (value) => {
            try {
                return new URL(value, window.location.href).searchParams.get('v') || '';
            } catch (error) {
                return '';
            }
        };

        const page = new URL(window.location.href);
        const isMusic = page.hostname.startsWith('music.');
        const playerBar = document.querySelector('ytmusic-player-bar');
        const shortsMatch = page.pathname.match(/^\/shorts\/([\w-]{6,})/);
        const urlVideoID = page.searchParams.get('v') || (shortsMatch ? shortsMatch[1] : '');

        // Estado real do player da pagina (a URL e a barra podem estar atrasadas no YouTube Music).
        const player = document.getElementById('movie_player');
        const call = (name) => {
            try { return player && typeof player[name] === 'function' ? player[name]() : null; } catch (error) { return null; }
        };
        const playerData = call('getVideoData') || {};
        const playerVideoID = playerData.video_id || '';
        const playerTime = call('getCurrentTime');
        const currentVideoID = isMusic ? (playerVideoID || urlVideoID) : (urlVideoID || playerVideoID);
        const useplayerData = playerVideoID && playerVideoID === currentVideoID;

        const metadata = {
            videoID: currentVideoID,
            playlistID: (isMusic && call('getPlaylistId')) || page.searchParams.get('list') || '',
            title: (useplayerData && cleanText(playerData.title))
                || textFrom(playerBar, ['.title', '.song-title', 'yt-formatted-string.title'])
                || cleanText(document.title.replace(/\s*-\s*YouTube( Music)?\s*$/, '')),
            artist: (useplayerData && cleanText(playerData.author))
                || textFrom(playerBar, ['.byline', '.subtitle', '.secondary-flex-columns']),
            artworkURL: useplayerData
                ? `https://i.ytimg.com/vi/${currentVideoID}/hqdefault.jpg`
                : imageFrom(playerBar),
            currentTime: (useplayerData && Number.isFinite(playerTime)) ? playerTime : null
        };

        const queueRoot = document.querySelector('ytmusic-player-queue')
            || document.querySelector('ytmusic-player-page #side-panel')
            || document.querySelector('#queue');
        const queueElements = queueRoot
            ? Array.from(queueRoot.querySelectorAll('ytmusic-player-queue-item, ytmusic-responsive-list-item-renderer'))
            : [];
        const queueItems = [];
        const seenVideoIDs = new Set();

        for (const item of queueElements) {
            const anchor = item.querySelector('a[href*="watch?v="]');
            const videoID = anchor ? videoIDFromURL(anchor.href || anchor.getAttribute('href')) : '';
            if (!videoID || seenVideoIDs.has(videoID)) continue;
            seenVideoIDs.add(videoID);
            queueItems.push({
                videoID,
                title: textFrom(item, ['.song-title', '.title', 'yt-formatted-string.title', 'a[href*="watch?v="]']),
                artist: textFrom(item, ['.byline', '.subtitle', '.secondary-flex-columns']),
                artworkURL: imageFrom(item)
            });
        }

        if (currentVideoID && !seenVideoIDs.has(currentVideoID)) {
            queueItems.unshift({
                videoID: currentVideoID,
                title: metadata.title,
                artist: metadata.artist,
                artworkURL: metadata.artworkURL
            });
        }

        const resourceURLs = performance.getEntriesByType('resource')
            .map((entry) => entry.name)
            .filter((url) => {
                const value = url.toLowerCase();
                return value.includes('googlevideo.com')
                    || value.includes('/videoplayback')
                    || value.includes('mime=audio')
                    || value.includes('mime%3daudio');
            })
            .slice(-30);

        return JSON.stringify({
            capturedAt: new Date().toISOString(),
            pageURL: window.location.href,
            activeElement: activeElement ? describe(activeElement, elements.indexOf(activeElement)) : null,
            mediaElements: elements.map(describe),
            metadata,
            queueItems,
            resourceURLs
        });
    })();
    """#

    private static let resumeWebMediaScript = """
    (() => {
        const media = Array.from(document.querySelectorAll('audio, video'))
            .find((item) => item.readyState > 0);
        if (!media) return 'missing';
        media.play().catch(() => {});
        return 'playing';
    })();
    """

    private static let pauseWebMediaScript = """
    (() => {
        const media = Array.from(document.querySelectorAll('audio, video'));
        media.forEach((item) => item.pause());
        return 'paused';
    })();
    """

}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
