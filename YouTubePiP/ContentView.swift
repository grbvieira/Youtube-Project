import SwiftUI
import WebKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var webViewModel = WebViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            YouTubeWebView(model: webViewModel)

            statusPanel

            browserToolbar
        }
        .background(Color(.systemBackground))
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                webViewModel.prepareForBackgroundPlayback()
            }
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        if webViewModel.errorMessage != nil || webViewModel.pipMessage != nil {
            VStack(spacing: 12) {
                if let message = webViewModel.errorMessage {
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Button {
                        webViewModel.loadHome()
                    } label: {
                        Label("Tentar novamente", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                } else if let message = webViewModel.pipMessage {
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
                webViewModel.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!webViewModel.canGoBack)
            .accessibilityLabel("Voltar")

            Button {
                webViewModel.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!webViewModel.canGoForward)
            .accessibilityLabel("Avancar")

            Button {
                webViewModel.loadHome()
            } label: {
                Image(systemName: "house")
            }
            .accessibilityLabel("Inicio")

            Button {
                webViewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Recarregar")

            Button {
                webViewModel.startPictureInPicture()
            } label: {
                Image(systemName: "pip.enter")
            }
            .accessibilityLabel("Picture in Picture")
        }
        .font(.headline)
        .frame(height: 48)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 12)
    }
}

final class WebViewModel: ObservableObject {
    let homeURL = URL(string: "https://www.youtube.com")!

    weak var webView: WKWebView?

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pipMessage: String?

    func attach(_ webView: WKWebView) {
        self.webView = webView

        if webView.url == nil {
            loadHome()
        }
    }

    func loadHome() {
        errorMessage = nil
        pipMessage = nil
        webView?.load(URLRequest(url: homeURL))
    }

    func reload() {
        errorMessage = nil
        pipMessage = nil

        if webView?.url == nil {
            loadHome()
        } else {
            webView?.reload()
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func startPictureInPicture() {
        runPictureInPictureScript(shouldShowResult: true)
    }

    func prepareForBackgroundPlayback() {
        runPictureInPictureScript(shouldShowResult: false)
    }

    func prepareVideoElements() {
        webView?.evaluateJavaScript(Self.prepareVideoElementsScript)
    }

    private func runPictureInPictureScript(shouldShowResult: Bool) {
        guard let webView else {
            if shouldShowResult {
                pipMessage = "A pagina ainda nao esta pronta para iniciar o PiP."
            }
            return
        }

        pipMessage = shouldShowResult ? "Tentando iniciar Picture in Picture..." : nil
        webView.evaluateJavaScript(Self.startPictureInPictureScript) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, shouldShowResult else { return }

                if let error {
                    self.pipMessage = "Nao foi possivel iniciar o PiP: \(error.localizedDescription)"
                    return
                }

                self.pipMessage = (result as? String) ?? "Solicitacao de PiP enviada ao player."
            }
        }
    }

    static let prepareVideoElementsScript = """
    (() => {
        const prepare = () => {
            document.querySelectorAll('video').forEach((video) => {
                video.setAttribute('playsinline', '');
                video.setAttribute('webkit-playsinline', '');
                video.disablePictureInPicture = false;
                video.controls = true;
            });
        };

        prepare();
        if (!window.__youtubePiPObserver) {
            window.__youtubePiPObserver = new MutationObserver(prepare);
            window.__youtubePiPObserver.observe(document.documentElement, { childList: true, subtree: true });
        }
    })();
    """

    private static let startPictureInPictureScript = """
    (async () => {
        const videos = Array.from(document.querySelectorAll('video'));
        const video = videos.find((item) => !item.paused && item.readyState > 0) || videos.find((item) => item.readyState > 0) || videos[0];

        if (!video) {
            return 'Nenhum video foi encontrado na pagina. Abra e toque em um video antes de iniciar o PiP.';
        }

        video.setAttribute('playsinline', '');
        video.setAttribute('webkit-playsinline', '');
        video.disablePictureInPicture = false;
        video.controls = true;

        try {
            if (document.pictureInPictureElement) {
                return 'O Picture in Picture ja esta ativo.';
            }

            if (video.webkitSupportsPresentationMode && typeof video.webkitSetPresentationMode === 'function') {
                video.webkitSetPresentationMode('picture-in-picture');
                return 'Picture in Picture solicitado ao player.';
            }

            if (document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function') {
                await video.requestPictureInPicture();
                return 'Picture in Picture solicitado ao player.';
            }

            return 'Este player do YouTube nao liberou Picture in Picture nesta WebView.';
        } catch (error) {
            return 'O YouTube ou o iOS recusou o Picture in Picture para este video.';
        }
    })();
    """
}

struct YouTubeWebView: UIViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebViewModel.prepareVideoElementsScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        DispatchQueue.main.async {
            model.attach(webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: WebViewModel

        init(model: WebViewModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
            model.errorMessage = nil
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            model.prepareVideoElements()
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finishWithError(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finishWithError(error, webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }

            return nil
        }

        private func finishWithError(_ error: Error, webView: WKWebView) {
            model.isLoading = false
            updateNavigationState(webView)

            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }

            model.errorMessage = "Nao foi possivel carregar o YouTube. Verifique sua conexao e tente novamente."
        }

        private func updateNavigationState(_ webView: WKWebView) {
            model.canGoBack = webView.canGoBack
            model.canGoForward = webView.canGoForward
        }
    }
}
