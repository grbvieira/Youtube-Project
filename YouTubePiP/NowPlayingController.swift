import MediaPlayer
import UIKit

final class NowPlayingController {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var isActive = false
    private var representedArtworkURL: URL?

    init() {
        registerCommands()
    }

    deinit {
        commandTargets.forEach { $0.command.removeTarget($0.target) }
    }

    func update(
        track: NativeAudioTrack,
        elapsedTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        canGoNext: Bool,
        canGoPrevious: Bool
    ) {
        isActive = true
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title.isEmpty ? "YouTube Music" : track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyPlaybackDuration] = validTime(duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = validTime(elapsedTime)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
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
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        isActive = false
        representedArtworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func registerCommands() {
        let commands = MPRemoteCommandCenter.shared()

        addTarget(to: commands.playCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.perform(self.onPlay)
        }
        addTarget(to: commands.pauseCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.perform(self.onPause)
        }
        addTarget(to: commands.togglePlayPauseCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.perform(MPNowPlayingInfoCenter.default().playbackState == .playing ? self.onPause : self.onPlay)
        }
        addTarget(to: commands.nextTrackCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.perform(self.onNext)
        }
        addTarget(to: commands.previousTrackCommand) { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.perform(self.onPrevious)
        }
        addTarget(to: commands.changePlaybackPositionCommand) { [weak self] event in
            guard
                let self,
                self.isActive,
                let event = event as? MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }
            DispatchQueue.main.async { self.onSeek?(event.positionTime) }
            return .success
        }
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func perform(_ action: (() -> Void)?) -> MPRemoteCommandHandlerStatus {
        guard isActive, let action else { return .commandFailed }
        DispatchQueue.main.async(execute: action)
        return .success
    }

    private func loadArtwork(from url: URL?) {
        guard representedArtworkURL != url else { return }
        representedArtworkURL = url

        guard let url else {
            removeArtwork()
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let self,
                self.representedArtworkURL == url,
                let data,
                let image = UIImage(data: data)
            else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                guard self.representedArtworkURL == url else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
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
