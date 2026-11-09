import Foundation
import YouTubePiPCore

/// Estado da tela de busca: sugestoes enquanto digita, resultados paginados e buscas recentes.
@MainActor
final class SearchViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case searching
        case results
        case failed(String)
    }

    @Published var query = "" {
        didSet { if query != oldValue { scheduleSuggestions() } }
    }
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var recent: RecentSearches

    private let catalog: YouTubeCatalog
    private let defaults: UserDefaults
    private var continuation: String?
    private var suggestionTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchedQuery = ""

    private static let recentKey = "recentSearches"
    private static let suggestionDelay: UInt64 = 250_000_000

    init(catalog: YouTubeCatalog = .shared, defaults: UserDefaults = .standard) {
        self.catalog = catalog
        self.defaults = defaults
        recent = defaults.data(forKey: Self.recentKey)
            .flatMap { try? JSONDecoder().decode(RecentSearches.self, from: $0) }
            ?? RecentSearches()
    }

    /// Buscas recentes que combinam com o que foi digitado.
    var matchingRecent: [String] { recent.matching(query) }

    func submit(_ text: String? = nil) {
        let text = (text ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if query != text { query = text }
        suggestionTask?.cancel()
        suggestions = []
        recent.add(text)
        saveRecent()

        searchedQuery = text
        phase = .searching
        items = []
        continuation = nil
        searchTask?.cancel()
        searchTask = Task { [weak self, catalog] in
            do {
                let page = try await catalog.search(text)
                guard let self, !Task.isCancelled, self.searchedQuery == text else { return }
                self.items = page.items
                self.continuation = page.continuation
                self.phase = .results
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Chamado quando um item aparece na tela; perto do fim, busca a proxima pagina.
    func loadMoreIfNeeded(after item: CatalogItem) {
        guard
            phase == .results,
            !isLoadingMore,
            let continuation,
            let index = items.firstIndex(of: item),
            index >= items.count - 5
        else { return }

        isLoadingMore = true
        let text = searchedQuery
        Task { [weak self, catalog] in
            let page = try? await catalog.moreResults(continuation)
            guard let self, self.searchedQuery == text else { return }
            self.isLoadingMore = false
            guard let page else { return }
            let known = Set(self.items.map(\.id))
            self.items += page.items.filter { !known.contains($0.id) }
            self.continuation = page.continuation
        }
    }

    func removeRecent(_ query: String) {
        recent.remove(query)
        saveRecent()
    }

    func clearRecent() {
        recent.clear()
        saveRecent()
    }

    /// Voltou ao campo vazio: mostra as recentes de novo.
    func reset() {
        searchTask?.cancel()
        items = []
        continuation = nil
        phase = .idle
    }

    private func scheduleSuggestions() {
        suggestionTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            suggestions = []
            return
        }
        suggestionTask = Task { [weak self, catalog] in
            try? await Task.sleep(nanoseconds: Self.suggestionDelay)
            guard !Task.isCancelled, let entries = try? await catalog.suggestions(for: text) else { return }
            guard let self, !Task.isCancelled, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            self.suggestions = entries
        }
    }

    private func saveRecent() {
        defaults.set(try? JSONEncoder().encode(recent), forKey: Self.recentKey)
    }
}
