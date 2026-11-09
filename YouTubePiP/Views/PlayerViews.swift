import SwiftUI

/// Video do player nativo com controles. Fica no topo da aba YouTube.
struct NativeVideoPanel: View {
    @ObservedObject var playback: PlaybackController
    let onPictureInPicture: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NativeVideoSurface(view: playback.player.videoView)
                if playback.isPictureInPictureActive {
                    Label("Tocando em Picture in Picture", systemImage: "pip")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                } else if playback.isPreparing {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)

            HStack(spacing: 14) {
                PlayPauseButton(playback: playback)

                TimeSlider(playback: playback, showsTotal: false)

                Button(action: onPictureInPicture) {
                    Image(systemName: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel("Picture in Picture")

                CloseButton(playback: playback)
            }
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    SleepTimerBadge(playback: playback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PlayerOptionsMenu(playback: playback)
                    .font(.headline)
                RoutePickerButton()
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .background(.bar)
    }
}

/// Mini player da aba YouTube Music. Tocar no titulo abre "Tocando agora".
struct NowPlayingBar: View {
    @ObservedObject var playback: PlaybackController
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: min(playback.elapsed, max(playback.duration, 1)), total: max(playback.duration, 1))
                .progressViewStyle(.linear)
                .tint(.primary)
                .scaleEffect(x: 1, y: 0.5, anchor: .top)

            HStack(spacing: 12) {
                Button(action: onExpand) {
                    HStack(spacing: 10) {
                        ArtworkView(url: playback.artworkURL, size: 40)

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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir Tocando agora")

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
            .padding(.vertical, 8)
        }
    }
}

/// Barra de tempo arrastavel com o tempo decorrido (e o total, opcionalmente).
struct TimeSlider: View {
    @ObservedObject var playback: PlaybackController
    var showsTotal = true

    @State private var scrubPosition: Double?

    var body: some View {
        let position = scrubPosition ?? playback.elapsed

        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(get: { position }, set: { scrubPosition = $0 }),
                    in: 0...max(playback.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let target = scrubPosition {
                            playback.seek(to: target)
                            scrubPosition = nil
                        }
                    }
                )
                .disabled(playback.duration <= 0)

                if !showsTotal {
                    Text(formatTime(position))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if showsTotal {
                HStack {
                    Text(formatTime(position))
                    Spacer()
                    Text("-" + formatTime(max(playback.duration - position, 0)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlayPauseButton: View {
    @ObservedObject var playback: PlaybackController

    var body: some View {
        Group {
            if playback.isPreparing {
                ProgressView()
            } else {
                Button(action: playback.togglePlayPause) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(playback.isPlaying ? "Pausar" : "Reproduzir")
            }
        }
        .frame(minWidth: 24)
    }
}

struct CloseButton: View {
    let playback: PlaybackController

    var body: some View {
        Button(action: playback.stop) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Fechar player")
    }
}

/// Capa da faixa, com um icone enquanto carrega ou quando nao ha imagem.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))
    }
}

private struct NativeVideoSurface: UIViewRepresentable {
    let view: PlayerLayerView

    func makeUIView(context: Context) -> PlayerLayerView { view }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
