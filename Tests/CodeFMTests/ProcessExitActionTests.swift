import XCTest
@testable import CodeFM

final class ProcessExitActionTests: XCTestCase {
    func test_noPlayRequestTearsDownInEveryState() {
        for state: PlayerState in [.stopped, .loading, .playing, .offline] {
            for didRebuild in [false, true] {
                XCTAssertEqual(ProcessExitAction.decide(isPlayRequested: false, state: state, didRebuild: didRebuild), .teardown)
            }
        }
    }

    func test_requestedOfflinePlayerTearsDownRegardlessOfRebuildFlag() {
        for didRebuild in [false, true] {
            XCTAssertEqual(ProcessExitAction.decide(isPlayRequested: true, state: .offline, didRebuild: didRebuild), .teardown)
        }
    }

    func test_requestedStoppedPlayerTearsDownRegardlessOfRebuildFlag() {
        for didRebuild in [false, true] {
            XCTAssertEqual(ProcessExitAction.decide(isPlayRequested: true, state: .stopped, didRebuild: didRebuild), .teardown)
        }
    }

    func test_firstExitDuringRequestedPlayAttemptRebuilds() {
        for state: PlayerState in [.loading, .playing] {
            XCTAssertEqual(ProcessExitAction.decide(isPlayRequested: true, state: state, didRebuild: false), .rebuild)
        }
    }

    func test_repeatedExitDuringRequestedPlayAttemptFails() {
        for state: PlayerState in [.loading, .playing] {
            XCTAssertEqual(ProcessExitAction.decide(isPlayRequested: true, state: state, didRebuild: true), .fail)
        }
    }
}
