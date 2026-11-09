import XCTest
@testable import YouTubePiPCore

final class LinkPolicyTests: XCTestCase {
    private func decide(_ string: String, userLink: Bool = true, mainFrame: Bool = true, newWindow: Bool = false) -> LinkPolicy.Decision {
        LinkPolicy.decide(url: URL(string: string)!, isUserLink: userLink, isMainFrame: mainFrame, opensNewWindow: newWindow)
    }

    func testYouTubeAndGoogleLoginStayInside() {
        XCTAssertEqual(decide("https://m.youtube.com/watch?v=abc"), .allow)
        XCTAssertEqual(decide("https://music.youtube.com/"), .allow)
        XCTAssertEqual(decide("https://youtu.be/abc"), .allow)
        XCTAssertEqual(decide("https://accounts.google.com/signin"), .allow)
        XCTAssertEqual(decide("https://www.google.com.br/search?q=x"), .allow)
        XCTAssertEqual(decide("https://consent.youtube.com/m"), .allow)
    }

    func testExternalLinksTappedByUserOpenOutside() {
        XCTAssertEqual(decide("https://www.instagram.com/artista"), .openExternally)
        XCTAssertEqual(decide("https://loja.example.com", mainFrame: false, newWindow: true), .openExternally)
        XCTAssertFalse(LinkPolicy.isInternal(host: "notyoutube.com"))
    }

    func testRedirectsAndIframesStayInside() {
        XCTAssertEqual(decide("https://www.instagram.com/x", userLink: false), .allow)
        XCTAssertEqual(decide("https://ads.example.com/frame", mainFrame: false), .allow)
    }

    func testSchemes() {
        XCTAssertEqual(decide("mailto:alguem@example.com"), .openExternally)
        XCTAssertEqual(decide("tel:+5511999999999"), .openExternally)
        XCTAssertEqual(decide("youtube://watch?v=abc"), .cancel)
        XCTAssertEqual(decide("intent://watch#Intent;end"), .cancel)
        XCTAssertEqual(decide("about:blank"), .allow)
        XCTAssertEqual(decide("blob:https://m.youtube.com/123"), .allow)
    }
}
