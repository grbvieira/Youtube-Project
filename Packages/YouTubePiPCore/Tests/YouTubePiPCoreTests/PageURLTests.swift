import XCTest
@testable import YouTubePiPCore

final class PageURLTests: XCTestCase {
    func testFallbackPages() {
        XCTAssertEqual(PageURL.home(isMusic: true).absoluteString, "https://music.youtube.com/")
        XCTAssertEqual(PageURL.search("legião urbana", isMusic: false).absoluteString,
                       "https://m.youtube.com/results?search_query=legi%C3%A3o%20urbana")
        XCTAssertEqual(PageURL.search("lofi & chill", isMusic: true).absoluteString,
                       "https://music.youtube.com/search?q=lofi%20%26%20chill")
        XCTAssertEqual(PageURL.channel("UC123", isMusic: false).absoluteString, "https://m.youtube.com/channel/UC123")
        XCTAssertEqual(PageURL.playlist("VLPL1", isMusic: true).absoluteString, "https://music.youtube.com/playlist?list=PL1")
        XCTAssertEqual(PageURL.library(isMusic: false).absoluteString, "https://m.youtube.com/feed/library")
        XCTAssertEqual(PageURL.subscriptions(isMusic: true).absoluteString, "https://music.youtube.com/library/subscriptions")
        // Os links montados sao reconhecidos de volta pelo app.
        XCTAssertEqual(YouTubeLink.parse(PageURL.playlist("PL1", isMusic: false))?.playlistID, "PL1")
    }

    func testChapters() {
        let chapters = VideoChapters.normalized([
            VideoChapter(title: "Meio", start: 120),
            VideoChapter(title: "Inicio", start: 0),
            VideoChapter(title: "Repetido", start: 120),
            VideoChapter(title: "Invalido", start: -5),
            VideoChapter(title: "Fim", start: 300)
        ])

        XCTAssertEqual(chapters.map(\.title), ["Inicio", "Meio", "Fim"])
        XCTAssertEqual(VideoChapters.currentIndex(in: chapters, at: 0), 0)
        XCTAssertEqual(VideoChapters.currentIndex(in: chapters, at: 119.9), 0)
        XCTAssertEqual(VideoChapters.currentIndex(in: chapters, at: 120), 1)
        XCTAssertEqual(VideoChapters.currentIndex(in: chapters, at: 9_999), 2)
        XCTAssertNil(VideoChapters.currentIndex(in: [], at: 10))
        XCTAssertNil(VideoChapters.currentIndex(in: [VideoChapter(title: "Tarde", start: 30)], at: 10))
    }
}
