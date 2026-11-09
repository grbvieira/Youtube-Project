import Foundation

/// Paginas equivalentes as telas nativas, usadas como reserva quando a tela nativa falha
/// (por exemplo, se o YouTube mudar a resposta da API interna).
public enum PageURL {
    public static func home(isMusic: Bool) -> URL {
        make(isMusic: isMusic, path: "/")
    }

    public static func search(_ query: String, isMusic: Bool) -> URL {
        make(isMusic: isMusic, path: isMusic ? "/search" : "/results", query: [isMusic ? "q" : "search_query": query])
    }

    public static func channel(_ channelID: String, isMusic: Bool) -> URL {
        make(isMusic: isMusic, path: "/channel/" + channelID)
    }

    public static func playlist(_ playlistID: String, isMusic: Bool) -> URL {
        let id = playlistID.hasPrefix("VL") ? String(playlistID.dropFirst(2)) : playlistID
        return make(isMusic: isMusic, path: "/playlist", query: ["list": id])
    }

    public static func library(isMusic: Bool) -> URL {
        make(isMusic: isMusic, path: isMusic ? "/library" : "/feed/library")
    }

    public static func subscriptions(isMusic: Bool) -> URL {
        make(isMusic: isMusic, path: isMusic ? "/library/subscriptions" : "/feed/subscriptions")
    }

    private static func make(isMusic: Bool, path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isMusic ? "music.youtube.com" : "m.youtube.com"
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }
}

/// Capitulo de um video.
public struct VideoChapter: Equatable, Hashable, Sendable {
    public let title: String
    public let start: TimeInterval

    public init(title: String, start: TimeInterval) {
        self.title = title
        self.start = start
    }
}

public enum VideoChapters {
    /// Ordena, remove repetidos e descarta capitulos invalidos.
    public static func normalized(_ chapters: [VideoChapter]) -> [VideoChapter] {
        var seen = Set<TimeInterval>()
        return chapters
            .filter { $0.start >= 0 && $0.start.isFinite }
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.start).inserted }
    }

    /// Indice do capitulo em andamento no tempo `time` (`chapters` ja normalizado).
    public static func currentIndex(in chapters: [VideoChapter], at time: TimeInterval) -> Int? {
        guard let first = chapters.first, time >= first.start else { return nil }
        return chapters.lastIndex { $0.start <= time }
    }
}
