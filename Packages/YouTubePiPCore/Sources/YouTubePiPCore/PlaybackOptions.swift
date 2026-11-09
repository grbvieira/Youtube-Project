import Foundation

/// Timer para dormir: pausa depois de um tempo ou ao fim da faixa atual.
public struct SleepTimer: Equatable, Sendable {
    public enum Option: Hashable, Sendable {
        case minutes(Int)
        case endOfTrack
    }

    public static let presets: [Option] = [.minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfTrack]

    public private(set) var deadline: Date?
    public private(set) var stopsAtEndOfTrack = false

    public init() {}

    public var isActive: Bool { deadline != nil || stopsAtEndOfTrack }

    /// Liga com uma opcao, ou desliga com `nil`.
    public mutating func set(_ option: Option?, now: Date) {
        deadline = nil
        stopsAtEndOfTrack = false
        switch option {
        case .minutes(let minutes) where minutes > 0:
            deadline = now.addingTimeInterval(TimeInterval(minutes) * 60)
        case .endOfTrack:
            stopsAtEndOfTrack = true
        default:
            break
        }
    }

    public func remaining(now: Date) -> TimeInterval? {
        deadline.map { max(0, $0.timeIntervalSince(now)) }
    }

    /// O tempo acabou (nao inclui "fim da faixa", que e decidido quando a faixa termina).
    public func isExpired(now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }
}

/// Velocidades de reproducao oferecidas.
public enum PlaybackRate {
    public static let options: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
}

/// Limite de qualidade do stream (economia de dados).
public enum StreamQuality: String, CaseIterable, Codable, Sendable {
    /// Sem limite: o player escolhe pela rede.
    case automatic
    /// Ate 480p.
    case dataSaver
    /// Ate 360p (rede ruim ou plano limitado).
    case minimum

    public struct Limits: Equatable, Sendable {
        /// Bits por segundo; 0 = sem limite.
        public let peakBitRate: Double
        public let maxWidth: Int?
        public let maxHeight: Int?
    }

    /// No modo so audio, o video nao aparece: usa a menor variante com audio AAC-LC (360p).
    public static let audioOnlyLimits = Limits(peakBitRate: 700_000, maxWidth: 640, maxHeight: 360)

    public func limits(audioOnly: Bool) -> Limits {
        if audioOnly { return Self.audioOnlyLimits }
        switch self {
        case .automatic: return Limits(peakBitRate: 0, maxWidth: nil, maxHeight: nil)
        case .dataSaver: return Limits(peakBitRate: 1_000_000, maxWidth: 854, maxHeight: 480)
        case .minimum: return Limits(peakBitRate: 700_000, maxWidth: 640, maxHeight: 360)
        }
    }
}
