import SwiftUI
import YouTubePiPCore

/// Playlist nativa: lista os videos e toca tudo (ou a partir de um item) no player nativo.
struct PlaylistDetailView: View {
    let playlist: CatalogPlaylist
    let onPlay: ([MediaTrack], Int) -> Void

    @State private var tracks: [MediaTrack] = []
    @State private var title = ""
    @State private var owner: String?
    @State private var continuation: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Carregando playlist...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                CatalogMessage(
                    systemImage: "exclamationmark.triangle",
                    title: String(localized: "Não foi possível abrir a playlist"),
                    message: errorMessage
                ) {
                    Button("Tentar novamente") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                list
            }
        }
        .navigationTitle(title.isEmpty ? playlist.title : title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let owner = owner ?? playlist.owner {
                        Text(owner).font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button {
                            onPlay(tracks, 0)
                        } label: {
                            Label("Tocar tudo", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onPlay(tracks.shuffled(), 0)
                        } label: {
                            Label("Aleatório", systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(tracks.isEmpty)
                }
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        onPlay(tracks, index)
                    } label: {
                        VideoRow(video: CatalogVideo(
                            track: track,
                            durationText: track.duration.map(formatTime),
                            details: nil
                        ))
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if index >= tracks.count - 5 { Task { await loadMore() } }
                    }
                }
                if isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                Text("\(tracks.count) vídeos")
            }
        }
        .listStyle(.plain)
    }

    private func load() async {
        guard tracks.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let page = try await YouTubeCatalog.shared.playlist(playlist.id)
            tracks = page.tracks
            title = page.title
            owner = page.owner
            continuation = page.continuation
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, let token = continuation else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await YouTubeCatalog.shared.morePlaylistVideos(token) else { return }
        tracks += page.tracks
        continuation = page.continuation
    }
}
