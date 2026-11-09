import Foundation
import WebKit
import YouTubePiPCore

/// Ponte com a midia da pagina: injeta os scripts, recebe os eventos e executa comandos.
@MainActor
final class WebMediaBridge {
    enum Event {
        case playing(videoID: String)
        case paused
        case pictureInPicture(active: Bool)
    }

    struct Capture {
        let snapshot: PageMediaSnapshot?
        /// JSON formatado, exibido na tela de diagnostico.
        let report: String
    }

    enum CaptureError: LocalizedError {
        case pageNotReady
        case invalidReport

        var errorDescription: String? {
            switch self {
            case .pageNotReady: String(localized: "A página ainda não está pronta.")
            case .invalidReport: String(localized: "A página retornou um diagnóstico de mídia inválido.")
            }
        }
    }

    /// Nome usado em `window.webkit.messageHandlers.<nome>` por `media-events.js`.
    static let messageHandlerName = "ytpipMedia"

    weak var webView: WKWebView?
    var onEvent: ((Event) -> Void)?

    private let audioOnly: Bool

    init(audioOnly: Bool) {
        self.audioOnly = audioOnly
    }

    /// Scripts injetados em toda pagina carregada.
    static func userScripts(audioOnly: Bool) -> [WKUserScript] {
        [
            WKUserScript(source: PageScript.mediaEvents.source, injectionTime: .atDocumentStart, forMainFrameOnly: true),
            WKUserScript(
                source: (audioOnly ? PageScript.audioOnly : PageScript.prepareVideo).source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        ]
    }

    func handle(messageBody: Any) {
        guard let event = messageBody as? [String: Any], let type = event["type"] as? String else { return }

        switch type {
        case "playing":
            onEvent?(.playing(videoID: (event["videoID"] as? String) ?? ""))
        case "paused":
            onEvent?(.paused)
        case "pip":
            onEvent?(.pictureInPicture(active: event["active"] as? Bool ?? false))
        default:
            break
        }
    }

    /// Reaplica os ajustes da pagina (o YouTube recria os elementos de video ao navegar).
    func applyPageAdjustments() {
        run(audioOnly ? .audioOnly : .prepareVideo)
    }

    func pauseMedia() {
        run(.pauseMedia)
    }

    func resumeMedia() {
        run(.resumeMedia)
    }

    /// Le o que a pagina esta tocando.
    func capture() async throws -> Capture {
        guard let webView else { throw CaptureError.pageNotReady }

        let json: String? = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(PageScript.mediaDiagnostics.source) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String)
                }
            }
        }

        guard
            let data = json?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let report = String(data: formatted, encoding: .utf8)
        else { throw CaptureError.invalidReport }

        return Capture(snapshot: PageMediaParser.snapshot(from: object), report: report)
    }

    private func run(_ script: PageScript) {
        webView?.evaluateJavaScript(script.source)
    }
}

/// Scripts de `YouTubePiP/Scripts/*.js`, copiados para o bundle do app.
enum PageScript: String, CaseIterable {
    case mediaEvents = "media-events"
    case mediaDiagnostics = "media-diagnostics"
    case prepareVideo = "prepare-video"
    case audioOnly = "audio-only"
    case pauseMedia = "pause-media"
    case resumeMedia = "resume-media"

    @MainActor var source: String {
        if let cached = Self.cache[self] { return cached }
        guard
            let url = Bundle.main.url(forResource: rawValue, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Script \(rawValue).js ausente do bundle")
            return ""
        }
        Self.cache[self] = source
        return source
    }

    @MainActor private static var cache: [PageScript: String] = [:]
}
