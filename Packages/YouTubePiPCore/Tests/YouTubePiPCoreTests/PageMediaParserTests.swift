import XCTest
@testable import YouTubePiPCore

final class PageMediaParserTests: XCTestCase {
    func testYouTubeMusicUsesPlayerDataInsteadOfStaleURL() throws {
        let snapshot = try XCTUnwrap(PageMediaParser.snapshot(fromJSON: fixture("ytmusic-watch")))

        // A URL ainda aponta para a faixa anterior; vale o que o player esta tocando.
        XCTAssertEqual(snapshot.currentTrack.videoID, "I_izvAbhExY")
        XCTAssertEqual(snapshot.currentTrack.title, "Stayin' Alive (From \"Saturday Night Fever\" Soundtrack)")
        XCTAssertEqual(snapshot.currentTrack.artist, "Bee Gees")
        XCTAssertEqual(snapshot.currentTrack.streamURL, nil)
        XCTAssertEqual(snapshot.playlistID, "RDAMVMdQw4w9WgXcQ")
        XCTAssertEqual(snapshot.currentTime, 124.612452, accuracy: 0.0001)
        XCTAssertEqual(snapshot.currentTrack.duration ?? 0, 249.521, accuracy: 0.001)
    }

    func testYouTubeMusicQueueSkipsItemsWithoutIDAndPlaceholderArtwork() throws {
        let snapshot = try XCTUnwrap(PageMediaParser.snapshot(fromJSON: fixture("ytmusic-watch")))

        XCTAssertEqual(snapshot.queue.map(\.videoID), ["dQw4w9WgXcQ", "yPYZpwSpKmA", "I_izvAbhExY", "djV11Xbc914"])
        XCTAssertEqual(snapshot.queue[0].duration, 214)
        XCTAssertNotNil(snapshot.queue[0].artworkURL)
        XCTAssertNil(snapshot.queue[1].artworkURL, "imagem data: (ainda nao carregada) nao e capa")
    }

    func testFallbackAudioURLDropsRangeParametersAndIgnoresVideo() throws {
        let snapshot = try XCTUnwrap(PageMediaParser.snapshot(fromJSON: fixture("ytmusic-watch")))
        let url = try XCTUnwrap(snapshot.fallbackStreamURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let names = Set(items.map(\.name))

        XCTAssertEqual(items.first(where: { $0.name == "itag" })?.value, "251")
        XCTAssertTrue(names.isDisjoint(with: ["range", "rn", "rbuf", "ump", "srfvp"]))
        XCTAssertTrue(names.contains("sig"))
    }

    func testYouTubeFallsBackToURLAndElementTime() throws {
        let snapshot = try XCTUnwrap(PageMediaParser.snapshot(fromJSON: fixture("youtube-watch")))

        XCTAssertEqual(snapshot.currentTrack.videoID, "dQw4w9WgXcQ")
        XCTAssertEqual(snapshot.playlistID, "PL123")
        XCTAssertEqual(snapshot.currentTime, 12.5)
        XCTAssertNil(snapshot.currentTrack.artworkURL)
        XCTAssertNil(snapshot.fallbackStreamURL)
        XCTAssertTrue(snapshot.queue.isEmpty)
    }

    func testReturnsNilWithoutVideoID() {
        let json = #"{"pageURL": "https://music.youtube.com/", "metadata": {"videoID": "  "}}"#
        XCTAssertNil(PageMediaParser.snapshot(fromJSON: Data(json.utf8)))
        XCTAssertNil(PageMediaParser.snapshot(fromJSON: Data("nao e json".utf8)))
    }

    func testBooleanIsNotATime() throws {
        let json = #"{"pageURL": "https://m.youtube.com/watch?v=abc123", "metadata": {"currentTime": true}}"#
        let snapshot = try XCTUnwrap(PageMediaParser.snapshot(fromJSON: Data(json.utf8)))
        XCTAssertEqual(snapshot.currentTime, 0)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
