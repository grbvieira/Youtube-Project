import SwiftUI
import YouTubePiPCore

/// Capitulos e comentarios do video que esta tocando.
struct VideoDetailsSheet: View {
    enum Section: Hashable {
        case chapters, comments
    }

    @ObservedObject var playback: PlaybackController
    @State var section: Section
    @Environment(\.dismiss) private var dismiss

    init(playback: PlaybackController, initialSection: Section? = nil) {
        self.playback = playback
        _section = State(initialValue: initialSection ?? (playback.chapters.isEmpty ? .comments : .chapters))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !playback.chapters.isEmpty {
                    Picker("Seção", selection: $section) {
                        Text("Capítulos").tag(Section.chapters)
                        Text(playback.commentsCount.map { String(localized: "Comentários (\($0))") } ?? String(localized: "Comentários"))
                            .tag(Section.comments)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                switch section {
                case .chapters:
                    ChapterList(playback: playback)
                case .comments:
                    CommentsList(videoID: playback.currentTrackID, token: playback.commentsContinuation)
                }
            }
            .navigationTitle(playback.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Lista de capitulos: o atual em destaque; tocar pula para ele.
struct ChapterList: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(playback.chapters.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        playback.seek(toChapter: index)
                    } label: {
                        HStack {
                            Text(formatTime(chapter.start))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                            Text(chapter.title.isEmpty ? String(localized: "Capítulo \(index + 1)") : chapter.title)
                                .font(.subheadline.weight(index == playback.currentChapterIndex ? .bold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if index == playback.currentChapterIndex {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(index)
                }
            }
            .listStyle(.plain)
            .onAppear {
                if let current = playback.currentChapterIndex { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }
}

/// Comentarios do video, com rolagem infinita.
struct CommentsList: View {
    let videoID: String?
    let token: String?

    @State private var comments: [CatalogComment] = []
    @State private var continuation: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedFor: String?

    var body: some View {
        Group {
            if token == nil && comments.isEmpty {
                CatalogMessage(
                    systemImage: "text.bubble",
                    title: String(localized: "Sem comentários"),
                    message: String(localized: "Os comentários estão desativados ou ainda estão carregando.")
                )
            } else if let errorMessage, comments.isEmpty {
                CatalogMessage(systemImage: "exclamationmark.triangle", title: String(localized: "Não foi possível carregar"), message: errorMessage) {
                    Button("Tentar novamente") { Task { await loadFirstPage(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
            } else if comments.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                            .onAppear {
                                if comment.id == comments.last?.id { Task { await loadMore() } }
                            }
                    }
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task(id: videoID) { await loadFirstPage() }
    }

    private func loadFirstPage(force: Bool = false) async {
        guard let token, force || loadedFor != videoID else { return }
        loadedFor = videoID
        comments = []
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await YouTubeCatalog.shared.comments(token: token, isFirstPage: true)
            comments = page.comments
            continuation = page.continuation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoading, let next = continuation else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await YouTubeCatalog.shared.comments(token: next, isFirstPage: false) else { return }
        let known = Set(comments.map(\.id))
        comments += page.comments.filter { !known.contains($0.id) }
        continuation = page.continuation
    }
}

private struct CommentRow: View {
    let comment: CatalogComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: comment.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author).font(.caption.weight(.semibold))
                    if let time = comment.timePosted {
                        Text(time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(comment.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                HStack(spacing: 14) {
                    if let likes = comment.likes, !likes.isEmpty {
                        Label(likes, systemImage: "hand.thumbsup")
                    }
                    if let replies = comment.repliesCount, !replies.isEmpty, replies != "0" {
                        Label(replies, systemImage: "arrowshape.turn.up.left")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
