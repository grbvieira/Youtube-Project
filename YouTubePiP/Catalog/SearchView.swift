import SwiftUI
import YouTubePiPCore

/// Busca nativa: sugestoes, buscas recentes e resultados que tocam direto no player nativo.
struct SearchView: View {
    let isMusic: Bool
    let onPlayVideo: (MediaTrack) -> Void
    let onPlayTracks: ([MediaTrack], Int) -> Void
    let onOpenChannel: (String) -> Void

    @StateObject private var model = SearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(isMusic ? "Buscar no YouTube Music" : "Buscar no YouTube")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: isMusic ? "Músicas, artistas, álbuns" : "Vídeos, canais, playlists"
                )
                .searchSuggestions {
                    ForEach(model.suggestions, id: \.self) { suggestion in
                        Button {
                            model.submit(suggestion)
                        } label: {
                            Label(suggestion, systemImage: "magnifyingglass")
                        }
                    }
                }
                .onSubmit(of: .search) { model.submit() }
                .onChange(of: model.query) { query in
                    if query.isEmpty { model.reset() }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fechar") { dismiss() }
                    }
                }
                .navigationDestination(for: CatalogPlaylist.self) { playlist in
                    PlaylistDetailView(playlist: playlist) { tracks, index in
                        dismiss()
                        onPlayTracks(tracks, index)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            recentList
        case .searching:
            ProgressView("Buscando...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            CatalogMessage(
                systemImage: "wifi.exclamationmark",
                title: String(localized: "Não foi possível buscar"),
                message: message
            ) {
                Button("Tentar novamente") { model.submit() }
                    .buttonStyle(.borderedProminent)
            }
        case .results where model.items.isEmpty:
            CatalogMessage(
                systemImage: "magnifyingglass",
                title: String(localized: "Nenhum resultado"),
                message: String(localized: "Tente outras palavras.")
            )
        case .results:
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            ForEach(model.items) { item in
                row(for: item)
                    .onAppear { model.loadMoreIfNeeded(after: item) }
            }
            if model.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func row(for item: CatalogItem) -> some View {
        switch item {
        case .video(let video):
            Button {
                dismiss()
                onPlayVideo(video.track)
            } label: {
                VideoRow(video: video)
            }
            .buttonStyle(.plain)
        case .channel(let channel):
            Button {
                dismiss()
                onOpenChannel(channel.id)
            } label: {
                ChannelRow(channel: channel)
            }
            .buttonStyle(.plain)
        case .playlist(let playlist):
            NavigationLink(value: playlist) {
                PlaylistRow(playlist: playlist)
            }
        }
    }

    @ViewBuilder
    private var recentList: some View {
        let recent = model.matchingRecent
        if recent.isEmpty {
            CatalogMessage(
                systemImage: isMusic ? "music.magnifyingglass" : "magnifyingglass",
                title: String(localized: "Buscar"),
                message: isMusic
                    ? String(localized: "As músicas tocam direto no player, em segundo plano.")
                    : String(localized: "Os vídeos abrem direto no player nativo, com PiP.")
            )
        } else {
            List {
                Section {
                    ForEach(recent, id: \.self) { query in
                        Button {
                            model.submit(query)
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { recent[$0] }.forEach(model.removeRecent)
                    }
                } header: {
                    HStack {
                        Text("Recentes")
                        Spacer()
                        Button("Limpar", action: model.clearRecent)
                            .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Linhas

struct VideoRow: View {
    let video: CatalogVideo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(url: video.track.artworkURL, width: 128)
                .overlay(alignment: .bottomTrailing) {
                    if let duration = video.durationText {
                        Text(duration)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(video.track.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if !video.track.artist.isEmpty {
                    Text(video.track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let details = video.details {
                    Text(details)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct ChannelRow: View {
    let channel: CatalogChannel

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .frame(width: 128)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.subheadline.weight(.semibold))
                Text(channel.subscribers ?? String(localized: "Canal"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

private struct PlaylistRow: View {
    let playlist: CatalogPlaylist

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(url: playlist.thumbnailURL, width: 128)
                .overlay(alignment: .trailing) {
                    VStack(spacing: 2) {
                        Image(systemName: "list.and.film")
                        if let count = playlist.videoCount {
                            Text(count).font(.caption2.weight(.semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .background(.black.opacity(0.7))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(playlist.owner.map { String(localized: "Playlist · \($0)") } ?? String(localized: "Playlist"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// Miniatura 16:9.
struct Thumbnail: View {
    let url: URL?
    let width: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(Color(.secondarySystemFill))
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Estado vazio / erro centralizado.
struct CatalogMessage<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(systemImage: String, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
