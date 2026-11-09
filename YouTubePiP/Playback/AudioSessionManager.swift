import AVFoundation

/// Centraliza a `AVAudioSession` do app.
///
/// A categoria `.playback` e configurada na inicializacao (necessaria para a WebView
/// continuar tocando em segundo plano), mas a sessao so e ativada quando o player
/// nativo realmente comeca a tocar, para nao interromper o audio de outros apps
/// apenas por abrir o YouTube PiP.
@MainActor
final class AudioSessionManager {
    enum Event {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case outputDeviceUnavailable
    }

    static let shared = AudioSessionManager()

    private var handlers: [UUID: (Event) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let event = Self.interruptionEvent(from: notification)
            MainActor.assumeIsolated {
                guard let event else { return }
                self?.broadcast(event)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard
                    let reasonValue,
                    AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable
                else { return }
                self?.broadcast(.outputDeviceUnavailable)
            }
        })
    }

    /// Define a categoria sem ativar a sessao (nao interrompe outros apps).
    func configureCategory() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            print("Unable to configure playback audio session category: \(error)")
        }
    }

    /// Ativa a sessao. Chame apenas quando o app for de fato tocar audio.
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try session.setCategory(.playback, mode: .default)
        }
        try session.setActive(true)
    }

    @discardableResult
    func observe(_ handler: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        handlers[id] = nil
    }

    private func broadcast(_ event: Event) {
        handlers.values.forEach { $0(event) }
    }

    private nonisolated static func interruptionEvent(from notification: Notification) -> Event? {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return nil }

        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}
