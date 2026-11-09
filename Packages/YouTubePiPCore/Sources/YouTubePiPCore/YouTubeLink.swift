import Foundation

/// Um link do YouTube/YouTube Music reconhecido (de compartilhamento, do `ytpip://` ou copiado).
public struct YouTubeLink: Equatable, Sendable {
    public let videoID: String?
    public let playlistID: String?
    public let startTime: TimeInterval?
    /// O link e do YouTube Music (abre na aba Music).
    public let isMusic: Bool

    public init(videoID: String?, playlistID: String? = nil, startTime: TimeInterval? = nil, isMusic: Bool) {
        self.videoID = videoID
        self.playlistID = playlistID
        self.startTime = startTime
        self.isMusic = isMusic
    }

    /// Pagina a carregar na aba correspondente.
    public var pageURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isMusic ? "music.youtube.com" : "m.youtube.com"
        var items: [URLQueryItem] = []
        if let videoID {
            components.path = "/watch"
            items.append(URLQueryItem(name: "v", value: videoID))
        } else {
            components.path = "/playlist"
        }
        if let playlistID {
            items.append(URLQueryItem(name: "list", value: playlistID))
        }
        components.queryItems = items
        return components.url!
    }

    /// Esquema proprio do app: `ytpip://open?url=<link>` ou `ytpip://watch?v=<id>`.
    public static let appScheme = "ytpip"

    public static func parse(_ url: URL) -> YouTubeLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        func value(_ name: String) -> String? { query.first(where: { $0.name == name })?.value.nonEmpty }

        if scheme == appScheme {
            if let inner = value("url").flatMap(URL.init(string:)) {
                return parse(inner)
            }
            // ytpip://watch?v=ID (host = "watch") ou ytpip://music/watch?v=ID
            let isMusic = url.host?.lowercased() == "music"
            return make(videoID: value("v"), playlistID: value("list"), time: value("t"), isMusic: isMusic)
        }

        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be" {
            return make(videoID: path.first, playlistID: value("list"), time: value("t"), isMusic: false)
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com"
                || host.hasSuffix(".youtube-nocookie.com")
        else { return nil }
        let isMusic = host == "music.youtube.com"

        switch path.first {
        case "watch":
            return make(videoID: value("v"), playlistID: value("list"), time: value("t") ?? value("start"), isMusic: isMusic)
        case "shorts", "live", "embed", "v":
            return make(videoID: path.dropFirst().first, playlistID: value("list"), time: value("t") ?? value("start"), isMusic: isMusic)
        case "playlist":
            return make(videoID: nil, playlistID: value("list"), time: nil, isMusic: isMusic)
        default:
            return nil
        }
    }

    /// Procura o primeiro link do YouTube num texto (por exemplo, o que foi copiado).
    public static func firstLink(in text: String) -> YouTubeLink? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'()"))
        for token in text.components(separatedBy: separators) where token.lowercased().contains("youtu") || token.hasPrefix(appScheme + ":") {
            let candidate = token.contains("://") ? token : "https://" + token
            if let url = URL(string: candidate), let link = parse(url) {
                return link
            }
        }
        return nil
    }

    /// Le `90`, `90s`, `1m30s` ou `1h2m3s`.
    public static func parseTime(_ value: String) -> TimeInterval? {
        let text = value.lowercased()
        if let seconds = TimeInterval(text) { return seconds >= 0 ? seconds : nil }

        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false
        for character in text {
            if character.isNumber {
                number.append(character)
                continue
            }
            guard let amount = TimeInterval(number) else { return nil }
            switch character {
            case "h": total += amount * 3600
            case "m": total += amount * 60
            case "s": total += amount
            default: return nil
            }
            number = ""
            sawUnit = true
        }
        guard number.isEmpty, sawUnit else { return nil }
        return total
    }

    private static func make(videoID: String?, playlistID: String?, time: String?, isMusic: Bool) -> YouTubeLink? {
        let videoID = videoID.flatMap { isValidID($0) ? $0 : nil }
        guard videoID != nil || playlistID != nil else { return nil }
        return YouTubeLink(
            videoID: videoID,
            playlistID: playlistID,
            startTime: time.flatMap(parseTime),
            isMusic: isMusic
        )
    }

    private static func isValidID(_ value: String) -> Bool {
        value.count >= 6 && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
