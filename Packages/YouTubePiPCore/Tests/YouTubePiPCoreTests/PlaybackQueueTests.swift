import XCTest
@testable import YouTubePiPCore

final class PlaybackQueueTests: XCTestCase {
    private let current = MediaTrack(videoID: "C", title: "Atual", artist: "Artista")

    private func snapshot(queue: [MediaTrack]) -> PageMediaSnapshot {
        PageMediaSnapshot(currentTrack: current, fallbackStreamURL: nil, currentTime: 0, playlistID: nil, queue: queue)
    }

    func testMusicQueueStartsAtCurrentTrackAndDropsDuplicates() {
        let queue = PlaybackQueue(
            snapshot: snapshot(queue: [
                MediaTrack(videoID: "A"),
                MediaTrack(videoID: "C", artworkURL: URL(string: "https://img/c.jpg"), duration: 200),
                MediaTrack(videoID: "A"),
                MediaTrack(videoID: "D")
            ]),
            includePageQueue: true
        )

        XCTAssertEqual(queue.tracks.map(\.videoID), ["A", "C", "D"])
        XCTAssertEqual(queue.currentIndex, 1)
        // Metadados da captura prevalecem; os vazios vem da fila.
        XCTAssertEqual(queue.current?.title, "Atual")
        XCTAssertEqual(queue.current?.duration, 200)
        XCTAssertTrue(queue.hasNext)
        XCTAssertTrue(queue.hasPrevious)
    }

    func testCurrentTrackMissingFromPageQueueGoesFirst() {
        let queue = PlaybackQueue(snapshot: snapshot(queue: [MediaTrack(videoID: "A")]), includePageQueue: true)
        XCTAssertEqual(queue.tracks.map(\.videoID), ["C", "A"])
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testYouTubeIgnoresPageQueue() {
        let queue = PlaybackQueue(snapshot: snapshot(queue: [MediaTrack(videoID: "A")]), includePageQueue: false)
        XCTAssertEqual(queue.tracks.map(\.videoID), ["C"])
        XCTAssertFalse(queue.hasNext)
    }

    func testMergePlaylistKeepsResolvedCurrentTrack() {
        var queue = PlaybackQueue(tracks: [MediaTrack(videoID: "C", streamURL: URL(string: "https://hls/c.m3u8"))])

        let changed = queue.mergePlaylist(
            [MediaTrack(videoID: "X"), MediaTrack(videoID: "C", title: "Da playlist"), MediaTrack(videoID: "Y")],
            expectedCurrentVideoID: "C"
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(queue.tracks.map(\.videoID), ["X", "C", "Y"])
        XCTAssertEqual(queue.currentIndex, 1)
        XCTAssertNotNil(queue.current?.streamURL)
        XCTAssertEqual(queue.current?.title, "Da playlist")
    }

    func testMergePlaylistWithoutCurrentTrackPutsItFirst() {
        var queue = PlaybackQueue(tracks: [current])
        queue.mergePlaylist([MediaTrack(videoID: "X"), MediaTrack(videoID: "Y")], expectedCurrentVideoID: "C")
        XCTAssertEqual(queue.tracks.map(\.videoID), ["C", "X", "Y"])
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testMergeIgnoredWhenTrackChangedMeanwhile() {
        var queue = PlaybackQueue(tracks: [current])
        XCTAssertFalse(queue.mergePlaylist([MediaTrack(videoID: "X")], expectedCurrentVideoID: "OUTRA"))
        XCTAssertFalse(queue.mergePlaylist([], expectedCurrentVideoID: "C"))
        XCTAssertEqual(queue.tracks.map(\.videoID), ["C"])
    }

    func testUnresolvedUpcomingRespectsLimitAndResolvedTracks() {
        let resolved = URL(string: "https://hls/b.m3u8")
        let queue = PlaybackQueue(
            tracks: ["A", "B", "C", "D", "E", "F"].map { MediaTrack(videoID: $0, streamURL: $0 == "B" ? resolved : nil) },
            currentIndex: 0
        )

        XCTAssertEqual(queue.unresolvedUpcoming(limit: 3).map(\.videoID), ["C", "D"])
        XCTAssertEqual(queue.unresolvedUpcoming(limit: 0), [])
        XCTAssertEqual(PlaybackQueue(tracks: [current]).unresolvedUpcoming(limit: 5), [])
    }

    func testStorePrefetchedFindsTrackByIDAndKeepsExistingURL() {
        let existing = URL(string: "https://hls/old.m3u8")
        var queue = PlaybackQueue(tracks: [current, MediaTrack(videoID: "A"), MediaTrack(videoID: "B", streamURL: existing)])

        queue.storePrefetched(MediaTrack(videoID: "A", streamURL: URL(string: "https://hls/a.m3u8")))
        queue.storePrefetched(MediaTrack(videoID: "B", streamURL: URL(string: "https://hls/new.m3u8")))
        queue.storePrefetched(MediaTrack(videoID: "NAO-ESTA", streamURL: existing))

        XCTAssertEqual(queue[1]?.streamURL?.absoluteString, "https://hls/a.m3u8")
        XCTAssertEqual(queue[2]?.streamURL, existing)
        XCTAssertEqual(queue.tracks.count, 3)
    }

    func testReplaceAndInvalidate() {
        var queue = PlaybackQueue(tracks: [current, MediaTrack(videoID: "A")])

        queue.replace(at: 1, with: MediaTrack(videoID: "OUTRO", streamURL: URL(string: "https://x")))
        XCTAssertNil(queue[1]?.streamURL, "nao troca por uma faixa com outro ID")

        queue.replace(at: 1, with: MediaTrack(videoID: "A", streamURL: URL(string: "https://x")))
        XCTAssertNotNil(queue[1]?.streamURL)

        queue.invalidateStream(at: 1)
        XCTAssertNil(queue[1]?.streamURL)

        XCTAssertTrue(queue.moveTo(1))
        XCTAssertFalse(queue.moveTo(9))
        XCTAssertEqual(queue.currentIndex, 1)
    }
}
