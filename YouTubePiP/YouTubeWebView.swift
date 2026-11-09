import SwiftUI
import WebKit

struct YouTubeWebView: UIViewRepresentable {
    let viewModel: BrowserViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()

        let contentController = configuration.userContentController
        contentController.add(
            WeakScriptMessageHandler(context.coordinator),
            name: BrowserViewModel.mediaEventsHandlerName
        )
        contentController.addUserScript(
            WKUserScript(
                source: BrowserViewModel.mediaEventsScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        contentController.addUserScript(
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

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let viewModel: BrowserViewModel

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            viewModel.handleMediaEvent(message.body)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.navigationStarted(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.navigationFinished(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.navigationFailed(in: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel.navigationFailed(in: webView, error: error)
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
    }
}

/// `WKUserContentController` retem o handler com referencia forte; este proxy evita o ciclo.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
