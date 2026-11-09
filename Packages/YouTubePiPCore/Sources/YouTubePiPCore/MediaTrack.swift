import Foundation

/// Um video ou musica identificado pelo `videoID` do YouTube.
public struct MediaTrack: Identifiable, Equatable, Sendable {
    public let videoID: String
    /// URL tocavel pelo player nativo (normalmente um manifesto HLS). `nil` ate ser resolvida.
    public var streamURL: URL?
    public var title: String
    public var artist: String
    public var artworkURL: URL?
    public var duration: TimeInterval?

    public var id: String { videoID }

    public init(
        videoID: String,
        streamURL: URL? = nil,
        title: String = "",
        artist: String = "",
        artworkURL: URL? = nil,
        duration: TimeInterval? = nil
    ) {
        self.videoID = videoID
        self.streamURL = streamURL
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.duration = duration
    }

    /// Mantem os valores desta faixa e completa os que estiverem vazios com os de `other`.
    public func mergingMetadata(from other: MediaTrack) -> MediaTrack {
        MediaTrack(
            videoID: videoID,
            streamURL: streamURL ?? other.streamURL,
            title: title.isEmpty ? other.title : title,
            artist: artist.isEmpty ? other.artist : artist,
            artworkURL: artworkURL ?? other.artworkURL,
            duration: duration ?? other.duration
        )
    }
}

/// O que a pagina estava tocando no momento da captura.
public struct PageMediaSnapshot: Equatable, Sendable {
    /// Faixa atual, sem URL de stream: ela sempre e resolvida pelo `videoID`.
    public let currentTrack: MediaTrack
    /// URL de audio observada na pagina. So deve ser usada se a resolucao pelo `videoID` falhar,
    /// pois pode pertencer a faixa pre-carregada pelo YouTube Music.
    public let fallbackStreamURL: URL?
    public let currentTime: TimeInterval
    public let playlistID: String?
    /// Fila exibida na pagina (YouTube Music), na ordem em que aparece.
    public let queue: [MediaTrack]

    public init(
        currentTrack: MediaTrack,
        fallbackStreamURL: URL?,
        currentTime: TimeInterval,
        playlistID: String?,
        queue: [MediaTrack]
    ) {
        self.currentTrack = currentTrack
        self.fallbackStreamURL = fallbackStreamURL
        self.currentTime = currentTime
        self.playlistID = playlistID
        self.queue = queue
    }
}
