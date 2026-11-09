import SwiftUI
import YouTubePiPCore

/// Uma aba: player nativo (quando ativo), pagina e, abaixo dela, mini player e barra de navegacao.
struct BrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var playback: PlaybackController

    /// Mostra "Inspecionar mídia" no menu. Vale para as duas abas.
    @AppStorage("debugToolsEnabled") private var debugToolsEnabled = false
    @EnvironmentObject private var settings: AppSettings
    @State private var showsNowPlaying = false
    @State private var showsHistory = false
    @State private var showsSearch = false
    @State private var showsLibrary = false
    @EnvironmentObject private var account: AccountSession

    private static let messageDuration: UInt64 = 4_000_000_000

    init(viewModel: BrowserViewModel) {
        self.viewModel = viewModel
        self.playback = viewModel.playback
    }

    var body: some View {
        VStack(spacing: 0) {
            if playback.showsVideo {
                NativeVideoPanel(playback: playback, onPictureInPicture: viewModel.togglePictureInPicture)
            }

            // A pagina continua carregada por baixo do Inicio nativo (login, reserva).
            ZStack {
                YouTubeWebView(viewModel: viewModel)
                    .overlay(alignment: .top) { loadingBar }
                    .opacity(viewModel.showsNativeHome ? 0 : 1)
                    .allowsHitTesting(!viewModel.showsNativeHome)
                    .accessibilityHidden(viewModel.showsNativeHome)

                if viewModel.showsNativeHome {
                    NativeHomeView(
                        isMusic: viewModel.audioOnly,
                        actions: catalogActions,
                        onSignIn: viewModel.signIn,
                        onFailure: viewModel.nativeHomeFailed
                    )
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) { messages }

            // Fora da pagina (nao por cima): a navegacao inferior do site continua acessivel.
            VStack(spacing: 0) {
                Divider()
                if playback.isAudioOnly && playback.isActive {
                    NowPlayingBar(playback: playback) { showsNowPlaying = true }
                    Divider()
                }
                browserToolbar
            }
            .background(.bar)
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.2), value: playback.isActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.transientMessage)
        .task(id: viewModel.transientMessage) {
            guard viewModel.transientMessage != nil else { return }
            try? await Task.sleep(nanoseconds: Self.messageDuration)
            guard !Task.isCancelled else { return }
            viewModel.dismissTransientMessage()
        }
        .onChange(of: playback.isActive) { isActive in
            if !isActive { showsNowPlaying = false }
        }
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingSheet(playback: playback)
        }
        .sheet(isPresented: $showsHistory) {
            HistorySheet()
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryView(
                actions: catalogActions,
                onSignIn: viewModel.signIn
            )
        }
        .sheet(isPresented: $showsSearch) {
            SearchView(
                isMusic: viewModel.audioOnly,
                actions: catalogActions
            )
        }
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
    private var loadingBar: some View {
        if viewModel.isLoading {
            ProgressView(value: max(viewModel.loadingProgress, 0.05))
                .progressViewStyle(.linear)
                .tint(.red)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let message = viewModel.errorMessage {
            // Erro de carregamento: fica ate o usuario agir.
            VStack(spacing: 12) {
                Text(message)
                Button {
                    viewModel.loadHome()
                } label: {
                    Label("Tentar novamente", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(18)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding()
        } else if let message = viewModel.transientMessage {
            // Aviso passageiro: some sozinho ou com um toque.
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .padding()
                .onTapGesture(perform: viewModel.dismissTransientMessage)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Toque para fechar")
        }
    }

    private var browserToolbar: some View {
        HStack {
            Button(action: viewModel.goBack) {
                Image(systemName: "chevron.backward")
            }
            .disabled(!viewModel.canGoBack || viewModel.showsNativeHome)
            .accessibilityLabel("Voltar")

            Spacer()

            // Alterna entre o Inicio nativo e a pagina.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { viewModel.showsNativeHome.toggle() }
            } label: {
                Image(systemName: viewModel.showsNativeHome ? "globe" : "house")
            }
            .accessibilityLabel(viewModel.showsNativeHome ? "Mostrar página" : "Início")

            Spacer()

            Button {
                showsSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Buscar")

            Spacer()

            Button {
                showsLibrary = true
            } label: {
                libraryIcon
            }
            .accessibilityLabel("Biblioteca")

            if viewModel.supportsPictureInPicture {
                Spacer()

                Button(action: viewModel.togglePictureInPicture) {
                    Image(systemName: playback.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel(playback.isPictureInPictureActive ? "Sair do Picture in Picture" : "Picture in Picture")
            }

            Spacer()

            moreMenu
        }
        .font(.title3)
        .padding(.horizontal, 28)
        .frame(height: 48)
    }

    private var catalogActions: CatalogActions {
        CatalogActions(
            isMusic: viewModel.audioOnly,
            playVideo: viewModel.play,
            playTracks: viewModel.play,
            openPage: viewModel.openPage
        )
    }

    /// Foto da conta quando logado; icone generico quando nao.
    @ViewBuilder
    private var libraryIcon: some View {
        if let avatar = account.profile?.avatarURL {
            AsyncImage(url: avatar) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(action: viewModel.goForward) {
                Label("Avançar", systemImage: "chevron.forward")
            }
            .disabled(!viewModel.canGoForward)

            Button(action: viewModel.loadHome) {
                Label("Início da página", systemImage: "globe")
            }

            Button(action: viewModel.reload) {
                Label("Recarregar", systemImage: "arrow.clockwise")
            }

            Button(action: viewModel.openCopiedLink) {
                Label("Abrir link copiado", systemImage: "doc.on.clipboard")
            }

            Button {
                showsHistory = true
            } label: {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
            }

            Divider()

            if !viewModel.audioOnly {
                Toggle(isOn: $settings.youtubeAudioOnly) {
                    Label("Só áudio no YouTube", systemImage: "headphones")
                }
            }

            Picker(selection: $settings.quality) {
                ForEach(StreamQuality.allCases, id: \.self) { quality in
                    Text(quality.title).tag(quality)
                }
            } label: {
                Label("Qualidade: \(settings.quality.title)", systemImage: "dial.medium")
            }
            .pickerStyle(.menu)

            Divider()

            if debugToolsEnabled {
                Button(action: viewModel.inspectCurrentMedia) {
                    Label("Inspecionar mídia", systemImage: "magnifyingglass")
                }
            }

            Toggle(isOn: $debugToolsEnabled) {
                Label("Ferramentas de depuração", systemImage: "ladybug")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Mais opções")
    }
}
