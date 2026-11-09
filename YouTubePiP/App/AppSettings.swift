import Foundation
import YouTubePiPCore

/// Preferencias do usuario, salvas no `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let quality = "streamQuality"
        static let youtubeAudioOnly = "youtubeAudioOnly"
    }

    private let defaults: UserDefaults

    /// Limite de qualidade do video (economia de dados).
    @Published var quality: StreamQuality {
        didSet { defaults.set(quality.rawValue, forKey: Key.quality) }
    }

    /// Toca a aba YouTube so em audio (podcasts, videos longos).
    @Published var youtubeAudioOnly: Bool {
        didSet { defaults.set(youtubeAudioOnly, forKey: Key.youtubeAudioOnly) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quality = defaults.string(forKey: Key.quality).flatMap(StreamQuality.init(rawValue:)) ?? .automatic
        youtubeAudioOnly = defaults.bool(forKey: Key.youtubeAudioOnly)
    }
}

extension StreamQuality {
    var title: String {
        switch self {
        case .automatic: String(localized: "Automática")
        case .dataSaver: String(localized: "Economia de dados (480p)")
        case .minimum: String(localized: "Mínima (360p)")
        }
    }
}
