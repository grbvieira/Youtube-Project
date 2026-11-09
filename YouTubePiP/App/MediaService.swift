import Foundation

enum MediaService: String, CaseIterable, Hashable, Identifiable {
    case youtube = "YouTube"
    case youtubeMusic = "YouTube Music"

    var id: Self { self }

    /// Nome exibido nas abas e na tela bloqueada (nome proprio, nao traduzido).
    var displayName: String { rawValue }

    var homeURL: URL {
        switch self {
        case .youtube:
            return URL(string: "https://www.youtube.com")!
        case .youtubeMusic:
            return URL(string: "https://music.youtube.com")!
        }
    }

    var audioOnly: Bool {
        self == .youtubeMusic
    }

    var tabIcon: String {
        switch self {
        case .youtube:
            return "play.rectangle.fill"
        case .youtubeMusic:
            return "music.note"
        }
    }
}
