import SwiftUI
import UIKit
import WebKit
import YouTubePiPCore

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
        // As duas abas compartilham cookies: o login vale para YouTube e YouTube Music.
        configuration.websiteDataStore = .default()

        let contentController = configuration.userContentController
        contentController.add(WeakScriptMessageHandler(context.coordinator), name: WebMediaBridge.messageHandlerName)
        WebMediaBridge.userScripts(audioOnly: viewModel.audioOnly).forEach(contentController.addUserScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        // Permite inspecionar a pagina pelo Safari do Mac (Desenvolvedor > iPhone).
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

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

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            viewModel.bridge.handle(messageBody: message.body)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }

            switch LinkPolicy.decide(
                url: url,
                isUserLink: navigationAction.navigationType == .linkActivated,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true
            ) {
            case .allow:
                return .allow
            case .openExternally:
                await UIApplication.shared.open(url)
                return .cancel
            case .cancel:
                return .cancel
            }
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

        /// `target=_blank`: links do YouTube abrem na mesma aba; links externos vao para o Safari.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }

            switch LinkPolicy.decide(url: url, isUserLink: true, isMainFrame: false, opensNewWindow: true) {
            case .allow:
                webView.load(navigationAction.request)
            case .openExternally:
                UIApplication.shared.open(url)
            case .cancel:
                break
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
