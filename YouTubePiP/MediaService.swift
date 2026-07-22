import Foundation

enum MediaService: String, CaseIterable, Hashable, Identifiable {
    case youtube = "YouTube"
    case youtubeMusic = "YouTube Music"

    var id: Self { self }

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
