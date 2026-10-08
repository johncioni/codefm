import XCTest
@testable import CodeFM

final class RemovedStreamAutoplayTests: XCTestCase {
    func test_provisionalStationFollowsWantsPlaybackInEveryState() {
        for state: PlayerState in [.stopped, .loading, .playing, .offline] {
            for wantsPlayback in [false, true] {
                XCTAssertEqual(RemovedStreamAutoplay.decide(isProvisional: true, wantsPlayback: wantsPlayback, state: state), wantsPlayback)
            }
        }
    }

    func test_establishedStationLoadingOrPlayingAutoplays() {
        for state: PlayerState in [.loading, .playing] {
            XCTAssertTrue(RemovedStreamAutoplay.decide(isProvisional: false, wantsPlayback: true, state: state))
        }
    }

    func test_establishedStationStoppedOrOfflineStaysSilentEvenWithPlayRequest() {
        for state: PlayerState in [.stopped, .offline] {
            XCTAssertFalse(RemovedStreamAutoplay.decide(isProvisional: false, wantsPlayback: true, state: state))
        }
    }
}
