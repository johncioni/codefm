import XCTest
@testable import CodeFM

final class LiveLookupActionTests: XCTestCase {
    func test_missingResolvedIdGoesOfflineInEveryState() {
        for state: PlayerState in [.stopped, .loading, .playing, .offline] {
            for isPlayRequested in [false, true] {
                XCTAssertEqual(LiveLookupAction.decide(resolvedId: nil, currentId: "current", isPlayRequested: isPlayRequested, state: state), .goOffline)
            }
        }
    }

    func test_unchangedResolvedIdGoesOfflineInEveryState() {
        for state: PlayerState in [.stopped, .loading, .playing, .offline] {
            for isPlayRequested in [false, true] {
                XCTAssertEqual(LiveLookupAction.decide(resolvedId: "current", currentId: "current", isPlayRequested: isPlayRequested, state: state), .goOffline)
            }
        }
    }

    func test_newIdDuringRequestedPlayAttemptReloadsWithAutoplay() {
        for state: PlayerState in [.loading, .playing] {
            XCTAssertEqual(LiveLookupAction.decide(resolvedId: "new", currentId: "current", isPlayRequested: true, state: state), .reload(videoId: "new", autoplay: true))
        }
    }

    func test_newIdForRequestedStoppedOrOfflinePlayerReloadsSilently() {
        for state: PlayerState in [.stopped, .offline] {
            XCTAssertEqual(LiveLookupAction.decide(resolvedId: "new", currentId: "current", isPlayRequested: true, state: state), .reload(videoId: "new", autoplay: false))
        }
    }

    func test_newIdWithoutPlayRequestReloadsSilentlyInEveryState() {
        for state: PlayerState in [.stopped, .loading, .playing, .offline] {
            XCTAssertEqual(LiveLookupAction.decide(resolvedId: "new", currentId: "current", isPlayRequested: false, state: state), .reload(videoId: "new", autoplay: false))
        }
    }
}
