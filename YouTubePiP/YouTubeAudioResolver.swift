import Foundation
import YouTubeKit

actor YouTubeAudioResolver {
    // `YouTubeModel` nao e `Sendable`; como so guarda configuracao (idioma, cookies),
    // cada requisicao cria o seu em vez de compartilhar uma instancia entre threads.

    func resolve(_ track: NativeAudioTrack) async throws -> NativeAudioTrack {
        let response = try await YTVideo(videoId: track.videoID)
            .fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: YouTubeModel())

        let formats = response.downloadFormats.compactMap { $0 as? AudioOnlyFormat }
        let audioFormat = preferredFormat(in: formats)
        let fallbackFormat = response.defaultFormats.first { $0.url != nil }
        // O manifesto HLS e o formato nativo do AVPlayer (video H.264 + audio AAC, adaptativo).
        guard let streamURL = response.videoInfos.streamingURL ?? audioFormat?.url ?? fallbackFormat?.url else {
            throw AudioResolverError.missingAudioStream
        }

        let info = response.videoInfos
        let resolved = NativeAudioTrack(
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

    func queueTracks(currentTrack: NativeAudioTrack, playlistID: String?) async throws -> [NativeAudioTrack] {
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

    private func makeTrack(_ video: YTVideo) -> NativeAudioTrack {
        NativeAudioTrack(
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

private enum AudioResolverError: LocalizedError {
    case missingAudioStream

    var errorDescription: String? {
        "Nenhum fluxo de audio foi encontrado para esta faixa."
    }
}
