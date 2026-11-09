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

    // MARK: - Edicao pelo usuario

    private func ids(_ queue: PlaybackQueue) -> String { queue.tracks.map(\.videoID).joined() }

    private func queue(_ ids: String, current: Int) -> PlaybackQueue {
        PlaybackQueue(tracks: ids.map { MediaTrack(videoID: String($0)) }, currentIndex: current)
    }

    func testRemoveKeepsCurrentTrack() {
        var queue = queue("ABCDE", current: 2)

        XCTAssertFalse(queue.remove(at: 2), "a faixa atual nao sai")
        XCTAssertTrue(queue.remove(at: 0))
        XCTAssertEqual(ids(queue), "BCDE")
        XCTAssertEqual(queue.current?.videoID, "C")

        XCTAssertTrue(queue.remove(at: 3))
        XCTAssertEqual(ids(queue), "BCD")
        XCTAssertEqual(queue.current?.videoID, "C")
        XCTAssertFalse(queue.remove(at: 9))
    }

    func testMoveFollowsOnMoveConvention() {
        var down = queue("ABCDE", current: 0)
        down.move(from: 1, to: 4) // B para antes do E
        XCTAssertEqual(ids(down), "ACDBE")

        var up = queue("ABCDE", current: 0)
        up.move(from: 4, to: 1) // E para antes do B
        XCTAssertEqual(ids(up), "AEBCD")

        var end = queue("ABC", current: 0)
        end.move(from: 0, to: 3)
        XCTAssertEqual(ids(end), "BCA")

        var noop = queue("ABC", current: 1)
        noop.move(from: 1, to: 2)
        noop.move(from: 5, to: 0)
        XCTAssertEqual(ids(noop), "ABC")
    }

    func testMoveKeepsTheSameCurrentTrack() {
        for source in 0..<5 {
            for destination in 0...5 {
                for current in 0..<5 {
                    var queue = queue("ABCDE", current: current)
                    let playing = queue.current?.videoID
                    queue.move(from: source, to: destination)
                    XCTAssertEqual(queue.current?.videoID, playing, "move(\(source), \(destination)) com atual \(current)")
                    XCTAssertEqual(Set(queue.tracks.map(\.videoID)), Set(["A", "B", "C", "D", "E"]))
                }
            }
        }
    }
}
