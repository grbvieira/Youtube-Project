import SwiftUI
import YouTubePiPCore

/// Inicio nativo da aba: continuar assistindo (historico local), recomendacoes da conta
/// e novidades das inscricoes. Mostra o que houver; sem login, convida a entrar.
struct NativeHomeView: View {
    let isMusic: Bool
    let actions: CatalogActions
    let onSignIn: () -> Void
    /// O Inicio nativo nao carregou nada: a aba volta para a pagina.
    let onFailure: () -> Void

    @EnvironmentObject private var account: AccountSession
    @EnvironmentObject private var history: HistoryStore
    @StateObject private var model = NativeHomeViewModel()

    var body: some View {
        NavigationStack {
            List {
                continueSection
                recommendationsSection
                subscriptionsSection
                signInSection
            }
            .listStyle(.plain)
            .navigationTitle("Início")
            .navigationBarTitleDisplayMode(.inline)
            .catalogDestinations(actions)
            .refreshable { await model.load(signedIn: account.isSignedIn, force: true) }
            .task(id: account.isSignedIn) {
                await model.load(signedIn: account.isSignedIn)
                // Erro sem nada para mostrar (nem historico): melhor mostrar a pagina do que uma tela vazia.
                if model.errorMessage != nil, model.recommendations.isEmpty, model.subscriptions.isEmpty, resumable.isEmpty {
                    onFailure()
                }
            }
        }
    }

    // MARK: - Secoes

    /// Itens do historico que podem ser retomados, da aba atual.
    private var resumable: [HistoryEntry] {
        history.entries
            .filter { $0.isMusic == isMusic && history.resumePosition(for: $0.videoID) != nil }
            .prefix(12)
            .map { $0 }
    }

    @ViewBuilder
    private var continueSection: some View {
        let entries = resumable
        if !entries.isEmpty {
            Section(isMusic ? "Continuar ouvindo" : "Continuar assistindo") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entries) { entry in
                            Button {
                                actions.playVideo(entry.track)
                            } label: {
                                ResumeCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if !model.recommendations.isEmpty {
            Section("Para você") {
                ForEach(model.recommendations) { item in
                    videoButton(item)
                        .onAppear { model.loadMoreRecommendations(after: item) }
                }
                if model.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionsSection: some View {
        if !model.subscriptions.isEmpty {
            Section("Novidades das inscrições") {
                ForEach(model.subscriptions) { item in
                    videoButton(item)
                }
            }
        }
    }

    @ViewBuilder
    private var signInSection: some View {
        if model.isLoading && model.recommendations.isEmpty && model.subscriptions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
                .listRowSeparator(.hidden)
        } else if !account.isSignedIn && account.state != .unknown {
            CatalogMessage(
                systemImage: "person.crop.circle.badge.plus",
                title: String(localized: "Recomendações para você"),
                message: String(localized: "O YouTube só mostra recomendações com login. Entre na sua conta ou use a busca.")
            ) {
                Button(action: onSignIn) {
                    Label("Entrar no YouTube", systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowSeparator(.hidden)
        } else if let error = model.errorMessage, model.recommendations.isEmpty, model.subscriptions.isEmpty {
            CatalogMessage(systemImage: "wifi.exclamationmark", title: String(localized: "Não foi possível carregar"), message: error) {
                Button("Tentar novamente") {
                    Task { await model.load(signedIn: account.isSignedIn, force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func videoButton(_ item: CatalogItem) -> some View {
        if case .video(let video) = item {
            Button {
                actions.playVideo(video.track)
            } label: {
                VideoRow(video: video)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ResumeCard: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Thumbnail(url: entry.artworkURL, width: 160)
                .overlay(alignment: .bottom) {
                    if let progress = entry.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.red)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 3)
                    }
                }
            Text(entry.title.isEmpty ? entry.videoID : entry.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Text("Parou em \(formatTime(entry.position))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 160, alignment: .leading)
    }
}

@MainActor
final class NativeHomeViewModel: ObservableObject {
    @Published private(set) var recommendations: [CatalogItem] = []
    @Published private(set) var subscriptions: [CatalogItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?

    private let catalog: YouTubeCatalog
    private var continuation: String?
    private var visitorData: String?
    private var loadedSignedIn: Bool?

    private static let subscriptionsLimit = 10

    init(catalog: YouTubeCatalog = .shared) {
        self.catalog = catalog
    }

    func load(signedIn: Bool, force: Bool = false) async {
        guard force || loadedSignedIn != signedIn else { return }
        loadedSignedIn = signedIn
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let home = catalog.home()
        async let feed: CatalogPage? = signedIn ? catalog.subscriptionsFeed() : nil

        do {
            let page = try await home
            recommendations = page.items
            continuation = page.continuation
            visitorData = page.visitorData
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        let subscriptionPage = try? await feed
        subscriptions = Array((subscriptionPage?.items ?? []).prefix(Self.subscriptionsLimit))
    }

    func loadMoreRecommendations(after item: CatalogItem) {
        guard
            !isLoadingMore,
            let continuation,
            let index = recommendations.firstIndex(of: item),
            index >= recommendations.count - 5
        else { return }

        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            guard let page = try? await catalog.home(continuation: continuation, visitorData: visitorData) else { return }
            let known = Set(recommendations.map(\.id))
            recommendations += page.items.filter { !known.contains($0.id) }
            self.continuation = page.continuation
        }
    }
}
