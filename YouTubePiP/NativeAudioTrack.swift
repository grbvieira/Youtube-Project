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
    let currentTrack: NativeAudioTrack
    let currentTime: TimeInterval
    let playlistID: String?
    let queue: [NativeAudioTrack]
}
