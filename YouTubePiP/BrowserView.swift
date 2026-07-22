import SwiftUI

struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            YouTubeWebView(viewModel: viewModel)

            statusPanel

            browserToolbar
        }
        .background(Color(.systemBackground))
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
        HStack(spacing: 22) {
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
        }
        .font(.headline)
        .frame(height: 48)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 12)
    }
}
