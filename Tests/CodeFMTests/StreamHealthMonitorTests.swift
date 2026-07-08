import XCTest
@testable import CodeFM

final class StreamHealthMonitorTests: XCTestCase {
    // Representative markers from a real YouTube live watch page: the channel is
    // broadcasting, so the player reports OK + isLive.
    private let liveHTML = #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"isLive":true,"isLiveContent":true}}"#

    // An ended/rotated live broadcast (the old pinned videoId) — YouTube gates the
    // watch page behind LOGIN_REQUIRED and drops the live flags. This is exactly the
    // state that made the app hide Claude FM from the dropdown.
    private let endedHTML = #"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in"}}"#

    func test_liveStreamIsHealthy() {
        XCTAssertTrue(StreamHealthMonitor.htmlIndicatesLive(liveHTML))
    }

    func test_endedOrLoginGatedStreamIsNotHealthy() {
        XCTAssertFalse(StreamHealthMonitor.htmlIndicatesLive(endedHTML))
    }

    func test_okButNotLiveIsNotHealthy() {
        // A plain (non-live) video is playable but must not be surfaced as a live stream.
        let vodHTML = #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"isLive":false}}"#
        XCTAssertFalse(StreamHealthMonitor.htmlIndicatesLive(vodHTML))
    }

    func test_isLiveContentAloneCountsAsLive() {
        // Edge fallback: some responses omit isLive entirely but still expose
        // isLiveContent for an active broadcast. With no isLive flag either way,
        // isLiveContent:true is accepted.
        let html = #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"isLiveContent":true}}"#
        XCTAssertTrue(StreamHealthMonitor.htmlIndicatesLive(html))
    }

    func test_endedReplayWithPersistentLiveContentIsNotHealthy() {
        // An ended broadcast keeps isLiveContent:true (YouTube's persistent
        // classification) but flips isLive to false. It must NOT read as live —
        // otherwise the stale/rotated pinned videoId looks healthy and the
        // channel-live fallback in probeYouTube never runs. (CodeRabbit finding.)
        let html = #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"isLive":false,"isLiveContent":true}}"#
        XCTAssertFalse(StreamHealthMonitor.htmlIndicatesLive(html))
    }
}
