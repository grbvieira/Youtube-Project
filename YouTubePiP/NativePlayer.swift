import AVFoundation
import AVKit
import UIKit

/// View cuja camada e um `AVPlayerLayer`; necessaria para exibir video e para o PiP.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Player nativo baseado em `AVPlayer`.
///
/// Diferente da WebView, o `AVPlayer` continua tocando em segundo plano, entra em
/// Picture in Picture automaticamente ao sair do app e se integra aos controles
/// da tela bloqueada.
@MainActor
final class NativePlayer: NSObject {
    enum Event {
        case ready
        case playbackStateChanged
        case timeChanged
        case finished
        case failed(Error?)
        case pictureInPictureChanged
    }

    var onEvent: ((Event) -> Void)?

    let videoView = PlayerLayerView()

    private let player = AVPlayer()
    private var pipController: AVPictureInPictureController?
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?
    private var itemNotifications: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var didReportReady = false
    private var isVideoDetachedForBackground = false
    private var backgroundDetachTask: Task<Void, Never>?

    private(set) var hasItem = false
    private(set) var isAudioOnly = true
    private(set) var isPictureInPictureActive = false

    var isPlaying: Bool { player.timeControlStatus != .paused }
    var isPictureInPicturePossible: Bool { pipController?.isPictureInPicturePossible == true }

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    var duration: TimeInterval {
        let seconds = player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    override init() {
        super.init()
        player.allowsExternalPlayback = true
        videoView.playerLayer.player = player
        // Ao sair do app tocando, o AVPlayer continua em vez de pausar (iOS 15+).
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.onEvent?(.playbackStateChanged) }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.timeChanged) }
        }

        if AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(playerLayer: videoView.playerLayer)
            controller?.delegate = self
            // Entra em PiP sozinho quando o usuario sai do app com o video tocando.
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            pipController = controller
        }
    }

    /// Carrega e toca a URL. Em modo audio limita a qualidade, ja que o video nao e exibido.
    func load(url: URL, startTime: TimeInterval, audioOnly: Bool) {
        stop()

        isAudioOnly = audioOnly
        // Em modo audio a camada fica desligada: nada para exibir e o audio segue em segundo plano.
        videoView.playerLayer.player = audioOnly ? nil : player
        isVideoDetachedForBackground = false
        didReportReady = false
        hasItem = true

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = audioOnly ? 30 : 0
        if audioOnly {
            // As variantes de 360p usam AAC-LC; abaixo disso o audio e HE-AAC de baixa taxa.
            item.preferredPeakBitRate = 700_000
            item.preferredMaximumResolution = CGSize(width: 640, height: 360)
        }

        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error
            Task { @MainActor [weak self] in
                self?.handleItemStatus(status, error: error, startTime: startTime)
            }
        }

        let center = NotificationCenter.default
        itemNotifications = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onEvent?(.finished) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                MainActor.assumeIsolated { self?.onEvent?(.failed(error)) }
            }
        ]

        player.replaceCurrentItem(with: item)
        player.play()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onEvent?(.timeChanged) }
        }
    }

    func stop() {
        if isPictureInPictureActive {
            pipController?.stopPictureInPicture()
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        itemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotifications = []
        hasItem = false
        didReportReady = false
    }

    func startPictureInPicture() -> Bool {
        guard let pipController, pipController.isPictureInPicturePossible else { return false }
        pipController.startPictureInPicture()
        return true
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    /// Sem PiP, o iOS pausa um `AVPlayer` ligado a uma camada de video visivel.
    /// Desligar a camada mantem o audio tocando em segundo plano. Espera um pouco porque
    /// o PiP automatico comeca durante a transicao e precisa da camada ligada.
    func didEnterBackground() {
        guard hasItem, !isAudioOnly else { return }
        backgroundDetachTask?.cancel()
        backgroundDetachTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled, self.hasItem, !self.isPictureInPictureActive else { return }
            let wasPlaying = self.isPlaying
            self.videoView.playerLayer.player = nil
            self.isVideoDetachedForBackground = true
            if wasPlaying { self.player.play() }
        }
    }

    func willEnterForeground() {
        backgroundDetachTask?.cancel()
        backgroundDetachTask = nil
        guard isVideoDetachedForBackground else { return }
        videoView.playerLayer.player = player
        isVideoDetachedForBackground = false
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: Error?, startTime: TimeInterval) {
        switch status {
        case .readyToPlay:
            guard !didReportReady else { return }
            didReportReady = true
            if startTime > 1 {
                seek(to: startTime)
            }
            player.play()
            onEvent?(.ready)
        case .failed:
            onEvent?(.failed(error))
        default:
            break
        }
    }
}

extension NativePlayer: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isPictureInPictureActive = true
            self.onEvent?(.pictureInPictureChanged)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isPictureInPictureActive = false
            self.onEvent?(.pictureInPictureChanged)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isPictureInPictureActive = false
            self.onEvent?(.pictureInPictureChanged)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
