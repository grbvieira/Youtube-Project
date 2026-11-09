import SwiftUI
import YouTubePiPCore

/// Pagina nativa de canal/artista: cabecalho, inscricao e abas (videos, shorts, ao vivo, playlists).
struct ChannelView: View {
    let channel: CatalogChannel
    let actions: CatalogActions
    let onLeave: () -> Void

    @StateObject private var model: ChannelViewModel
    @EnvironmentObject private var account: AccountSession

    init(channel: CatalogChannel, actions: CatalogActions, onLeave: @escaping () -> Void) {
        self.channel = channel
        self.actions = actions
        self.onLeave = onLeave
        _model = StateObject(wrappedValue: ChannelViewModel(channelID: channel.id))
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            if let details = model.details, details.tabs.count > 1 {
                Picker("Aba", selection: $model.tab) {
                    ForEach(details.tabs, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }

            tabContent
        }
        .listStyle(.plain)
        .navigationTitle(model.details?.name ?? channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: openPage) {
                        Label("Abrir na página", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await model.loadDetails() }
        .task(id: model.tab) { await model.loadTab() }
        .refreshable { await model.reload() }
        .alert("Não foi possível atualizar a inscrição", isPresented: Binding(
            get: { model.subscriptionError != nil },
            set: { if !$0 { model.subscriptionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.subscriptionError ?? "")
        }
    }

    private func openPage() {
        onLeave()
        actions.openPage(PageURL.channel(channel.id, isMusic: actions.isMusic))
    }

    private var header: some View {
        VStack(spacing: 10) {
            AsyncImage(url: model.details?.bannerURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(.secondarySystemFill))
            }
            .frame(height: 90)
            .frame(maxWidth: .infinity)
            .clipped()

            HStack(spacing: 12) {
                AsyncImage(url: model.details?.avatarURL ?? channel.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.details?.name ?? channel.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    Text([model.details?.handle, model.details?.subscribers ?? channel.subscribers]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            if account.isSignedIn, let subscribed = model.isSubscribed {
                Button {
                    Task { await model.toggleSubscription() }
                } label: {
                    Label(
                        subscribed ? String(localized: "Inscrito") : String(localized: "Inscrever-se"),
                        systemImage: subscribed ? "bell.fill" : "person.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(subscribed ? .gray : .red)
                .disabled(model.isUpdatingSubscription)
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        let items = model.items[model.tab] ?? []

        if let error = model.errorMessage {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Abrir na página", action: openPage)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if model.items[model.tab] == nil {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if items.isEmpty {
            Text("Nada por aqui.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            let tracks = items.compactMap { item -> MediaTrack? in
                if case .video(let video) = item { return video.track }
                return nil
            }
            if tracks.count > 1 {
                Button {
                    onLeave()
                    actions.playTracks(tracks, 0)
                } label: {
                    Label("Tocar tudo", systemImage: "play.fill")
                }
            }

            ForEach(items) { item in
                Group {
                    switch item {
                    case .video(let video):
                        Button {
                            onLeave()
                            if let index = tracks.firstIndex(of: video.track), tracks.count > 1 {
                                actions.playTracks(tracks, index)
                            } else {
                                actions.playVideo(video.track)
                            }
                        } label: {
                            VideoRow(video: video)
                        }
                        .buttonStyle(.plain)
                    case .playlist(let playlist):
                        NavigationLink(value: playlist) {
                            PlaylistRow(playlist: playlist)
                        }
                    case .channel(let channel):
                        NavigationLink(value: channel) {
                            ChannelRow(channel: channel)
                        }
                    }
                }
                .onAppear { model.loadMoreIfNeeded(after: item) }
            }

            if model.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }
}

@MainActor
final class ChannelViewModel: ObservableObject {
    @Published var tab: ChannelTab = .videos
    @Published private(set) var details: ChannelDetails?
    @Published private(set) var items: [ChannelTab: [CatalogItem]] = [:]
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSubscribed: Bool?
    @Published private(set) var isUpdatingSubscription = false
    @Published var subscriptionError: String?

    private let channelID: String
    private let catalog: YouTubeCatalog
    private var continuations: [ChannelTab: String] = [:]

    init(channelID: String, catalog: YouTubeCatalog = .shared) {
        self.channelID = channelID
        self.catalog = catalog
    }

    func loadDetails() async {
        guard details == nil else { return }
        do {
            let details = try await catalog.channel(channelID)
            self.details = details
            isSubscribed = details.isSubscribed
            if !details.tabs.contains(tab), let first = details.tabs.first {
                tab = first
            } else {
                await loadTab()
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTab() async {
        guard details != nil, items[tab] == nil else { return }
        let tab = tab
        do {
            let page = try await catalog.channelItems(channelID, tab: tab)
            items[tab] = page.items
            continuations[tab] = page.continuation
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        details = nil
        items = [:]
        continuations = [:]
        errorMessage = nil
        await loadDetails()
    }

    func loadMoreIfNeeded(after item: CatalogItem) {
        let tab = tab
        guard
            !isLoadingMore,
            continuations[tab] != nil,
            let current = items[tab],
            let index = current.firstIndex(of: item),
            index >= current.count - 5
        else { return }

        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            guard let page = try? await catalog.moreChannelItems(channelID, tab: tab) else { return }
            let known = Set((items[tab] ?? []).map(\.id))
            items[tab, default: []] += page.items.filter { !known.contains($0.id) }
            continuations[tab] = page.continuation
        }
    }

    func toggleSubscription() async {
        guard let subscribed = isSubscribed else { return }
        isUpdatingSubscription = true
        isSubscribed = !subscribed
        do {
            try await catalog.setSubscribed(!subscribed, channelID: channelID)
        } catch {
            isSubscribed = subscribed
            subscriptionError = error.localizedDescription
        }
        isUpdatingSubscription = false
    }
}
