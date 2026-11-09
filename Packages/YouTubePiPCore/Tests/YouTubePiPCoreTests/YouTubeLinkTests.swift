import XCTest
@testable import YouTubePiPCore

final class YouTubeLinkTests: XCTestCase {
    private func parse(_ string: String) -> YouTubeLink? {
        YouTubeLink.parse(URL(string: string)!)
    }

    func testCommonYouTubeLinks() {
        XCTAssertEqual(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1")?.playlistID, "PL1")
        XCTAssertEqual(parse("https://youtu.be/dQw4w9WgXcQ?si=abc")?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(parse("https://www.youtube.com/shorts/abcDEF12345")?.videoID, "abcDEF12345")
        XCTAssertEqual(parse("https://www.youtube.com/live/abcDEF12345")?.videoID, "abcDEF12345")
        XCTAssertEqual(parse("https://www.youtube-nocookie.com/embed/abcDEF12345")?.videoID, "abcDEF12345")
        XCTAssertFalse(parse("https://youtu.be/dQw4w9WgXcQ")!.isMusic)
    }

    func testMusicAndPlaylists() throws {
        let music = try XCTUnwrap(parse("https://music.youtube.com/watch?v=I_izvAbhExY&list=RDAMVM1"))
        XCTAssertTrue(music.isMusic)
        XCTAssertEqual(music.pageURL.absoluteString, "https://music.youtube.com/watch?v=I_izvAbhExY&list=RDAMVM1")

        let playlist = try XCTUnwrap(parse("https://music.youtube.com/playlist?list=PLx"))
        XCTAssertNil(playlist.videoID)
        XCTAssertEqual(playlist.pageURL.absoluteString, "https://music.youtube.com/playlist?list=PLx")
    }

    func testStartTimes() {
        XCTAssertEqual(parse("https://youtu.be/dQw4w9WgXcQ?t=90")?.startTime, 90)
        XCTAssertEqual(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s")?.startTime, 90)
        XCTAssertEqual(YouTubeLink.parseTime("1h2m3s"), 3723)
        XCTAssertEqual(YouTubeLink.parseTime("45s"), 45)
        XCTAssertNil(YouTubeLink.parseTime("abc"))
        XCTAssertNil(YouTubeLink.parseTime("10x"))
        XCTAssertNil(YouTubeLink.parseTime("12m3"))
    }

    func testAppScheme() throws {
        let wrapped = "ytpip://open?url=" + "https://music.youtube.com/watch?v=I_izvAbhExY"
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertEqual(parse(wrapped)?.videoID, "I_izvAbhExY")
        XCTAssertEqual(parse(wrapped)?.isMusic, true)

        let direct = try XCTUnwrap(parse("ytpip://watch?v=dQw4w9WgXcQ&t=10"))
        XCTAssertEqual(direct.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(direct.startTime, 10)
        XCTAssertEqual(parse("ytpip://music?v=dQw4w9WgXcQ")?.isMusic, true)
    }

    func testRejectsOtherLinks() {
        XCTAssertNil(parse("https://www.youtube.com/"))
        XCTAssertNil(parse("https://www.youtube.com/@canal"))
        XCTAssertNil(parse("https://notyoutube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(parse("https://www.youtube.com/watch?v=x"), "ID curto demais")
        XCTAssertNil(parse("https://www.youtube.com/watch?v=abc%3Cscript%3E"))
        XCTAssertNil(parse("ytpip://open"))
    }

    func testFindsLinkInCopiedText() {
        let text = "Olha esse video: youtu.be/dQw4w9WgXcQ muito bom"
        XCTAssertEqual(YouTubeLink.firstLink(in: text)?.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(
            YouTubeLink.firstLink(in: "<https://music.youtube.com/watch?v=I_izvAbhExY>")?.isMusic,
            true
        )
        XCTAssertNil(YouTubeLink.firstLink(in: "nenhum link aqui"))
    }
}
