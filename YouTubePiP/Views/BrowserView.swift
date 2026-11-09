import SwiftUI

/// Uma aba: player nativo (quando ativo), pagina, mensagens e barra de navegacao.
struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var playback: PlaybackController

    init(viewModel: BrowserViewModel) {
        self.viewModel = viewModel
        self.playback = viewModel.playback
    }

    var body: some View {
        VStack(spacing: 0) {
            if playback.showsVideo {
                NativeVideoPanel(playback: playback, onPictureInPicture: viewModel.togglePictureInPicture)
            }

            ZStack(alignment: .bottom) {
                YouTubeWebView(viewModel: viewModel)

                VStack(spacing: 8) {
                    statusPanel

                    if playback.audioOnly && playback.isActive {
                        NowPlayingBar(playback: playback)
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
                    canStartNativePlayback: viewModel.hasMediaCandidate,
                    onStartNativePlayback: viewModel.playDiagnosticsSnapshot,
                    onDismiss: viewModel.dismissMediaDiagnostics
                )
            }
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        if let message = viewModel.errorMessage {
            messageCard {
                Text(message)
                Button {
                    viewModel.loadHome()
                } label: {
                    Label("Tentar novamente", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let message = viewModel.statusMessage ?? playback.message {
            messageCard {
                Text(message)
            }
        }
    }

    private func messageCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12, content: content)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal)
    }

    private var browserToolbar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.goBack) {
                Image(systemName: "chevron.backward")
            }
            .disabled(!viewModel.canGoBack)
            .accessibilityLabel("Voltar")

            Button(action: viewModel.goForward) {
                Image(systemName: "chevron.forward")
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityLabel("Avançar")

            Button(action: viewModel.loadHome) {
                Image(systemName: "house")
            }
            .accessibilityLabel("Início")

            Button(action: viewModel.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Recarregar")

            if viewModel.supportsPictureInPicture {
                Button(action: viewModel.togglePictureInPicture) {
                    Image(systemName: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel(playback.isPictureInPictureActive ? "Sair do Picture in Picture" : "Picture in Picture")
            }

            if viewModel.audioOnly {
                Button(action: viewModel.inspectCurrentMedia) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Inspecionar mídia")
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
