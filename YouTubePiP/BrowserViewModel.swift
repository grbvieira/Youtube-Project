import AVFoundation
import Foundation
import Combine
import KSPlayer
import WebKit

final class BrowserViewModel: ObservableObject {
    let service: MediaService

    weak var webView: WKWebView?

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pipMessage: String?
    @Published var mediaDiagnostics: String?
    @Published private(set) var hasNativeAudioCandidate = false
    @Published private(set) var isNativeAudioActive = false
    @Published private(set) var isNativeAudioPlaying = false
    @Published private(set) var pictureInPictureRequested = false

    private let audioResolver = YouTubeAudioResolver()
    private var nativeAudioCapture: NativeAudioCapture?
    private var nativePlayer: KSMEPlayer?
    private var isPreparingNativeAudio = false
    private var nativeQueue: [NativeAudioTrack] = []
    private var currentQueueIndex = 0
    private var queueGeneration = UUID()
    private var queueTask: Task<Void, Never>?
    private var nowPlayingController: NowPlayingController?

    init(service: MediaService) {
        self.service = service

        if service.audioOnly {
            let controller = NowPlayingController()
            nowPlayingController = controller
            controller.onPlay = { [weak self] in self?.resumeNativeAudioPlayback() }
            controller.onPause = { [weak self] in self?.pauseNativeAudioPlayback() }
            controller.onNext = { [weak self] in self?.playNextTrack() }
            controller.onPrevious = { [weak self] in self?.playPreviousTrack() }
            controller.onSeek = { [weak self] time in self?.seekNativeAudio(to: time) }
        }
    }

    var serviceName: String { service.rawValue }
    var homeURL: URL { service.homeURL }
    var audioOnly: Bool { service.audioOnly }
    var supportsPictureInPicture: Bool { true }

    func attach(_ webView: WKWebView) {
        self.webView = webView

        if webView.url == nil {
            loadHome()
        }
    }

    func loadHome() {
        stopNativeAudioPlayback(resumeWebPlayback: false)
        errorMessage = nil
        pipMessage = nil
        mediaDiagnostics = nil
        webView?.load(URLRequest(url: homeURL))
    }

    func reload() {
        stopNativeAudioPlayback(resumeWebPlayback: false)
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

    func startPictureInPicture() {
        pictureInPictureRequested = true
        runPictureInPictureScript(shouldShowResult: true)
    }

    func prepareForBackgroundPlayback() {
        if nativePlayer != nil {
            activateAudioSession()
            nativePlayer?.enterBackground()
            return
        }

        if audioOnly {
            if pictureInPictureRequested {
                exitPictureInPicture()
            }
            captureCurrentMedia(showDiagnostics: false, startNativePlayback: true)
            return
        }

        if pictureInPictureRequested {
            return
        }

        prepareVideoElements()
        webView?.evaluateJavaScript(Self.prepareForBackgroundPlaybackScript)
    }

    private func exitPictureInPicture() {
        webView?.evaluateJavaScript(Self.exitPictureInPictureScript)
        pictureInPictureRequested = false
    }

    func prepareVideoElements() {
        webView?.evaluateJavaScript(Self.prepareVideoElementsScript)
    }

    func prepareAudioOnlyMode() {
        webView?.evaluateJavaScript(Self.audioOnlyScript)
    }

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
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPreparingNativeAudio = false

                if let error {
                    if startNativePlayback {
                        self.fallbackToWebBackgroundPlayback()
                    } else {
                        self.pipMessage = "Nao foi possivel inspecionar a midia: \(error.localizedDescription)"
                    }
                    return
                }

                guard
                    let json = result as? String,
                    let data = json.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let formattedData = try? JSONSerialization.data(
                        withJSONObject: object,
                        options: [.prettyPrinted, .sortedKeys]
                    ),
                    let report = String(data: formattedData, encoding: .utf8)
                else {
                    if startNativePlayback {
                        self.fallbackToWebBackgroundPlayback()
                    } else {
                        self.pipMessage = "A pagina retornou um diagnostico de midia invalido."
                    }
                    return
                }

                self.pipMessage = nil
                self.nativeAudioCapture = Self.nativeAudioCapture(from: object)
                self.hasNativeAudioCandidate = self.nativeAudioCapture != nil

                if showDiagnostics {
                    self.mediaDiagnostics = report
                }

                if startNativePlayback {
                    if self.nativeAudioCapture != nil {
                        self.startNativeAudioPlayback()
                    } else {
                        self.fallbackToWebBackgroundPlayback()
                    }
                }
            }
        }
    }

    func dismissMediaDiagnostics() {
        mediaDiagnostics = nil
    }

    func startNativeAudioPlayback() {
        guard audioOnly, let capture = nativeAudioCapture else {
            pipMessage = "Nenhuma URL direta de audio foi encontrada. Inicie a musica e inspecione novamente."
            return
        }

        resetNativeQueue()
        configureQueue(from: capture)
        activateAudioSession()
        playTrack(at: currentQueueIndex, startTime: capture.currentTime)
        populateQueueIfNeeded(capture.playlistID)
        prefetchUpcomingTracks()
    }

    private func configureQueue(from capture: NativeAudioCapture) {
        var seenIDs = Set<String>()
        nativeQueue = capture.queue.filter { seenIDs.insert($0.videoID).inserted }

        if let index = nativeQueue.firstIndex(where: { $0.videoID == capture.currentTrack.videoID }) {
            nativeQueue[index] = capture.currentTrack.mergingMetadata(from: nativeQueue[index])
            currentQueueIndex = index
        } else {
            nativeQueue.insert(capture.currentTrack, at: 0)
            currentQueueIndex = 0
        }
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
        shutdownNativePlayer()
        activateAudioSession()

        let options = KSOptions()
        options.videoDisable = true
        options.startPlayTime = max(startTime, 0)
        options.registerRemoteControll = false
        options.userAgent = Self.mobileUserAgent
        options.appendHeader([
            "Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/"
        ])

        let player = KSMEPlayer(url: streamURL, options: options)
        player.delegate = self
        nativePlayer = player
        isNativeAudioActive = true
        isNativeAudioPlaying = false
        pipMessage = "Preparando audio no KSPlayer..."
        updateNowPlaying(isPlaying: false, elapsedTime: startTime)
        player.prepareToPlay()
    }

    func toggleNativeAudioPlayback() {
        guard let player = nativePlayer else { return }

        if player.isPlaying {
            pauseNativeAudioPlayback()
        } else {
            resumeNativeAudioPlayback()
        }
    }

    private func resumeNativeAudioPlayback() {
        guard let player = nativePlayer else { return }
        activateAudioSession()
        player.play()
        isNativeAudioPlaying = true
        updateNowPlaying(isPlaying: true)
    }

    private func pauseNativeAudioPlayback() {
        guard let player = nativePlayer else { return }
        player.pause()
        isNativeAudioPlaying = false
        updateNowPlaying(isPlaying: false)
    }

    private func seekNativeAudio(to time: TimeInterval) {
        guard let player = nativePlayer else { return }
        let target = max(0, min(time, player.duration.isFinite ? player.duration : time))
        player.seek(time: target) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateNowPlaying(isPlaying: player.isPlaying, elapsedTime: target)
            }
        }
    }

    private func playNextTrack() {
        guard currentQueueIndex + 1 < nativeQueue.count else { return }
        playTrack(at: currentQueueIndex + 1)
        prefetchUpcomingTracks()
    }

    private func playPreviousTrack() {
        guard let player = nativePlayer else { return }

        if player.currentPlaybackTime > 5 || currentQueueIndex == 0 {
            seekNativeAudio(to: 0)
        } else {
            playTrack(at: currentQueueIndex - 1)
            prefetchUpcomingTracks()
        }
    }

    func stopNativeAudioPlayback(resumeWebPlayback: Bool = true) {
        let playbackTime = nativePlayer?.currentPlaybackTime

        resetNativeQueue()

        guard resumeWebPlayback, let playbackTime, playbackTime.isFinite else { return }
        resumeWebMedia(at: playbackTime)
    }

    private func shutdownNativePlayer() {
        nativePlayer?.delegate = nil
        nativePlayer?.shutdown()
        nativePlayer = nil
        isNativeAudioActive = false
        isNativeAudioPlaying = false
    }

    private func resetNativeQueue() {
        queueGeneration = UUID()
        queueTask?.cancel()
        queueTask = nil
        shutdownNativePlayer()
        nativeQueue = []
        currentQueueIndex = 0
        nowPlayingController?.clear()
    }

    private func finishNativeQueue() {
        shutdownNativePlayer()
        nowPlayingController?.clear()
    }

    private func resolveAndPlayTrack(at index: Int, startTime: TimeInterval) {
        guard nativeQueue.indices.contains(index) else { return }
        let generation = queueGeneration
        let track = nativeQueue[index]
        pipMessage = "Preparando \(track.title.isEmpty ? "a proxima faixa" : track.title)..."

        queueTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await audioResolver.resolve(track)
                await MainActor.run {
                    guard self.queueGeneration == generation, self.nativeQueue.indices.contains(index) else { return }
                    self.nativeQueue[index] = resolved
                    self.playTrack(at: index, startTime: startTime)
                    self.prefetchUpcomingTracks()
                }
            } catch {
                await MainActor.run {
                    guard self.queueGeneration == generation else { return }
                    self.pipMessage = "Nao foi possivel preparar a faixa: \(error.localizedDescription)"
                    if index + 1 < self.nativeQueue.count {
                        self.playTrack(at: index + 1)
                    } else {
                        self.finishNativeQueue()
                    }
                }
            }
        }
    }

    private func populateQueueIfNeeded(_ playlistID: String?) {
        guard nativeQueue.count <= 1 else { return }
        let generation = queueGeneration
        let currentTrack = nativeQueue[currentQueueIndex]

        Task { [weak self] in
            guard let self else { return }
            do {
                let playlistTracks = try await audioResolver.queueTracks(
                    currentTrack: currentTrack,
                    playlistID: playlistID
                )
                await MainActor.run {
                    guard self.queueGeneration == generation else { return }
                    self.mergePlaylistTracks(playlistTracks, currentTrack: currentTrack)
                    self.prefetchUpcomingTracks()
                }
            } catch {
                // The DOM queue remains usable when a private or generated playlist cannot be fetched.
            }
        }
    }

    private func mergePlaylistTracks(_ playlistTracks: [NativeAudioTrack], currentTrack: NativeAudioTrack) {
        guard !playlistTracks.isEmpty else { return }

        var merged = playlistTracks
        if let index = merged.firstIndex(where: { $0.videoID == currentTrack.videoID }) {
            merged[index] = currentTrack.mergingMetadata(from: merged[index])
            nativeQueue = merged
            currentQueueIndex = index
        } else {
            nativeQueue = [currentTrack] + merged.filter { $0.videoID != currentTrack.videoID }
            currentQueueIndex = 0
        }
        updateNowPlaying(isPlaying: nativePlayer?.isPlaying == true)
    }

    private func prefetchUpcomingTracks() {
        guard !nativeQueue.isEmpty else { return }
        let generation = queueGeneration
        let upperBound = min(nativeQueue.count, currentQueueIndex + 6)
        let indexes = ((currentQueueIndex + 1)..<upperBound).filter {
            nativeQueue[$0].streamURL == nil
        }
        guard !indexes.isEmpty else {
            updateNowPlaying(isPlaying: nativePlayer?.isPlaying == true)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            for index in indexes {
                if Task.isCancelled { return }
                let track = await MainActor.run { () -> NativeAudioTrack? in
                    guard self.queueGeneration == generation, self.nativeQueue.indices.contains(index) else {
                        return nil
                    }
                    return self.nativeQueue[index]
                }
                guard let track else { return }
                do {
                    let resolved = try await audioResolver.resolve(track)
                    await MainActor.run {
                        guard self.queueGeneration == generation, self.nativeQueue.indices.contains(index) else { return }
                        self.nativeQueue[index] = resolved
                        self.updateNowPlaying(isPlaying: self.nativePlayer?.isPlaying == true)
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func updateNowPlaying(isPlaying: Bool, elapsedTime: TimeInterval? = nil) {
        guard nativeQueue.indices.contains(currentQueueIndex) else { return }
        let track = nativeQueue[currentQueueIndex]
        let elapsed = elapsedTime ?? nativePlayer?.currentPlaybackTime ?? 0
        let duration = nativePlayer?.duration ?? track.duration ?? 0
        nowPlayingController?.update(
            track: track,
            elapsedTime: elapsed,
            duration: duration,
            isPlaying: isPlaying,
            canGoNext: currentQueueIndex + 1 < nativeQueue.count,
            canGoPrevious: currentQueueIndex > 0 || elapsed > 0
        )
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            pipMessage = "Nao foi possivel ativar o audio em segundo plano: \(error.localizedDescription)"
        }
    }

    private func fallbackToWebBackgroundPlayback() {
        prepareAudioOnlyMode()
        webView?.evaluateJavaScript(Self.prepareForBackgroundPlaybackScript)
    }

    private func pauseWebMedia() {
        webView?.evaluateJavaScript(Self.pauseWebMediaScript)
    }

    private func resumeWebMedia(at seconds: Double) {
        let script = """
        (() => {
            const media = Array.from(document.querySelectorAll('audio, video'))
                .find((item) => item.readyState > 0);
            if (!media) return 'missing';
            media.currentTime = \(seconds);
            media.play().catch(() => {});
            return 'playing';
        })();
        """
        webView?.evaluateJavaScript(script)
    }

    private static func nativeAudioCapture(from object: Any) -> NativeAudioCapture? {
        guard let report = object as? [String: Any] else { return nil }

        let activeElement = report["activeElement"] as? [String: Any]
        let currentTime = activeElement?["currentTime"] as? Double ?? 0
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
                let currentTrack = NativeAudioTrack(
                    videoID: currentVideoID,
                    streamURL: url,
                    title: (metadata["title"] as? String).nonEmpty ?? "YouTube Music",
                    artist: (metadata["artist"] as? String).nonEmpty ?? "",
                    artworkURL: (metadata["artworkURL"] as? String).flatMap(URL.init(string:)),
                    duration: duration
                )
                let queue = nativeQueue(from: report["queueItems"])
                return NativeAudioCapture(
                    currentTrack: currentTrack,
                    currentTime: currentTime,
                    playlistID: playlistID,
                    queue: queue
                )
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

    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private func runPictureInPictureScript(shouldShowResult: Bool) {
        guard let webView else {
            if shouldShowResult {
                pipMessage = "A pagina ainda nao esta pronta para iniciar o PiP."
            }
            return
        }

        pipMessage = shouldShowResult ? "Tentando iniciar Picture in Picture..." : nil
        webView.evaluateJavaScript(Self.startPictureInPictureScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, shouldShowResult else { return }

                if let error {
                    self.pictureInPictureRequested = false
                    self.pipMessage = "Nao foi possivel iniciar o PiP: \(error.localizedDescription)"
                    return
                }

                let message = (result as? String) ?? "Solicitacao de PiP enviada ao player."
                self.pictureInPictureRequested = message.contains("solicitado") || message.contains("ja esta ativo")
                self.pipMessage = message
            }
        }
    }

    static let prepareVideoElementsScript = """
    (() => {
        const prepare = () => {
            document.querySelectorAll('video').forEach((video) => {
                video.setAttribute('playsinline', '');
                video.setAttribute('webkit-playsinline', '');
                video.disablePictureInPicture = false;
                video.controls = true;
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
        const playerBar = document.querySelector('ytmusic-player-bar');
        const currentVideoID = page.searchParams.get('v') || '';
        const metadata = {
            videoID: currentVideoID,
            playlistID: page.searchParams.get('list') || '',
            title: textFrom(playerBar, ['.title', '.song-title', 'yt-formatted-string.title'])
                || cleanText(document.title.replace(/\s*-\s*YouTube Music\s*$/, '')),
            artist: textFrom(playerBar, ['.byline', '.subtitle', '.secondary-flex-columns']),
            artworkURL: imageFrom(playerBar)
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

    private static let prepareForBackgroundPlaybackScript = """
    (() => {
        const media = Array.from(document.querySelectorAll('audio, video'))
            .filter((item) => item.readyState > 0)
            .sort((left, right) => Number(left.paused) - Number(right.paused))[0];

        if (!media) {
            return 'Nenhuma midia pronta para continuar em segundo plano.';
        }

        media.setAttribute('playsinline', '');
        if (media.paused) {
            media.play().catch(() => {});
        }

        return 'Reproducao preparada para segundo plano.';
    })();
    """

    private static let pauseWebMediaScript = """
    (() => {
        const media = Array.from(document.querySelectorAll('audio, video'));
        media.forEach((item) => item.pause());
        return 'paused';
    })();
    """

    private static let exitPictureInPictureScript = """
    (() => {
        try {
            if (document.pictureInPictureElement && typeof document.exitPictureInPicture === 'function') {
                const request = document.exitPictureInPicture();
                if (request && typeof request.catch === 'function') {
                    request.catch(() => {});
                }
            }

            document.querySelectorAll('video').forEach((video) => {
                if (video.webkitPresentationMode === 'picture-in-picture' && typeof video.webkitSetPresentationMode === 'function') {
                    video.webkitSetPresentationMode('inline');
                }
            });
        } catch (error) {}

        return 'Picture in Picture ocultado para o YouTube Music.';
    })();
    """

    private static let startPictureInPictureScript = """
    (() => {
        const videos = Array.from(document.querySelectorAll('video'));
        const video = videos.find((item) => !item.paused && item.readyState > 0) || videos.find((item) => item.readyState > 0) || videos[0];

        if (!video) {
            return 'Nenhum video foi encontrado na pagina. Abra e toque em um video antes de iniciar o PiP.';
        }

        video.style.opacity = '';
        video.style.pointerEvents = '';
        video.style.position = '';
        video.style.width = '';
        video.style.height = '';
        video.style.left = '';
        video.style.top = '';
        video.setAttribute('playsinline', '');
        video.setAttribute('webkit-playsinline', '');
        video.disablePictureInPicture = false;
        video.controls = true;

        try {
            if (document.pictureInPictureElement) {
                return 'O Picture in Picture ja esta ativo.';
            }

            if (video.webkitSupportsPresentationMode && typeof video.webkitSetPresentationMode === 'function') {
                video.webkitSetPresentationMode('picture-in-picture');
                return 'Picture in Picture solicitado ao player.';
            }

            if (document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function') {
                const request = video.requestPictureInPicture();
                if (request && typeof request.catch === 'function') {
                    request.catch(() => {});
                }
                return 'Picture in Picture solicitado ao player.';
            }

            return 'Este player do YouTube nao liberou Picture in Picture nesta WebView.';
        } catch (error) {
            return 'O YouTube ou o iOS recusou o Picture in Picture para este video.';
        }
    })();
    """
}

extension BrowserViewModel: MediaPlayerDelegate {
    func readyToPlay(player: some MediaPlayerProtocol) {
        guard let nativePlayer, (player as AnyObject) === nativePlayer else { return }

        pauseWebMedia()
        player.play()
        isNativeAudioActive = true
        isNativeAudioPlaying = true
        pipMessage = nil
        updateNowPlaying(isPlaying: true)
        prefetchUpcomingTracks()
    }

    func changeLoadState(player: some MediaPlayerProtocol) {
        guard let nativePlayer, (player as AnyObject) === nativePlayer else { return }
        isNativeAudioPlaying = player.isPlaying
        nowPlayingController?.updatePlayback(
            elapsedTime: player.currentPlaybackTime,
            duration: player.duration,
            isPlaying: player.isPlaying
        )
    }

    func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {}

    func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}

    func finish(player: some MediaPlayerProtocol, error: Error?) {
        guard let nativePlayer, (player as AnyObject) === nativePlayer else { return }

        shutdownNativePlayer()
        if currentQueueIndex + 1 < nativeQueue.count {
            if let error {
                pipMessage = "A faixa atual falhou; tentando a proxima: \(error.localizedDescription)"
            }
            playNextTrack()
        } else {
            nowPlayingController?.clear()
            if let error {
                pipMessage = "Nao foi possivel tocar no KSPlayer: \(error.localizedDescription)."
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
