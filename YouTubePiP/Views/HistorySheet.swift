import SwiftUI
import YouTubePiPCore

/// Historico de reproducao: tocar de novo (continuando de onde parou), remover ou limpar.
struct HistorySheet: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            Button {
                                dismiss()
                                LinkRouter.shared.open(YouTubeLink(videoID: entry.videoID, isMusic: entry.isMusic))
                            } label: {
                                HistoryRow(entry: entry, resumePosition: history.resumePosition(for: entry.videoID))
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { history.entries[$0].videoID }
                            ids.forEach(history.remove(videoID:))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Histórico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Limpar", role: .destructive) { confirmsClear = true }
                        .disabled(history.entries.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .confirmationDialog("Apagar todo o histórico?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Apagar histórico", role: .destructive, action: history.clear)
            } message: {
                Text("As posições salvas para continuar de onde parou também serão apagadas.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Nada por aqui ainda")
                .font(.headline)
            Text("Vídeos e músicas tocados no player aparecem aqui.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let resumePosition: TimeInterval?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: entry.artworkURL, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.isEmpty ? entry.videoID : entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: entry.isMusic ? "music.note" : "play.rectangle")
                    if !entry.artist.isEmpty {
                        Text(entry.artist).lineLimit(1)
                    }
                    Text(entry.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let resumePosition {
                    Text("Continuar de \(formatTime(resumePosition))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                }

                if let progress = entry.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
