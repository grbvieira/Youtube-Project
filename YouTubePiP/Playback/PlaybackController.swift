import Combine
import Foundation
import UIKit
import YouTubePiPCore

/// Reproducao nativa de uma aba: fila, resolucao das URLs, player, tela bloqueada,
/// interrupcoes de audio e segundo plano.
@MainActor
final class PlaybackController: ObservableObject {
    enum Event {
        /// Esta aba passou a tocar (a outra deve pausar).
        case started
        /// O player nativo esta pronto; a pagina deve ficar pausada.
        case ready
        /// O player nativo nao conseguiu tocar este video; a pagina deve assumir.
        case failed(videoID: String)
    }

    var onEvent: ((Event) -> Void)?

    /// Ha algo no player nativo (tocando, pausado ou carregando).
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isPictureInPictureActive = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var canSkipToNext = false
    @Published private(set) var artworkURL: URL?
    /// Resolvendo a URL ou carregando o stream.
    @Published private(set) var isPreparing = false
    /// Fila completa e posicao atual, para a tela "Tocando agora".
    @Published private(set) var queueTracks: [MediaTrack] = []
    @Published private(set) var currentIndex = 0
    /// Mensagem passageira (erros); a interface a esconde depois de alguns segundos.
    @Published var message: String?
    /// So audio: sempre no YouTube Music; no YouTube, quando ligado nas configuracoes.
    @Published private(set) var isAudioOnly: Bool
    @Published private(set) var rate: Float = 1
    @Published private(set) var sleepTimer = SleepTimer()
    /// Tempo restante do timer para dormir (atualizado a cada segundo).
    @Published private(set) var sleepRemaining: TimeInterval?

    let player = NativePlayer()

    private let service: MediaService
    private let settings: AppSettings
    private let history: HistoryStore
    private let resolver = YouTubeStreamResolver()
    private let nowPlaying: NowPlayingController
    private var settingsObservers: Set<AnyCancellable> = []
    private var sleepTask: Task<Void, Never>?
    private var lastHistoryRecord = Date.distantPast
    private var queue = PlaybackQueue()
    /// Muda a cada nova fila; respostas de tarefas antigas sao descartadas.
    private var generation = UUID()
    private var retriedVideoIDs = Set<String>()
    private var resolveTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var playlistTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private static let prefetchCount = 5
    private static let restartThreshold: TimeInterval = 5
    private static let historyInterval: TimeInterval = 5

    init(service: MediaService, nowPlaying: NowPlayingController, settings: AppSettings, history: HistoryStore) {
        self.service = service
        self.nowPlaying = nowPlaying
        self.settings = settings
        self.history = history
        isAudioOnly = service.audioOnly || settings.youtubeAudioOnly

        // Mudancas nas configuracoes valem para o que ja esta tocando.
        if !service.audioOnly {
            settings.$youtubeAudioOnly
                .dropFirst()
                .sink { [weak self] audioOnly in self?.setAudioOnly(audioOnly) }
                .store(in: &settingsObservers)
        }
        settings.$quality
            .dropFirst()
            .sink { [weak self] quality in self?.applyQuality(quality) }
            .store(in: &settingsObservers)

        player.onEvent = { [weak self] event in
            self?.handlePlayerEvent(event)
        }
        AudioSessionManager.shared.observe { [weak self] event in
            self?.handleAudioSessionEvent(event)
        }
    }

    var currentVideoID: String? { queue.current?.videoID }
    var showsVideo: Bool { !isAudioOnly && isActive }
    private var isMusic: Bool { service.audioOnly }
    private var serviceName: String { service.displayName }

    // MARK: - Comandos

    /// Comeca a tocar o que a pagina estava tocando.
    func start(with snapshot: PageMediaSnapshot) {
        reset()
        // Filas de playlist/radio fazem sentido no YouTube Music; no YouTube toca so o video aberto.
        queue = PlaybackQueue(snapshot: snapshot, includePageQueue: isMusic)
        isActive = true
        publishTrack()
        // Ativa a sessao agora, em primeiro plano: o iOS nao deixa iniciar audio em segundo plano.
        activateAudioSession()
        onEvent?(.started)
        resolveAndPlay(
            at: queue.currentIndex,
            startTime: startPosition(for: snapshot.currentTrack.videoID, requested: snapshot.currentTime),
            fallbackURL: snapshot.fallbackStreamURL
        )

        if isMusic, queue.tracks.count <= 1 {
            loadPlaylist(snapshot.playlistID)
        }
    }

    /// Toca um video direto pelo ID (link aberto de fora ou item do historico), sem esperar a pagina.
    func start(track: MediaTrack, startTime: TimeInterval?, playlistID: String?) {
        start(with: PageMediaSnapshot(
            currentTrack: track,
            fallbackStreamURL: nil,
            currentTime: startTime ?? 0,
            playlistID: playlistID,
            queue: []
        ))
    }

    /// Toca uma lista (playlist nativa) a partir de `startIndex`.
    func start(tracks: [MediaTrack], startIndex: Int) {
        guard !tracks.isEmpty else { return }
        reset()
        queue = PlaybackQueue(tracks: tracks, currentIndex: startIndex)
        isActive = true
        publishTrack()
        activateAudioSession()
        onEvent?(.started)
        begin(at: queue.currentIndex)
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        player.rate = rate
        nowPlaying.playbackRate = rate
        updateNowPlaying()
    }

    /// Liga o timer para dormir, ou desliga com `nil`.
    func setSleepTimer(_ option: SleepTimer.Option?) {
        sleepTimer.set(option, now: Date())
        sleepTask?.cancel()
        sleepTask = nil
        sleepRemaining = sleepTimer.remaining(now: Date())
        guard sleepTimer.deadline != nil else { return }

        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                self.sleepRemaining = self.sleepTimer.remaining(now: now)
                if self.sleepTimer.isExpired(now: now) {
                    self.sleepTimerFired()
                    return
                }
            }
        }
    }

    private func sleepTimerFired() {
        pause()
        sleepTimer.set(nil, now: Date())
        sleepTask?.cancel()
        sleepTask = nil
        sleepRemaining = nil
        message = String(localized: "Timer para dormir: reprodução pausada.")
    }

    private func setAudioOnly(_ youtubeAudioOnly: Bool) {
        isAudioOnly = service.audioOnly || youtubeAudioOnly
        if player.hasItem {
            player.configure(audioOnly: isAudioOnly, quality: settings.quality)
        }
    }

    private func applyQuality(_ quality: StreamQuality) {
        if player.hasItem {
            player.configure(audioOnly: isAudioOnly, quality: quality)
        }
    }

    /// Retoma de onde parou se o pedido for "do inicio" e o historico tiver uma posicao valida.
    private func startPosition(for videoID: String, requested: TimeInterval) -> TimeInterval {
        guard requested < Self.restartThreshold, let resume = history.resumePosition(for: videoID) else {
            return requested
        }
        message = String(localized: "Continuando de \(formatTime(resume)).")
        return resume
    }

    private func recordHistory(position: TimeInterval? = nil) {
        guard let track = queue.current, player.hasItem else { return }
        lastHistoryRecord = Date()
        history.record(
            track,
            position: position ?? player.currentTime,
            duration: player.duration > 0 ? player.duration : track.duration,
            isMusic: isMusic
        )
    }

    func togglePlayPause() {
        player.isPlaying ? pause() : play()
    }

    func play() {
        guard player.hasItem else { return }
        activateAudioSession()
        player.play()
        isPlaying = true
        bindNowPlaying()
        updateNowPlaying()
        onEvent?(.started)
    }

    func pause() {
        guard player.hasItem else { return }
        player.pause()
        isPlaying = false
        recordHistory()
        updateNowPlaying()
    }

    func skipToNext() {
        guard queue.hasNext else { return }
        recordHistory()
        begin(at: queue.currentIndex + 1)
    }

    func skipToPrevious() {
        if player.currentTime > Self.restartThreshold || !queue.hasPrevious {
            seek(to: 0)
        } else {
            recordHistory()
            begin(at: queue.currentIndex - 1)
        }
    }

    /// Comeca uma faixa da fila, retomando de onde parou quando fizer sentido.
    private func begin(at index: Int) {
        guard let track = queue[index] else { return }
        play(at: index, startTime: startPosition(for: track.videoID, requested: 0))
    }

    func seek(to time: TimeInterval) {
        guard player.hasItem else { return }
        let length = player.duration
        let target = max(0, length > 0 ? min(time, length) : time)
        player.seek(to: target)
        elapsed = target
        updateNowPlaying(elapsedTime: target)
    }

    /// Toca uma faixa especifica da fila (toque na lista "Tocando agora").
    func jump(to index: Int) {
        guard index != queue.currentIndex || !player.hasItem else { return }
        recordHistory()
        begin(at: index)
    }

    func removeFromQueue(at index: Int) {
        guard queue.remove(at: index) else { return }
        publishTrack()
        updateNowPlaying()
    }

    func moveInQueue(from source: Int, to destination: Int) {
        queue.move(from: source, to: destination)
        publishTrack()
        updateNowPlaying()
        prefetchUpcoming()
    }

    /// Fecha o player nativo.
    func stop() {
        reset()
    }

    /// Entra ou sai do PiP. Retorna `false` se ainda nao for possivel (video carregando).
    func togglePictureInPicture() -> Bool {
        if player.isPictureInPictureActive {
            player.stopPictureInPicture()
            return true
        }
        return player.startPictureInPicture()
    }

    /// A outra aba comecou a tocar.
    func pauseForOtherTab() {
        if player.isPictureInPictureActive {
            player.stopPictureInPicture()
        }
        pause()
    }

    func didEnterBackground() {
        player.didEnterBackground()
    }

    func willEnterForeground() {
        player.willEnterForeground()
    }

    // MARK: - Fila

    private func play(at index: Int, startTime: TimeInterval = 0) {
        guard let track = queue[index] else {
            finish()
            return
        }
        guard let streamURL = track.streamURL else {
            resolveAndPlay(at: index, startTime: startTime)
            return
        }

        queue.moveTo(index)
        activateAudioSession()
        isActive = true
        isPlaying = false
        isPreparing = true
        publishTrack()
        updateNowPlaying(isPlaying: false, elapsedTime: startTime)
        player.load(url: streamURL, startTime: startTime, audioOnly: isAudioOnly, quality: settings.quality)
    }

    /// Resolve a URL pelo `videoID` e toca. `fallbackURL` (vista na pagina) so e usada se a resolucao falhar.
    private func resolveAndPlay(at index: Int, startTime: TimeInterval, fallbackURL: URL? = nil) {
        guard let track = queue[index] else {
            finish()
            return
        }

        player.stop()
        isPlaying = false
        queue.moveTo(index)
        let generation = generation
        isPreparing = true
        publishTrack()
        updateNowPlaying(isPlaying: false, elapsedTime: startTime)
        // Sem audio tocando, o iOS pode suspender o app antes de a faixa ficar pronta.
        beginBackgroundTask()

        resolveTask?.cancel()
        resolveTask = Task { [weak self, resolver] in
            let result: Result<MediaTrack, Error>
            do {
                result = .success(try await resolver.resolve(track))
            } catch {
                result = .failure(error)
            }

            guard let self, !Task.isCancelled, self.generation == generation, self.queue.contains(index: index) else { return }

            switch result {
            case .success(let resolved):
                self.queue.replace(at: index, with: resolved)
                self.play(at: index, startTime: startTime)
            case .failure(let error):
                if let fallbackURL {
                    var fallback = track
                    fallback.streamURL = fallbackURL
                    self.queue.replace(at: index, with: fallback)
                    self.play(at: index, startTime: startTime)
                } else if index + 1 < self.queue.tracks.count {
                    self.message = String(localized: "Não foi possível preparar a faixa: \(error.localizedDescription)")
                    self.play(at: index + 1)
                } else {
                    self.giveUp(videoID: track.videoID)
                }
            }
        }
    }

    private func loadPlaylist(_ playlistID: String?) {
        guard let current = queue.current else { return }
        let generation = generation

        playlistTask?.cancel()
        playlistTask = Task { [weak self, resolver] in
            // Se a playlist for privada ou gerada, a fila da pagina continua valendo.
            guard let tracks = try? await resolver.queueTracks(currentTrack: current, playlistID: playlistID) else { return }
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            if self.queue.mergePlaylist(tracks, expectedCurrentVideoID: current.videoID) {
                self.publishTrack()
                self.updateNowPlaying()
                self.prefetchUpcoming()
            }
        }
    }

    /// Resolve as proximas faixas antes da hora, para a troca ser imediata.
    private func prefetchUpcoming() {
        let tracks = queue.unresolvedUpcoming(limit: Self.prefetchCount)
        guard !tracks.isEmpty else { return }
        let generation = generation

        prefetchTask?.cancel()
        prefetchTask = Task { [weak self, resolver] in
            for track in tracks {
                guard !Task.isCancelled else { return }
                guard let resolved = try? await resolver.resolve(track) else { continue }
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.queue.storePrefetched(resolved)
                self.publishTrack()
            }
        }
    }

    private func reset() {
        recordHistory()
        generation = UUID()
        [resolveTask, prefetchTask, playlistTask].forEach { $0?.cancel() }
        resolveTask = nil
        prefetchTask = nil
        playlistTask = nil
        player.stop()
        queue = PlaybackQueue()
        retriedVideoIDs = []
        isActive = false
        isPlaying = false
        isPreparing = false
        isPictureInPictureActive = false
        elapsed = 0
        duration = 0
        message = nil
        publishTrack()
        clearNowPlayingIfOwned()
        endBackgroundTask()
    }

    /// Chegou ao fim da fila ou nao ha como continuar.
    private func finish() {
        player.stop()
        isActive = false
        isPlaying = false
        isPreparing = false
        isPictureInPictureActive = false
        clearNowPlayingIfOwned()
        endBackgroundTask()
    }

    private func giveUp(videoID: String) {
        reset()
        onEvent?(.failed(videoID: videoID))
    }

    private func publishTrack() {
        title = queue.current?.title ?? ""
        artist = queue.current?.artist ?? ""
        artworkURL = queue.current?.artworkURL
        canSkipToNext = queue.hasNext
        if queueTracks != queue.tracks { queueTracks = queue.tracks }
        if currentIndex != queue.currentIndex { currentIndex = queue.currentIndex }
    }

    // MARK: - Eventos do player

    private func handlePlayerEvent(_ event: NativePlayer.Event) {
        switch event {
        case .ready:
            isActive = true
            isPlaying = true
            isPreparing = false
            duration = player.duration
            bindNowPlaying()
            updateNowPlaying(isPlaying: true)
            onEvent?(.ready)
            onEvent?(.started)
            recordHistory()
            // O audio ja mantem o app vivo em segundo plano.
            endBackgroundTask()
            prefetchUpcoming()
        case .playbackStateChanged:
            guard player.hasItem else { return }
            isPlaying = player.isPlaying
            nowPlaying.updatePlayback(elapsedTime: player.currentTime, duration: player.duration, isPlaying: player.isPlaying)
        case .timeChanged:
            guard player.hasItem else { return }
            elapsed = player.currentTime
            if player.duration > 0, player.duration != duration {
                duration = player.duration
            }
            if isPlaying, Date().timeIntervalSince(lastHistoryRecord) >= Self.historyInterval {
                recordHistory()
            }
        case .finished:
            // Terminou: fica no historico como assistido (nao sera retomado).
            recordHistory(position: player.duration)
            if sleepTimer.stopsAtEndOfTrack {
                isPlaying = false
                setSleepTimer(nil)
                updateNowPlaying(isPlaying: false)
                message = String(localized: "Timer para dormir: reprodução pausada no fim da faixa.")
            } else if queue.hasNext {
                begin(at: queue.currentIndex + 1)
            } else {
                isPlaying = false
                updateNowPlaying(isPlaying: false)
            }
        case .failed(let error):
            handlePlaybackFailure(error)
        case .pictureInPictureChanged:
            isPictureInPictureActive = player.isPictureInPictureActive
        }
    }

    private func handlePlaybackFailure(_ error: Error?) {
        let index = queue.currentIndex
        let elapsed = player.currentTime
        guard let track = queue.current else { return }

        // URLs do googlevideo expiram: tenta resolver de novo uma vez antes de desistir.
        if retriedVideoIDs.insert(track.videoID).inserted {
            queue.invalidateStream(at: index)
            resolveAndPlay(at: index, startTime: elapsed)
            return
        }

        if queue.hasNext {
            message = String(localized: "A faixa atual falhou; tocando a próxima.")
            skipToNext()
        } else {
            giveUp(videoID: track.videoID)
            if let error {
                message = String(localized: "O player nativo não conseguiu tocar: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tela bloqueada

    /// A tela bloqueada e compartilhada pelas abas; quem toca assume os comandos.
    private func bindNowPlaying() {
        nowPlaying.owner = ObjectIdentifier(self)
        nowPlaying.playbackRate = rate
        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onNext = { [weak self] in self?.skipToNext() }
        nowPlaying.onPrevious = { [weak self] in self?.skipToPrevious() }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
    }

    private func clearNowPlayingIfOwned() {
        guard nowPlaying.owner == ObjectIdentifier(self) else { return }
        nowPlaying.owner = nil
        nowPlaying.clear()
    }

    private func updateNowPlaying(isPlaying: Bool? = nil, elapsedTime: TimeInterval? = nil) {
        guard let track = queue.current else { return }
        guard nowPlaying.owner == nil || nowPlaying.owner == ObjectIdentifier(self) else { return }
        let elapsed = elapsedTime ?? player.currentTime
        let length = player.duration > 0 ? player.duration : (track.duration ?? 0)
        nowPlaying.update(
            track: track,
            fallbackTitle: serviceName,
            elapsedTime: elapsed,
            duration: length,
            isPlaying: isPlaying ?? player.isPlaying,
            canGoNext: queue.hasNext,
            canGoPrevious: queue.hasPrevious || elapsed > 0
        )
    }

    // MARK: - Sessao de audio e segundo plano

    private func activateAudioSession() {
        do {
            try AudioSessionManager.shared.activate()
        } catch {
            message = String(localized: "Não foi possível ativar o áudio em segundo plano: \(error.localizedDescription)")
        }
    }

    private func handleAudioSessionEvent(_ event: AudioSessionManager.Event) {
        guard player.hasItem else { return }

        switch event {
        case .interruptionBegan:
            wasPlayingBeforeInterruption = isPlaying
            pause()
        case .interruptionEnded(let shouldResume):
            if shouldResume && wasPlayingBeforeInterruption {
                play()
            }
            wasPlayingBeforeInterruption = false
        case .outputDeviceUnavailable:
            // Fone desconectado: pausa, como os apps de musica do sistema.
            pause()
        }
    }

    private func beginBackgroundTask() {
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
}
