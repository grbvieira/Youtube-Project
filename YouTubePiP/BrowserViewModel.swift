import Foundation
import Combine
import WebKit

final class BrowserViewModel: ObservableObject {
    let service: MediaService

    weak var webView: WKWebView?

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pipMessage: String?

    init(service: MediaService) {
        self.service = service
    }

    var serviceName: String { service.rawValue }
    var homeURL: URL { service.homeURL }
    var audioOnly: Bool { service.audioOnly }
    var supportsPictureInPicture: Bool { !audioOnly }

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
        if audioOnly {
            prepareAudioOnlyMode()
        } else {
            prepareVideoElements()
        }
        webView?.evaluateJavaScript(Self.prepareForBackgroundPlaybackScript)
    }

    func prepareVideoElements() {
        webView?.evaluateJavaScript(Self.prepareVideoElementsScript)
    }

    func prepareAudioOnlyMode() {
        webView?.evaluateJavaScript(Self.audioOnlyScript)
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

    static let audioOnlyScript = """
    (() => {
        const apply = () => {
            document.querySelectorAll('video').forEach((video) => {
                video.style.opacity = '0';
                video.style.pointerEvents = 'none';
                video.style.position = 'fixed';
                video.style.width = '1px';
                video.style.height = '1px';
                video.style.left = '-10px';
                video.style.top = '-10px';
            });
        };

        apply();
        if (!window.__youtubeMusicAudioOnlyObserver) {
            window.__youtubeMusicAudioOnlyObserver = new MutationObserver(apply);
            window.__youtubeMusicAudioOnlyObserver.observe(document.documentElement, { childList: true, subtree: true });
        }
    })();
    """

    private static let prepareForBackgroundPlaybackScript = """
    (() => {
        const media = Array.from(document.querySelectorAll('audio, video'))
            .filter((item) => item.readyState > 0)
            .sort((left, right) => Number(left.paused) - Number(right.paused))[0];

        if (!media) {
            return 'Nenhuma midia pronta para continuar em segundo plano.';
        }

        media.setAttribute('playsinline', '');
        if (media.paused) {
            media.play().catch(() => {});
        }

        return 'Reproducao preparada para segundo plano.';
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
