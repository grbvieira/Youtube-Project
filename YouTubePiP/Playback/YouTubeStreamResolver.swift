import Foundation
import YouTubeKit
import YouTubePiPCore

/// Descobre a URL tocavel (manifesto HLS) e a fila de um video usando o YouTubeKit.
actor YouTubeStreamResolver {
    // `YouTubeModel` nao e `Sendable`; como so guarda configuracao (idioma, cookies),
    // cada requisicao cria o seu em vez de compartilhar uma instancia entre threads.

    func resolve(_ track: MediaTrack) async throws -> MediaTrack {
        let response = try await YTVideo(videoId: track.videoID)
            .fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: YouTubeModel())

        let formats = response.downloadFormats.compactMap { $0 as? AudioOnlyFormat }
        let audioFormat = preferredFormat(in: formats)
        let fallbackFormat = response.defaultFormats.first { $0.url != nil }
        // O manifesto HLS e o formato nativo do AVPlayer (video H.264 + audio AAC, adaptativo).
        guard let streamURL = response.videoInfos.streamingURL ?? audioFormat?.url ?? fallbackFormat?.url else {
            throw StreamResolverError.missingStream
        }

        let info = response.videoInfos
        let resolved = MediaTrack(
            videoID: track.videoID,
            streamURL: streamURL,
            title: info.title ?? "",
            artist: info.channel?.name ?? "",
            artworkURL: info.thumbnails.last?.url,
            duration: (audioFormat?.contentDuration ?? fallbackFormat?.contentDuration)
                .map { TimeInterval($0) / 1_000 }
        )
        return track.mergingMetadata(from: resolved)
    }

    func queueTracks(currentTrack: MediaTrack, playlistID: String?) async throws -> [MediaTrack] {
        if let playlistID, !playlistID.isEmpty {
            let browseID = playlistID.hasPrefix("VL") ? playlistID : "VL" + playlistID
            if let response = try? await YTPlaylist(playlistId: browseID)
                .fetchVideosThrowing(youtubeModel: YouTubeModel())
            {
                let tracks = response.results.map(makeTrack)
                if tracks.contains(where: { $0.videoID == currentTrack.videoID }) {
                    return tracks
                }
            }
        }

        let response = try await YTVideo(videoId: currentTrack.videoID)
            .fetchMoreInfosThrowing(youtubeModel: YouTubeModel())
        let recommendations = response.recommendedVideos
            .compactMap { $0 as? YTVideo }
            .prefix(20)
            .map(makeTrack)
        return [currentTrack] + recommendations.filter { $0.videoID != currentTrack.videoID }
    }

    private func makeTrack(_ video: YTVideo) -> MediaTrack {
        MediaTrack(
            videoID: video.videoId,
            streamURL: nil,
            title: video.title ?? "",
            artist: video.channel?.name ?? "",
            artworkURL: video.thumbnails.last?.url,
            duration: video.timeLengthSeconds.map(TimeInterval.init)
        )
    }

    private func preferredFormat(in formats: [AudioOnlyFormat]) -> AudioOnlyFormat? {
        let defaultLanguageFormats = formats.filter {
            $0.formatLocaleInfos?.isDefaultAudioFormat != false
        }
        let candidates = defaultLanguageFormats.isEmpty ? formats : defaultLanguageFormats

        return candidates
            .filter { $0.url != nil }
            .max { ($0.averageBitrate ?? 0) < ($1.averageBitrate ?? 0) }
    }
}

private enum StreamResolverError: LocalizedError {
    case missingStream

    var errorDescription: String? {
        String(localized: "Nenhum stream tocável foi encontrado para este vídeo.")
    }
}
