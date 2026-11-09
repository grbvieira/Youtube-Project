import SwiftUI
import YouTubePiPCore

/// "Tocando agora" do YouTube Music: capa, controles e a fila (tocar, reordenar, remover).
struct NowPlayingSheet: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var showsComments = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                }

                if !playback.chapters.isEmpty {
                    Section("Capítulos") {
                        ForEach(Array(playback.chapters.enumerated()), id: \.offset) { index, chapter in
                            Button {
                                playback.seek(toChapter: index)
                            } label: {
                                HStack {
                                    Text(formatTime(chapter.start))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 56, alignment: .leading)
                                    Text(chapter.title)
                                        .font(.subheadline.weight(index == playback.currentChapterIndex ? .bold : .regular))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if index == playback.currentChapterIndex {
                                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    ForEach(Array(playback.queueTracks.enumerated()), id: \.offset) { index, track in
                        QueueRow(track: track, isCurrent: index == playback.currentIndex) {
                            playback.jump(to: index)
                        }
                        .deleteDisabled(index == playback.currentIndex)
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) {
                            playback.removeFromQueue(at: index)
                        }
                    }
                    .onMove { offsets, destination in
                        guard let source = offsets.first else { return }
                        playback.moveInQueue(from: source, to: destination)
                    }
                } header: {
                    Text("Fila (\(playback.queueTracks.count))")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tocando agora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsComments) {
            VideoDetailsSheet(playback: playback, initialSection: .comments)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ArtworkView(url: playback.artworkURL, size: 220)
                .shadow(radius: 8, y: 4)

            VStack(spacing: 4) {
                Text(playback.title.isEmpty ? String(localized: "Carregando...") : playback.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !playback.artist.isEmpty {
                    Text(playback.artist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            TimeSlider(playback: playback)

            HStack(spacing: 44) {
                Button(action: playback.skipToPrevious) {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Faixa anterior")

                PlayPauseButton(playback: playback)
                    .font(.largeTitle)

                Button(action: playback.skipToNext) {
                    Image(systemName: "forward.fill")
                }
                .disabled(!playback.canSkipToNext)
                .accessibilityLabel("Próxima faixa")
            }
            .font(.title)
            .buttonStyle(.plain)

            HStack(spacing: 28) {
                AccountActionsView(videoID: playback.currentTrackID)
                    .font(.title3)
                if playback.commentsContinuation != nil {
                    Button {
                        showsComments = true
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                    .font(.title3)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Comentários")
                }
                PlayerOptionsMenu(playback: playback)
                    .font(.title3)
                RoutePickerButton()
                    .frame(width: 32, height: 32)
            }

            SleepTimerBadge(playback: playback)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QueueRow: View {
    let track: MediaTrack
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkView(url: track.artworkURL, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title.isEmpty ? track.videoID : track.title)
                        .font(.subheadline.weight(isCurrent ? .bold : .regular))
                        .lineLimit(1)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Tocando")
                } else if let duration = track.duration {
                    Text(formatTime(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
