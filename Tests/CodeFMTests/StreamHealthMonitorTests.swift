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
        // Some edge servers omit isLive but still expose isLiveContent for an active broadcast.
        let html = #"{"playabilityStatus":{"status":"OK"},"videoDetails":{"isLiveContent":true}}"#
        XCTAssertTrue(StreamHealthMonitor.htmlIndicatesLive(html))
    }
}
