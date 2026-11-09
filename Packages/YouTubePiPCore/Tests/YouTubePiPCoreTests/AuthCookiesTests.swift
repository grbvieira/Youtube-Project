import XCTest
@testable import YouTubePiPCore

final class AuthCookiesTests: XCTestCase {
    private func cookie(_ name: String, _ value: String, _ domain: String = ".youtube.com") -> AuthCookies.Cookie {
        AuthCookies.Cookie(name: name, value: value, domain: domain)
    }

    func testBuildsHeaderOnlyFromYouTubeCookies() throws {
        let header = try XCTUnwrap(AuthCookies.header(from: [
            cookie("SAPISID", "a"),
            cookie("__Secure-1PSID", "b"),
            cookie("__Secure-1PAPISID", "c"),
            cookie("SID", "google", ".google.com"),
            cookie("TRACK", "x", ".notyoutube.com"),
            cookie("PREF", "hl=pt", "music.youtube.com")
        ]))

        XCTAssertEqual(header, "PREF=hl=pt; SAPISID=a; __Secure-1PAPISID=c; __Secure-1PSID=b")
        XCTAssertFalse(header.contains("google"))
        XCTAssertFalse(header.contains("TRACK"))
    }

    func testRequiresAuthenticationCookies() {
        XCTAssertNil(AuthCookies.header(from: [cookie("PREF", "x"), cookie("VISITOR_INFO1_LIVE", "y")]))
        XCTAssertNil(AuthCookies.header(from: [cookie("SAPISID", "a")]))
        XCTAssertNil(AuthCookies.header(from: [cookie("SAPISID", ""), cookie("__Secure-1PSID", "b")]))
        XCTAssertNil(AuthCookies.header(from: [cookie("SAPISID", "a", ".google.com"), cookie("__Secure-1PSID", "b", ".google.com")]))
    }

    func testPrefersParentDomainCookie() {
        let header = AuthCookies.header(from: [
            cookie("SAPISID", "dominio", ".youtube.com"),
            cookie("SAPISID", "subdominio", "m.youtube.com"),
            cookie("__Secure-1PSID", "b")
        ])
        XCTAssertEqual(header, "SAPISID=dominio; __Secure-1PSID=b")
    }
}
