import Foundation

/// Decide o que fazer com uma navegacao dentro da WebView.
public enum LinkPolicy {
    public enum Decision: Equatable, Sendable {
        /// Abre dentro do app.
        case allow
        /// Abre fora do app (Safari, Mail, Telefone...).
        case openExternally
        /// Ignora (por exemplo, `youtube://`, que abriria o app oficial).
        case cancel
    }

    /// Dominios do YouTube e do login do Google, que ficam dentro do app.
    static let internalHostSuffixes = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "ytimg.com",
        "google.com", "gstatic.com", "googleusercontent.com", "googlevideo.com"
    ]

    static let externalSchemes: Set<String> = ["mailto", "tel", "sms", "facetime", "maps"]
    static let inPageSchemes: Set<String> = ["about", "blob", "data", "javascript"]

    /// - Parameters:
    ///   - isUserLink: a navegacao veio de um toque em link (redirecionamentos de login nao contam).
    ///   - opensNewWindow: o link pediu uma nova janela (`target=_blank`).
    public static func decide(url: URL, isUserLink: Bool, isMainFrame: Bool, opensNewWindow: Bool = false) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .cancel }

        if inPageSchemes.contains(scheme) { return .allow }
        if externalSchemes.contains(scheme) { return .openExternally }
        guard scheme == "http" || scheme == "https" else { return .cancel }

        // So links tocados pelo usuario na pagina principal saem do app; iframes e redirecionamentos ficam.
        guard isUserLink, isMainFrame || opensNewWindow else { return .allow }
        return isInternal(host: url.host) ? .allow : .openExternally
    }

    static func isInternal(host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return true }
        // Dominios do Google por pais (google.com.br, accounts.google.co.uk...).
        if host == "google" || host.hasPrefix("google.") || host.contains(".google.") { return true }
        return internalHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
