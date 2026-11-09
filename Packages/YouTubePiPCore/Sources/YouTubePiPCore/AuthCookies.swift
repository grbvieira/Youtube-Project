import Foundation

/// Monta o cabecalho `Cookie` para as chamadas autenticadas a partir dos cookies da WebView.
///
/// Os cookies sao o login da conta: so os do dominio `youtube.com` sao usados, e apenas se
/// os de autenticacao estiverem presentes. O resultado deve ficar so na memoria.
public enum AuthCookies {
    public struct Cookie: Equatable, Sendable {
        public let name: String
        public let value: String
        public let domain: String

        public init(name: String, value: String, domain: String) {
            self.name = name
            self.value = value
            self.domain = domain
        }
    }

    /// Cookies que o YouTube exige para identificar a conta.
    static let requiredNames = ["SAPISID", "__Secure-1PSID"]

    public static func header(from cookies: [Cookie]) -> String? {
        var byName: [String: Cookie] = [:]
        for cookie in cookies where isYouTube(domain: cookie.domain) && !cookie.value.isEmpty {
            // Prefere o cookie de ".youtube.com" (vale para todos os subdominios).
            if let existing = byName[cookie.name], existing.domain.hasPrefix("."), !cookie.domain.hasPrefix(".") {
                continue
            }
            byName[cookie.name] = cookie
        }

        guard requiredNames.allSatisfy({ byName[$0] != nil }) else { return nil }

        return byName.keys.sorted()
            .compactMap { name in byName[name].map { "\(name)=\($0.value)" } }
            .joined(separator: "; ")
    }

    static func isYouTube(domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
}
