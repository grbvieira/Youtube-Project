import Foundation

/// Algo que foi tocado, com a posicao em que parou.
public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let videoID: String
    public var title: String
    public var artist: String
    public var artworkURL: URL?
    public var position: TimeInterval
    public var duration: TimeInterval?
    public var isMusic: Bool
    public var updatedAt: Date

    public var id: String { videoID }

    /// Fracao assistida (0...1), quando a duracao e conhecida.
    public var progress: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    public var track: MediaTrack {
        MediaTrack(videoID: videoID, title: title, artist: artist, artworkURL: artworkURL, duration: duration)
    }
}

/// Historico de reproducao, do mais recente para o mais antigo.
public struct PlaybackHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [HistoryEntry]

    public static let limit = 200
    /// Abaixo disso nao vale retomar (mal comecou).
    public static let minimumResumePosition: TimeInterval = 30
    /// Perto do fim conta como terminado.
    public static let finishedMargin: TimeInterval = 30
    /// Musicas curtas recomecam do inicio; so retoma faixas longas (mixes, podcasts).
    public static let minimumMusicResumeDuration: TimeInterval = 10 * 60

    public init(entries: [HistoryEntry] = []) {
        self.entries = entries
    }

    /// Registra (ou atualiza) a posicao de uma faixa e a coloca no topo.
    public mutating func record(
        _ track: MediaTrack,
        position: TimeInterval,
        duration: TimeInterval?,
        isMusic: Bool,
        at date: Date
    ) {
        let previous = entries.first(where: { $0.videoID == track.videoID })
        entries.removeAll { $0.videoID == track.videoID }

        let validDuration = duration.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        let entry = HistoryEntry(
            videoID: track.videoID,
            title: track.title.isEmpty ? (previous?.title ?? "") : track.title,
            artist: track.artist.isEmpty ? (previous?.artist ?? "") : track.artist,
            artworkURL: track.artworkURL ?? previous?.artworkURL,
            position: position.isFinite ? max(0, position) : 0,
            duration: validDuration ?? track.duration ?? previous?.duration,
            isMusic: isMusic,
            updatedAt: date
        )
        entries.insert(entry, at: 0)

        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    public mutating func remove(videoID: String) {
        entries.removeAll { $0.videoID == videoID }
    }

    public mutating func clear() {
        entries.removeAll()
    }

    /// Onde retomar este video, ou `nil` para comecar do inicio.
    public func resumePosition(for videoID: String) -> TimeInterval? {
        guard let entry = entries.first(where: { $0.videoID == videoID }) else { return nil }
        guard entry.position >= Self.minimumResumePosition else { return nil }

        if let duration = entry.duration {
            guard entry.position < duration - Self.finishedMargin else { return nil }
            if entry.isMusic, duration < Self.minimumMusicResumeDuration { return nil }
        } else if entry.isMusic {
            return nil
        }
        return entry.position
    }
}
