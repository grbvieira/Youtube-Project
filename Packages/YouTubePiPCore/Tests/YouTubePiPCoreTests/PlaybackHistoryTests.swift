import XCTest
@testable import YouTubePiPCore

final class PlaybackHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func track(_ id: String, title: String = "") -> MediaTrack {
        MediaTrack(videoID: id, title: title)
    }

    func testRecordMovesToTopAndKeepsKnownMetadata() {
        var history = PlaybackHistory()
        history.record(track("A", title: "Video A"), position: 10, duration: 300, isMusic: false, at: now)
        history.record(track("B"), position: 5, duration: 200, isMusic: false, at: now)
        history.record(track("A"), position: 120, duration: nil, isMusic: false, at: now.addingTimeInterval(60))

        XCTAssertEqual(history.entries.map(\.videoID), ["A", "B"])
        XCTAssertEqual(history.entries[0].title, "Video A", "titulo vazio nao apaga o anterior")
        XCTAssertEqual(history.entries[0].duration, 300)
        XCTAssertEqual(history.entries[0].position, 120)
        XCTAssertEqual(history.entries[0].progress ?? 0, 0.4, accuracy: 0.0001)
    }

    func testLimit() {
        var history = PlaybackHistory()
        for index in 0..<(PlaybackHistory.limit + 10) {
            history.record(track("video\(index)"), position: 0, duration: nil, isMusic: false, at: now)
        }
        XCTAssertEqual(history.entries.count, PlaybackHistory.limit)
        XCTAssertEqual(history.entries.first?.videoID, "video\(PlaybackHistory.limit + 9)")
    }

    func testResumeRulesForVideos() {
        var history = PlaybackHistory()
        history.record(track("comecou"), position: 10, duration: 600, isMusic: false, at: now)
        history.record(track("meio"), position: 250, duration: 600, isMusic: false, at: now)
        history.record(track("fim"), position: 590, duration: 600, isMusic: false, at: now)
        history.record(track("semDuracao"), position: 100, duration: nil, isMusic: false, at: now)

        XCTAssertNil(history.resumePosition(for: "comecou"))
        XCTAssertEqual(history.resumePosition(for: "meio"), 250)
        XCTAssertNil(history.resumePosition(for: "fim"))
        XCTAssertEqual(history.resumePosition(for: "semDuracao"), 100)
        XCTAssertNil(history.resumePosition(for: "nunca"))
    }

    func testMusicOnlyResumesLongTracks() {
        var history = PlaybackHistory()
        history.record(track("musica"), position: 120, duration: 240, isMusic: true, at: now)
        history.record(track("mix"), position: 1200, duration: 3600, isMusic: true, at: now)
        history.record(track("semDuracao"), position: 120, duration: nil, isMusic: true, at: now)

        XCTAssertNil(history.resumePosition(for: "musica"))
        XCTAssertEqual(history.resumePosition(for: "mix"), 1200)
        XCTAssertNil(history.resumePosition(for: "semDuracao"))
    }

    func testRemoveClearAndCodable() throws {
        var history = PlaybackHistory()
        history.record(track("A"), position: 60, duration: 600, isMusic: false, at: now)
        history.record(track("B"), position: 60, duration: 600, isMusic: false, at: now)

        let decoded = try JSONDecoder().decode(PlaybackHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)

        history.remove(videoID: "A")
        XCTAssertEqual(history.entries.map(\.videoID), ["B"])
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }
}

final class PlaybackOptionsTests: XCTestCase {
    func testSleepTimer() {
        let now = Date(timeIntervalSince1970: 1_000)
        var timer = SleepTimer()
        XCTAssertFalse(timer.isActive)

        timer.set(.minutes(15), now: now)
        XCTAssertTrue(timer.isActive)
        XCTAssertEqual(timer.remaining(now: now.addingTimeInterval(60)), 14 * 60)
        XCTAssertFalse(timer.isExpired(now: now.addingTimeInterval(899)))
        XCTAssertTrue(timer.isExpired(now: now.addingTimeInterval(900)))
        XCTAssertEqual(timer.remaining(now: now.addingTimeInterval(2000)), 0)

        timer.set(.endOfTrack, now: now)
        XCTAssertTrue(timer.stopsAtEndOfTrack)
        XCTAssertNil(timer.deadline)
        XCTAssertFalse(timer.isExpired(now: now.addingTimeInterval(99_999)))

        timer.set(nil, now: now)
        XCTAssertFalse(timer.isActive)
        timer.set(.minutes(0), now: now)
        XCTAssertFalse(timer.isActive)
    }

    func testQualityLimits() {
        XCTAssertEqual(StreamQuality.automatic.limits(audioOnly: false).peakBitRate, 0)
        XCTAssertEqual(StreamQuality.dataSaver.limits(audioOnly: false).maxHeight, 480)
        XCTAssertEqual(StreamQuality.minimum.limits(audioOnly: false).maxHeight, 360)
        for quality in StreamQuality.allCases {
            XCTAssertEqual(quality.limits(audioOnly: true), StreamQuality.audioOnlyLimits)
        }
    }
}
