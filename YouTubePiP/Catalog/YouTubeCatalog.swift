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

/// Conta conectada (a partir do login feito na WebView).
struct AccountProfile: Equatable, Sendable {
    let name: String
    let handle: String?
    let avatarURL: URL?
}

struct LibrarySummary: Sendable {
    let likes: CatalogPlaylist?
    let watchLater: CatalogPlaylist?
    let playlists: [CatalogPlaylist]
}

/// Se o usuario curtiu o video e se esta inscrito no canal.
struct VideoAccountState: Equatable, Sendable {
    let videoID: String
    var isLiked: Bool
    var isSubscribed: Bool?
    let channelID: String?
    let channelName: String?
}

/// Abas de um canal.
enum ChannelTab: String, CaseIterable, Hashable, Sendable {
    case videos, shorts, live, playlists

    var title: String {
        switch self {
        case .videos: String(localized: "Vídeos")
        case .shorts: String(localized: "Shorts")
        case .live: String(localized: "Ao vivo")
        case .playlists: String(localized: "Playlists")
        }
    }

    fileprivate var requestType: ChannelInfosResponse.RequestTypes {
        switch self {
        case .videos: .videos
        case .shorts: .shorts
        case .live: .directs
        case .playlists: .playlists
        }
    }
}

struct ChannelDetails: Sendable {
    let id: String
    let name: String
    let handle: String?
    let subscribers: String?
    let avatarURL: URL?
    let bannerURL: URL?
    let tabs: [ChannelTab]
    /// So vem com login.
    let isSubscribed: Bool?
}

/// Informacoes extras do video que esta tocando.
struct VideoDetails: Sendable {
    let chapters: [VideoChapter]
    let commentsCount: String?
    let commentsContinuation: String?
}

struct CatalogComment: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let avatarURL: URL?
    let text: String
    let timePosted: String?
    let likes: String?
    let repliesCount: String?
}

struct CommentsPage: Sendable {
    let comments: [CatalogComment]
    let continuation: String?
}

struct ChannelPage: Sendable {
    let channels: [CatalogChannel]
    let continuation: String?
}

enum CatalogError: LocalizedError {
    case signedOut

    var errorDescription: String? {
        String(localized: "Entre na sua conta do YouTube para ver isto.")
    }
}

struct CatalogPage: Sendable {
    let items: [CatalogItem]
    /// Token para buscar a proxima pagina, se houver.
    let continuation: String?
    /// A continuacao da tela inicial tambem exige este valor.
    var visitorData: String? = nil
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

    /// Cabecalho `Cookie` da conta (so na memoria). `nil` = sem login.
    private var cookies: String?

    func setCookies(_ cookies: String?) {
        self.cookies = cookies
    }

    var isSignedIn: Bool { cookies != nil }

    // `YouTubeModel` nao e `Sendable`; cada chamada cria o seu (so guarda idioma/cookies).
    private nonisolated static func makeModel(cookies: String? = nil) -> YouTubeModel {
        let model = YouTubeModel()
        model.selectedLocale = Locale.preferredLanguages.first ?? "pt-BR"
        if let cookies {
            model.cookies = cookies
            model.alwaysUseCookies = true
        }
        return model
    }

    private func requireCookies() throws -> String {
        guard let cookies else { throw CatalogError.signedOut }
        return cookies
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
        let response = try await YTPlaylist(playlistId: browseID).fetchVideosThrowing(youtubeModel: Self.makeModel(cookies: cookies))
        return PlaylistPage(
            title: response.title ?? "",
            owner: response.channel.first?.name,
            tracks: response.results.map(Self.track(from:)),
            continuation: response.continuationToken
        )
    }

    func morePlaylistVideos(_ continuation: String) async throws -> PlaylistPage {
        let response = try await PlaylistInfosResponse.Continuation.sendThrowingRequest(
            youtubeModel: Self.makeModel(cookies: cookies),
            data: [.continuation: continuation]
        )
        return PlaylistPage(
            title: "",
            owner: nil,
            tracks: response.results.map(Self.track(from:)),
            continuation: response.continuationToken
        )
    }

    // MARK: - Inicio

    /// Recomendacoes da tela inicial. Sem login o YouTube devolve uma lista vazia.
    func home(continuation: String? = nil, visitorData: String? = nil) async throws -> CatalogPage {
        let model = Self.makeModel(cookies: cookies)
        if let continuation, let visitorData {
            let response = try await HomeScreenResponse.Continuation.sendThrowingRequest(
                youtubeModel: model,
                data: [.continuation: continuation, .visitorData: visitorData]
            )
            return CatalogPage(items: Self.items(from: response.results), continuation: response.continuationToken, visitorData: visitorData)
        }
        let response = try await HomeScreenResponse.sendThrowingRequest(youtubeModel: model, data: [:])
        return CatalogPage(items: Self.items(from: response.results), continuation: response.continuationToken, visitorData: response.visitorData)
    }

    // MARK: - Canais

    /// Respostas de canal guardadas para buscar as proximas paginas de cada aba.
    private var channelResponses: [String: ChannelInfosResponse] = [:]

    func channel(_ channelID: String) async throws -> ChannelDetails {
        let response = try await YTChannel(channelId: channelID)
            .fetchInfosThrowing(youtubeModel: Self.makeModel(cookies: cookies), useCookies: cookies != nil)
        channelResponses[channelID] = response
        let tabs = ChannelTab.allCases.filter { response.requestParams[$0.requestType] != nil }
        return ChannelDetails(
            id: channelID,
            name: response.name ?? "",
            handle: response.handle,
            subscribers: response.subscriberCount,
            avatarURL: response.avatarThumbnails.last?.url.withHTTPS,
            bannerURL: response.bannerThumbnails.last?.url.withHTTPS,
            tabs: tabs,
            isSubscribed: cookies == nil ? nil : response.subscribeStatus
        )
    }

    /// Primeira pagina de uma aba do canal (chame `channel(_:)` antes).
    func channelItems(_ channelID: String, tab: ChannelTab) async throws -> CatalogPage {
        guard let base = channelResponses[channelID] else {
            _ = try await channel(channelID)
            return try await channelItems(channelID, tab: tab)
        }
        let response = try await base.getChannelContentThrowing(
            forType: tab.requestType,
            youtubeModel: Self.makeModel(cookies: cookies),
            useCookies: cookies != nil
        )
        channelResponses[channelID] = response
        let content = response.channelContentStore[tab.requestType] as? any ListableChannelContent
        return CatalogPage(
            items: Self.items(from: content?.items ?? []),
            continuation: response.channelContentContinuationStore[tab.requestType] ?? nil
        )
    }

    func moreChannelItems(_ channelID: String, tab: ChannelTab) async throws -> CatalogPage {
        guard var response = channelResponses[channelID] else { return CatalogPage(items: [], continuation: nil) }
        let model = Self.makeModel(cookies: cookies)
        let items: [any YTSearchResult]
        let token: String?
        switch tab {
        case .videos:
            let page = try await response.getChannelContentContinuationThrowing(ChannelInfosResponse.Videos.self, youtubeModel: model)
            (items, token) = (page.contents?.items ?? [], page.newContinuationToken)
        case .shorts:
            let page = try await response.getChannelContentContinuationThrowing(ChannelInfosResponse.Shorts.self, youtubeModel: model)
            (items, token) = (page.contents?.items ?? [], page.newContinuationToken)
        case .live:
            let page = try await response.getChannelContentContinuationThrowing(ChannelInfosResponse.Directs.self, youtubeModel: model)
            (items, token) = (page.contents?.items ?? [], page.newContinuationToken)
        case .playlists:
            let page = try await response.getChannelContentContinuationThrowing(ChannelInfosResponse.Playlists.self, youtubeModel: model)
            (items, token) = (page.contents?.items ?? [], page.newContinuationToken)
        }
        response.channelContentContinuationStore[tab.requestType] = token
        channelResponses[channelID] = response
        return CatalogPage(items: Self.items(from: items), continuation: token)
    }

    // MARK: - Detalhes do video

    func details(for videoID: String) async throws -> VideoDetails {
        let response = try await YTVideo(videoId: videoID)
            .fetchMoreInfosThrowing(youtubeModel: Self.makeModel(cookies: cookies), useCookies: cookies != nil)
        let chapters = (response.chapters ?? []).compactMap { chapter -> VideoChapter? in
            guard let start = chapter.startTimeSeconds else { return nil }
            return VideoChapter(title: chapter.title ?? "", start: TimeInterval(start))
        }
        return VideoDetails(
            chapters: VideoChapters.normalized(chapters),
            commentsCount: response.commentsCount,
            commentsContinuation: response.commentsContinuationToken
        )
    }

    /// Comentarios. A primeira pagina usa o token de `details(for:)`; as seguintes, o token da pagina anterior.
    func comments(token: String, isFirstPage: Bool) async throws -> CommentsPage {
        let model = Self.makeModel(cookies: cookies)
        let comments: [YTComment]
        let next: String?
        if isFirstPage {
            let response = try await VideoCommentsResponse.sendThrowingRequest(youtubeModel: model, data: [.continuation: token])
            (comments, next) = (response.results, response.continuationToken)
        } else {
            let response = try await VideoCommentsResponse.Continuation.sendThrowingRequest(youtubeModel: model, data: [.continuation: token])
            (comments, next) = (response.results, response.continuationToken)
        }
        return CommentsPage(
            comments: comments.map { comment in
                CatalogComment(
                    id: comment.commentIdentifier,
                    author: comment.sender?.name ?? comment.sender?.handle ?? "",
                    avatarURL: comment.sender?.thumbnails.last?.url.withHTTPS,
                    text: comment.text,
                    timePosted: comment.timePosted,
                    likes: comment.likesCount,
                    repliesCount: comment.totalRepliesNumber
                )
            },
            continuation: next
        )
    }

    // MARK: - Conta

    /// Dados da conta, ou `nil` se os cookies nao forem mais validos.
    func profile() async throws -> AccountProfile? {
        let response = try await AccountInfosResponse.sendThrowingRequest(youtubeModel: Self.makeModel(cookies: try requireCookies()), data: [:])
        guard !response.isDisconnected else { return nil }
        return AccountProfile(
            name: response.name ?? "",
            handle: response.channelHandle,
            avatarURL: response.avatar.last?.url.withHTTPS
        )
    }

    func library() async throws -> LibrarySummary {
        let model = Self.makeModel(cookies: try requireCookies())
        let library = try await AccountLibraryResponse.sendThrowingRequest(youtubeModel: model, data: [:])
        guard !library.isDisconnected else { throw CatalogError.signedOut }
        // A biblioteca traz so algumas playlists; a lista completa vem desta outra chamada.
        let all = try? await AccountPlaylistsResponse.sendThrowingRequest(youtubeModel: Self.makeModel(cookies: cookies), data: [:])
        let playlists = (all?.results.isEmpty == false ? all?.results : nil) ?? library.playlists
        return LibrarySummary(
            likes: library.likes.map(Self.playlist(from:)),
            watchLater: library.watchLater.map(Self.playlist(from:)),
            playlists: playlists.map(Self.playlist(from:))
        )
    }

    /// Videos novos dos canais inscritos.
    func subscriptionsFeed(continuation: String? = nil) async throws -> CatalogPage {
        let model = Self.makeModel(cookies: try requireCookies())
        let videos: [YTVideo]
        let token: String?
        if let continuation {
            let response = try await AccountSubscriptionsFeedResponse.Continuation.sendThrowingRequest(
                youtubeModel: model,
                data: [.continuation: continuation]
            )
            videos = response.results
            token = response.continuationToken
        } else {
            let response = try await AccountSubscriptionsFeedResponse.sendThrowingRequest(youtubeModel: model, data: [:])
            guard !response.isDisconnected else { throw CatalogError.signedOut }
            videos = response.results
            token = response.continuationToken
        }
        return CatalogPage(items: Self.items(from: videos), continuation: token)
    }

    func subscriptions(continuation: String? = nil) async throws -> ChannelPage {
        let model = Self.makeModel(cookies: try requireCookies())
        let channels: [YTChannel]
        let token: String?
        if let continuation {
            let response = try await AccountSubscriptionsResponse.Continuation.sendThrowingRequest(
                youtubeModel: model,
                data: [.continuation: continuation]
            )
            channels = response.results
            token = response.continuationToken
        } else {
            let response = try await AccountSubscriptionsResponse.sendThrowingRequest(youtubeModel: model, data: [:])
            guard !response.isDisconnected else { throw CatalogError.signedOut }
            channels = response.results
            token = response.continuationToken
        }
        return ChannelPage(channels: channels.map(Self.channel(from:)), continuation: token)
    }

    func accountState(for videoID: String) async throws -> VideoAccountState {
        let response = try await YTVideo(videoId: videoID).fetchMoreInfosThrowing(youtubeModel: Self.makeModel(cookies: try requireCookies()), useCookies: true)
        return VideoAccountState(
            videoID: videoID,
            isLiked: response.authenticatedInfos?.likeStatus == .liked,
            isSubscribed: response.authenticatedInfos?.subscriptionStatus,
            channelID: response.channel?.channelId,
            channelName: response.channel?.name
        )
    }

    func setLiked(_ liked: Bool, videoID: String) async throws {
        let video = YTVideo(videoId: videoID)
        if liked {
            try await video.likeVideoThrowing(youtubeModel: Self.makeModel(cookies: try requireCookies()))
        } else {
            try await video.removeLikeFromVideoThrowing(youtubeModel: Self.makeModel(cookies: try requireCookies()))
        }
    }

    func setSubscribed(_ subscribed: Bool, channelID: String) async throws {
        let channel = YTChannel(channelId: channelID)
        if subscribed {
            try await channel.subscribeThrowing(youtubeModel: Self.makeModel(cookies: try requireCookies()))
        } else {
            try await channel.unsubscribeThrowing(youtubeModel: Self.makeModel(cookies: try requireCookies()))
        }
    }

    // MARK: - Conversao

    private static func items(from videos: [YTVideo]) -> [CatalogItem] {
        items(from: videos as [any YTSearchResult])
    }

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
                return .channel(Self.channel(from: channel))
            case let playlist as YTPlaylist:
                return .playlist(Self.playlist(from: playlist))
            default:
                return nil
            }
        }
    }

    static func channel(from channel: YTChannel) -> CatalogChannel {
        CatalogChannel(
            id: channel.channelId,
            name: channel.name ?? channel.handle ?? "",
            subscribers: channel.subscriberCount,
            thumbnailURL: channel.thumbnails.last?.url.withHTTPS
        )
    }

    static func playlist(from playlist: YTPlaylist) -> CatalogPlaylist {
        CatalogPlaylist(
            id: playlist.playlistId.hasPrefix("VL") ? String(playlist.playlistId.dropFirst(2)) : playlist.playlistId,
            title: playlist.title ?? "",
            owner: playlist.channel?.name,
            videoCount: playlist.videoCount,
            thumbnailURL: (playlist.thumbnails.last ?? playlist.frontVideos.first?.thumbnails.last)?.url.withHTTPS
        )
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
