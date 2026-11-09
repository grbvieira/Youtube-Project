import Foundation

/// Buscas recentes, da mais nova para a mais antiga, sem repetir (ignorando maiusculas e acentos).
public struct RecentSearches: Codable, Equatable, Sendable {
    public private(set) var queries: [String]

    public static let limit = 20

    public init(queries: [String] = []) {
        self.queries = queries
    }

    public mutating func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = Self.key(trimmed)
        queries.removeAll { Self.key($0) == key }
        queries.insert(trimmed, at: 0)
        if queries.count > Self.limit {
            queries.removeLast(queries.count - Self.limit)
        }
    }

    public mutating func remove(_ query: String) {
        let key = Self.key(query)
        queries.removeAll { Self.key($0) == key }
    }

    public mutating func clear() {
        queries.removeAll()
    }

    /// Recentes que comecam com o texto digitado (para sugerir antes da resposta da rede).
    public func matching(_ prefix: String) -> [String] {
        let key = Self.key(prefix.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return queries }
        return queries.filter { Self.key($0).hasPrefix(key) }
    }

    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
