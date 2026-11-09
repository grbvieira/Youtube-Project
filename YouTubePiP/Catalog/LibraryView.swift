import SwiftUI
import YouTubePiPCore

/// Biblioteca da conta: playlists (incluindo "Gostei" e "Assistir mais tarde"),
/// videos novos das inscricoes e canais inscritos.
struct LibraryView: View {
    let actions: CatalogActions
    let onSignIn: () -> Void

    @EnvironmentObject private var account: AccountSession
    @StateObject private var model = LibraryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch account.state {
                case .unknown:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .signedOut:
                    signedOut
                case .signedIn(let profile):
                    signedIn(profile)
                }
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .catalogDestinations(actions, onLeave: { dismiss() })
        }
        .task { await account.refresh() }
    }

    private var signedOut: some View {
        CatalogMessage(
            systemImage: "person.crop.circle.badge.questionmark",
            title: String(localized: "Entre na sua conta"),
            message: String(localized: "O login é feito na página do YouTube. Depois de entrar, suas playlists e inscrições aparecem aqui.")
        ) {
            Button {
                dismiss()
                onSignIn()
            } label: {
                Label("Entrar no YouTube", systemImage: "person.crop.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func signedIn(_ profile: AccountProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: profile.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.headline)
                    if let handle = profile.handle {
                        Text(handle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Picker("Seção", selection: $model.section) {
                Text("Playlists").tag(LibraryViewModel.Section.playlists)
                Text("Novidades").tag(LibraryViewModel.Section.feed)
                Text("Canais").tag(LibraryViewModel.Section.channels)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            sectionContent
                .frame(maxHeight: .infinity)
        }
        .task(id: model.section) { await model.loadSection() }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let error = model.errorMessage {
            CatalogMessage(systemImage: "exclamationmark.triangle", title: String(localized: "Não foi possível carregar"), message: error) {
                Button("Tentar novamente") { Task { await model.loadSection(force: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Abrir na página") {
                    dismiss()
                    actions.openPage(model.section == .playlists
                        ? PageURL.library(isMusic: actions.isMusic)
                        : PageURL.subscriptions(isMusic: actions.isMusic))
                }
            }
        } else {
            switch model.section {
            case .playlists: playlists
            case .feed: feed
            case .channels: channels
            }
        }
    }

    @ViewBuilder
    private var playlists: some View {
        if let library = model.library {
            List {
                if library.likes != nil || library.watchLater != nil {
                    Section {
                        if let likes = library.likes {
                            NavigationLink(value: likes) {
                                Label("Gostei", systemImage: "hand.thumbsup.fill")
                            }
                        }
                        if let watchLater = library.watchLater {
                            NavigationLink(value: watchLater) {
                                Label("Assistir mais tarde", systemImage: "clock.fill")
                            }
                        }
                    }
                }
                Section("Suas playlists") {
                    if library.playlists.isEmpty {
                        Text("Nenhuma playlist").foregroundStyle(.secondary)
                    }
                    ForEach(library.playlists, id: \.id) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistRow(playlist: playlist)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.loadSection(force: true) }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var feed: some View {
        if let items = model.feed {
            if items.isEmpty {
                CatalogMessage(systemImage: "play.square.stack", title: String(localized: "Nada novo"), message: String(localized: "Vídeos novos dos seus canais aparecem aqui."))
            } else {
                List {
                    ForEach(items) { item in
                        if case .video(let video) = item {
                            Button {
                                dismiss()
                                actions.playVideo(video.track)
                            } label: {
                                VideoRow(video: video)
                            }
                            .buttonStyle(.plain)
                            .onAppear { model.loadMoreFeed(after: item) }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.loadSection(force: true) }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var channels: some View {
        if let channels = model.channels {
            List {
                ForEach(channels, id: \.id) { channel in
                    NavigationLink(value: channel) {
                        ChannelRow(channel: channel)
                    }
                    .onAppear { model.loadMoreChannels(after: channel) }
                }
            }
            .listStyle(.plain)
            .refreshable { await model.loadSection(force: true) }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    enum Section: Hashable {
        case playlists, feed, channels
    }

    @Published var section: Section = .playlists
    @Published private(set) var library: LibrarySummary?
    @Published private(set) var feed: [CatalogItem]?
    @Published private(set) var channels: [CatalogChannel]?
    @Published private(set) var errorMessage: String?

    private let catalog: YouTubeCatalog
    private var feedContinuation: String?
    private var channelsContinuation: String?
    private var isLoadingMore = false

    init(catalog: YouTubeCatalog = .shared) {
        self.catalog = catalog
    }

    func loadSection(force: Bool = false) async {
        errorMessage = nil
        do {
            switch section {
            case .playlists:
                guard force || library == nil else { return }
                library = try await catalog.library()
            case .feed:
                guard force || feed == nil else { return }
                let page = try await catalog.subscriptionsFeed()
                feed = page.items
                feedContinuation = page.continuation
            case .channels:
                guard force || channels == nil else { return }
                let page = try await catalog.subscriptions()
                channels = page.channels
                channelsContinuation = page.continuation
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreFeed(after item: CatalogItem) {
        guard let feed, !isLoadingMore, let token = feedContinuation,
              let index = feed.firstIndex(of: item), index >= feed.count - 5
        else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            guard let page = try? await catalog.subscriptionsFeed(continuation: token) else { return }
            let known = Set(feed.map(\.id))
            self.feed = (self.feed ?? []) + page.items.filter { !known.contains($0.id) }
            feedContinuation = page.continuation
        }
    }

    func loadMoreChannels(after channel: CatalogChannel) {
        guard let channels, !isLoadingMore, let token = channelsContinuation,
              let index = channels.firstIndex(of: channel), index >= channels.count - 5
        else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            guard let page = try? await catalog.subscriptions(continuation: token) else { return }
            self.channels = (self.channels ?? []) + page.channels
            channelsContinuation = page.continuation
        }
    }
}
