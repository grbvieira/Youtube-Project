import MediaPlayer
import UIKit
import YouTubePiPCore

/// Tela bloqueada e Central de Controle: informacoes da faixa e comandos remotos.
@MainActor
final class NowPlayingController {
    /// Aba que controla a tela bloqueada no momento (so uma toca por vez).
    var owner: ObjectIdentifier?
    /// Velocidade atual, para a barra de tempo da tela bloqueada andar no ritmo certo.
    var playbackRate: Float = 1
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var isActive = false
    private var representedArtworkURL: URL?
    private var artworkTask: Task<Void, Never>?

    init() {
        registerCommands()
    }

    func update(
        track: MediaTrack,
        fallbackTitle: String,
        elapsedTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        canGoNext: Bool,
        canGoPrevious: Bool
    ) {
        isActive = true
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title.isEmpty ? fallbackTitle : track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyPlaybackDuration] = validTime(duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = validTime(elapsedTime)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = canGoNext
        commands.previousTrackCommand.isEnabled = canGoPrevious
        commands.changePlaybackPositionCommand.isEnabled = true

        loadArtwork(from: track.artworkURL)
    }

    func updatePlayback(elapsedTime: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard isActive, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = validTime(duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = validTime(elapsedTime)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        isActive = false
        representedArtworkURL = nil
        artworkTask?.cancel()
        artworkTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func registerCommands() {
        let commands = MPRemoteCommandCenter.shared()

        addTarget(to: commands.playCommand) { $0.perform($0.onPlay) }
        addTarget(to: commands.pauseCommand) { $0.perform($0.onPause) }
        addTarget(to: commands.togglePlayPauseCommand) { controller in
            controller.perform(
                MPNowPlayingInfoCenter.default().playbackState == .playing ? controller.onPause : controller.onPlay
            )
        }
        addTarget(to: commands.nextTrackCommand) { $0.perform($0.onNext) }
        addTarget(to: commands.previousTrackCommand) { $0.perform($0.onPrevious) }

        let positionTarget = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            return Self.onMain {
                guard let self, self.isActive, let onSeek = self.onSeek else { return .commandFailed }
                onSeek(position)
                return .success
            }
        }
        commandTargets.append((commands.changePlaybackPositionCommand, positionTarget))
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping @MainActor (NowPlayingController) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget { [weak self] _ in
            Self.onMain {
                guard let self else { return .commandFailed }
                return handler(self)
            }
        }
        commandTargets.append((command, target))
    }

    private func perform(_ action: (() -> Void)?) -> MPRemoteCommandHandlerStatus {
        guard isActive, let action else { return .commandFailed }
        action()
        return .success
    }

    /// Os comandos remotos chegam na main thread; o fallback evita um crash caso isso mude.
    private nonisolated static func onMain(
        _ body: @MainActor () -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return withoutActuallyEscaping(body) { body in
            nonisolated(unsafe) let body = body
            return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
        }
    }

    private func loadArtwork(from url: URL?) {
        guard representedArtworkURL != url else { return }
        representedArtworkURL = url
        artworkTask?.cancel()
        removeArtwork()

        guard let url else { return }

        artworkTask = Task { [weak self] in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data),
                let self,
                !Task.isCancelled,
                self.representedArtworkURL == url
            else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func removeArtwork() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info.removeValue(forKey: MPMediaItemPropertyArtwork)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func validTime(_ value: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : 0
    }
}
