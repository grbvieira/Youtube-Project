import Foundation
import YouTubeKit
import YouTubePiPCore

/// Item de uma lista nativa (busca, playlist).
enum CatalogItem: Identifiable, Hashable, Sendable {
    case video(CatalogVideo)
    case channel(CatalogChannel)
    case playlist(CatalogPlaylist)

    var id: String {
        switch self {
        case .video(let video): "v:" + video.track.videoID
        case .channel(let channel): "c:" + channel.id
        case .playlist(let playlist): "p:" + playlist.id
        }
    }
}

struct CatalogVideo: Hashable, Sendable {
    let track: MediaTrack
    /// "3:55", ou `nil` para transmissoes ao vivo.
    let durationText: String?
    /// "1,2 mi de visualizações · há 3 anos".
    let details: String?
}

struct CatalogChannel: Hashable, Sendable {
    let id: String
    let name: String
    let subscribers: String?
    let thumbnailURL: URL?
}

struct CatalogPlaylist: Hashable, Sendable {
    let id: String
    let title: String
    let owner: String?
    let videoCount: String?
    let thumbnailURL: URL?
}

struct CatalogPage: Sendable {
    let items: [CatalogItem]
    /// Token para buscar a proxima pagina, se houver.
    let continuation: String?
}

struct PlaylistPage: Sendable {
    let title: String
    let owner: String?
    let tracks: [MediaTrack]
    let continuation: String?
}

/// Busca e playlists pela API interna do YouTube (YouTubeKit), para as telas nativas.
actor YouTubeCatalog {
    static let shared = YouTubeCatalog()

    // `YouTubeModel` nao e `Sendable`; cada chamada cria o seu (so guarda idioma/cookies).
    private nonisolated static func makeModel() -> YouTubeModel {
        let model = YouTubeModel()
        model.selectedLocale = Locale.preferredLanguages.first ?? "pt-BR"
        return model
    }

    func suggestions(for query: String) async throws -> [String] {
        try await AutoCompletionResponse.sendThrowingRequest(youtubeModel: Self.makeModel(), data: [.query: query])
            .autoCompletionEntries
    }

    func search(_ query: String) async throws -> CatalogPage {
        let response = try await SearchResponse.sendThrowingRequest(youtubeModel: Self.makeModel(), data: [.query: query])
        return CatalogPage(items: Self.items(from: response.results), continuation: response.continuationToken)
    }

    func moreResults(_ continuation: String) async throws -> CatalogPage {
        let response = try await SearchResponse.Continuation.sendThrowingRequest(
            youtubeModel: Self.makeModel(),
            data: [.continuation: continuation]
        )
        return CatalogPage(items: Self.items(from: response.results), continuation: response.continuationToken)
    }

    func playlist(_ playlistID: String) async throws -> PlaylistPage {
        let browseID = playlistID.hasPrefix("VL") ? playlistID : "VL" + playlistID
        let response = try await YTPlaylist(playlistId: browseID).fetchVideosThrowing(youtubeModel: Self.makeModel())
        return PlaylistPage(
            title: response.title ?? "",
            owner: response.channel.first?.name,
            tracks: response.results.map(Self.track(from:)),
            continuation: response.continuationToken
        )
    }

    func morePlaylistVideos(_ continuation: String) async throws -> PlaylistPage {
        let response = try await PlaylistInfosResponse.Continuation.sendThrowingRequest(
            youtubeModel: Self.makeModel(),
            data: [.continuation: continuation]
        )
        return PlaylistPage(
            title: "",
            owner: nil,
            tracks: response.results.map(Self.track(from:)),
            continuation: response.continuationToken
        )
    }

    // MARK: - Conversao

    private static func items(from results: [any YTSearchResult]) -> [CatalogItem] {
        results.compactMap { result in
            switch result {
            case let video as YTVideo:
                return .video(CatalogVideo(
                    track: track(from: video),
                    durationText: video.timeLength,
                    details: [video.viewCount, video.timePosted].compactMap { $0 }.joined(separator: " · ").nonEmpty
                ))
            case let channel as YTChannel:
                return .channel(CatalogChannel(
                    id: channel.channelId,
                    name: channel.name ?? channel.handle ?? "",
                    subscribers: channel.subscriberCount,
                    thumbnailURL: channel.thumbnails.last?.url.withHTTPS
                ))
            case let playlist as YTPlaylist:
                return .playlist(CatalogPlaylist(
                    id: playlist.playlistId.hasPrefix("VL") ? String(playlist.playlistId.dropFirst(2)) : playlist.playlistId,
                    title: playlist.title ?? "",
                    owner: playlist.channel?.name,
                    videoCount: playlist.videoCount,
                    thumbnailURL: playlist.thumbnails.last?.url.withHTTPS
                ))
            default:
                return nil
            }
        }
    }

    static func track(from video: YTVideo) -> MediaTrack {
        MediaTrack(
            videoID: video.videoId,
            title: video.title ?? "",
            artist: video.channel?.name ?? "",
            artworkURL: video.thumbnails.last?.url.withHTTPS,
            duration: video.timeLengthSeconds.map(TimeInterval.init)
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension URL {
    /// Algumas miniaturas de canal vem como `//yt3.ggpht.com/...`.
    var withHTTPS: URL {
        guard scheme == nil, absoluteString.hasPrefix("//") else { return self }
        return URL(string: "https:" + absoluteString) ?? self
    }
}
