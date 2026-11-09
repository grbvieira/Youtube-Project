import SwiftUI

/// Video do player nativo com controles. Fica no topo da aba YouTube.
struct NativeVideoPanel: View {
    @ObservedObject var playback: PlaybackController
    let onPictureInPicture: () -> Void

    @State private var scrubPosition: Double?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NativeVideoSurface(view: playback.player.videoView)
                if playback.isPictureInPictureActive {
                    Label("Tocando em Picture in Picture", systemImage: "pip")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)

            HStack(spacing: 14) {
                PlayPauseButton(playback: playback)

                Slider(
                    value: Binding(
                        get: { scrubPosition ?? playback.elapsed },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(playback.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let position = scrubPosition {
                            playback.seek(to: position)
                            scrubPosition = nil
                        }
                    }
                )
                .disabled(playback.duration <= 0)

                Text(formatTime(scrubPosition ?? playback.elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: onPictureInPicture) {
                    Image(systemName: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel("Picture in Picture")

                CloseButton(playback: playback)
            }
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            if !playback.title.isEmpty {
                Text(playback.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .background(.regularMaterial)
            }
        }
    }
}

/// Mini player da aba YouTube Music (somente audio).
struct NowPlayingBar: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.title.isEmpty ? String(localized: "Carregando...") : playback.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !playback.artist.isEmpty {
                    Text(playback.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PlayPauseButton(playback: playback)

            Button(action: playback.skipToNext) {
                Image(systemName: "forward.fill")
            }
            .disabled(!playback.canSkipToNext)
            .accessibilityLabel("Próxima faixa")

            CloseButton(playback: playback)
        }
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }
}

private struct PlayPauseButton: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Button(action: playback.togglePlayPause) {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
        }
        .accessibilityLabel(playback.isPlaying ? "Pausar" : "Reproduzir")
    }
}

private struct CloseButton: View {
    let playback: PlaybackController

    var body: some View {
        Button(action: playback.stop) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Fechar player")
    }
}

private struct NativeVideoSurface: UIViewRepresentable {
    let view: PlayerLayerView

    func makeUIView(context: Context) -> PlayerLayerView { view }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
