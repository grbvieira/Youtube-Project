import Foundation

struct NativeAudioTrack: Identifiable, Sendable {
    let videoID: String
    var streamURL: URL?
    var title: String
    var artist: String
    var artworkURL: URL?
    var duration: TimeInterval?

    var id: String { videoID }

    func mergingMetadata(from other: NativeAudioTrack) -> NativeAudioTrack {
        NativeAudioTrack(
            videoID: videoID,
            streamURL: streamURL ?? other.streamURL,
            title: title.isEmpty ? other.title : title,
            artist: artist.isEmpty ? other.artist : artist,
            artworkURL: artworkURL ?? other.artworkURL,
            duration: duration ?? other.duration
        )
    }
}

struct NativeAudioCapture {
    /// Faixa atual, sem URL de stream: ela sempre e resolvida pelo `videoID`.
    let currentTrack: NativeAudioTrack
    /// URL de audio observada na pagina. So e usada se a resolucao pelo `videoID` falhar,
    /// pois pode pertencer a faixa pre-carregada pelo YouTube Music.
    let fallbackStreamURL: URL?
    let currentTime: TimeInterval
    let playlistID: String?
    let queue: [NativeAudioTrack]
}
