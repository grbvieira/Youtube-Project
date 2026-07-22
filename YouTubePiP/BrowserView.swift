import SwiftUI
import UIKit

struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            YouTubeWebView(viewModel: viewModel)

            statusPanel

            browserToolbar
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
            .padding(.bottom, 76)
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
                    Image(systemName: "pip.enter")
                }
                .accessibilityLabel("Picture in Picture")
            }

            if viewModel.audioOnly {
                if viewModel.isNativeAudioActive {
                    Button {
                        viewModel.toggleNativeAudioPlayback()
                    } label: {
                        Image(systemName: viewModel.isNativeAudioPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(viewModel.isNativeAudioPlaying ? "Pausar audio nativo" : "Continuar audio nativo")

                    Button {
                        viewModel.stopNativeAudioPlayback()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .accessibilityLabel("Parar audio nativo")
                }

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
                        Text("Nenhum fluxo direto de audio foi encontrado neste diagnostico.")
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
