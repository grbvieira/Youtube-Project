import SwiftUI
import WebKit

struct YouTubeWebView: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: viewModel.audioOnly ? BrowserViewModel.audioOnlyScript : BrowserViewModel.prepareVideoElementsScript,
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
            viewModel.attach(webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let viewModel: BrowserViewModel

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.isLoading = true
            viewModel.errorMessage = nil
            updateNavigationState(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.isLoading = false
            if viewModel.audioOnly {
                viewModel.prepareAudioOnlyMode()
            } else {
                viewModel.prepareVideoElements()
            }
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
            viewModel.isLoading = false
            updateNavigationState(webView)

            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }

            viewModel.errorMessage = "Nao foi possivel carregar o \(viewModel.serviceName). Verifique sua conexao e tente novamente."
        }

        private func updateNavigationState(_ webView: WKWebView) {
            viewModel.canGoBack = webView.canGoBack
            viewModel.canGoForward = webView.canGoForward
        }
    }
}
