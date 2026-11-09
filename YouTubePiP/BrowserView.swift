import SwiftUI
import UIKit

struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.showsNativeVideo {
                NativeVideoPanel(viewModel: viewModel)
            }

            ZStack(alignment: .bottom) {
                YouTubeWebView(viewModel: viewModel)

                VStack(spacing: 8) {
                    statusPanel

                    if viewModel.audioOnly && viewModel.isNativeAudioActive {
                        NowPlayingBar(viewModel: viewModel)
                    }

                    browserToolbar
                }
            }
        }
        .background(Color(.systemBackground))
        .sheet(
            isPresented: Binding(
                get: { viewModel.mediaDiagnostics != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissMediaDiagnostics()
                    }
                }
            )
        ) {
            if let report = viewModel.mediaDiagnostics {
                MediaDiagnosticsView(
                    report: report,
                    canStartNativePlayback: viewModel.hasNativeAudioCandidate,
                    onStartNativePlayback: {
                        viewModel.dismissMediaDiagnostics()
                        viewModel.startNativeAudioPlayback()
                    },
                    onDismiss: viewModel.dismissMediaDiagnostics
                )
            }
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        if viewModel.errorMessage != nil || viewModel.pipMessage != nil {
            VStack(spacing: 12) {
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Button {
                        viewModel.loadHome()
                    } label: {
                        Label("Tentar novamente", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                } else if let message = viewModel.pipMessage {
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal)
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel("Voltar")

            Button {
                viewModel.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel("Avancar")

            Button {
                viewModel.loadHome()
            } label: {
                Image(systemName: "house")
            }
            .accessibilityLabel("Inicio")

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Recarregar")

            if viewModel.supportsPictureInPicture {
                Button {
                    viewModel.startPictureInPicture()
                } label: {
                    Image(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel(viewModel.isPictureInPictureActive ? "Sair do Picture in Picture" : "Picture in Picture")
            }

            if viewModel.audioOnly {
                Button {
                    viewModel.inspectCurrentMedia()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Inspecionar midia")
            }
        }
        .font(.headline)
        .frame(height: 48)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 12)
    }
}

/// Video do player nativo (AVPlayer) com controles. Fica no topo da aba YouTube.
private struct NativeVideoPanel: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var scrubPosition: Double?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NativeVideoSurface(view: viewModel.nativePlayer.videoView)
                if viewModel.isPictureInPictureActive {
                    Label("Tocando em Picture in Picture", systemImage: "pip")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)

            HStack(spacing: 14) {
                Button {
                    viewModel.toggleNativeAudioPlayback()
                } label: {
                    Image(systemName: viewModel.isNativeAudioPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(viewModel.isNativeAudioPlaying ? "Pausar" : "Reproduzir")

                Slider(
                    value: Binding(
                        get: { scrubPosition ?? viewModel.nativeElapsed },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(viewModel.nativeDuration, 1),
                    onEditingChanged: { editing in
                        if !editing, let position = scrubPosition {
                            viewModel.seekNative(to: position)
                            scrubPosition = nil
                        }
                    }
                )
                .disabled(viewModel.nativeDuration <= 0)

                Text(formatTime(scrubPosition ?? viewModel.nativeElapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.startPictureInPicture()
                } label: {
                    Image(systemName: viewModel.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel("Picture in Picture")

                Button {
                    viewModel.stopNativeAudioPlayback()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Fechar player")
            }
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            if !viewModel.nowPlayingTitle.isEmpty {
                Text(viewModel.nowPlayingTitle)
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
private struct NowPlayingBar: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.nowPlayingTitle.isEmpty ? "Carregando..." : viewModel.nowPlayingTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !viewModel.nowPlayingArtist.isEmpty {
                    Text(viewModel.nowPlayingArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.toggleNativeAudioPlayback()
            } label: {
                Image(systemName: viewModel.isNativeAudioPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(viewModel.isNativeAudioPlaying ? "Pausar" : "Reproduzir")

            Button {
                viewModel.skipToNextTrack()
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!viewModel.canSkipToNext)
            .accessibilityLabel("Proxima faixa")

            Button {
                viewModel.stopNativeAudioPlayback()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Fechar player")
        }
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
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

private struct MediaDiagnosticsView: View {
    let report: String
    let canStartNativePlayback: Bool
    let onStartNativePlayback: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: onStartNativePlayback) {
                        Label("Tocar no player nativo", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStartNativePlayback)

                    if !canStartNativePlayback {
                        Text("Nenhuma musica em reproducao foi identificada neste diagnostico.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Text(report)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Diagnostico de midia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = report
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copiar diagnostico")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
