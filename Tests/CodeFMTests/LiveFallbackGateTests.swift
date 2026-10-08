import XCTest
@testable import CodeFM

final class LiveFallbackGateTests: XCTestCase {
    func test_failureWhileResolvingIsIgnored() {
        var gate = LiveFallbackGate()
        guard case .resolve = gate.failure() else { return XCTFail("First failure should resolve") }
        XCTAssertEqual(gate.failure(), .ignore)
    }

    func test_completedFallbackGoesOfflineOnNextFailure() {
        var gate = LiveFallbackGate()
        guard case let .resolve(token) = gate.failure() else { return XCTFail("Expected resolve") }
        XCTAssertTrue(gate.complete(token: token))
        XCTAssertEqual(gate.failure(), .goOffline)
    }

    func test_playingSupersedesResolveAndAllowsNewToken() {
        var gate = LiveFallbackGate()
        guard case let .resolve(oldToken) = gate.failure() else { return XCTFail("Expected resolve") }
        gate.playing()
        XCTAssertFalse(gate.complete(token: oldToken))
        guard case let .resolve(newToken) = gate.failure() else { return XCTFail("Expected new resolve") }
        XCTAssertNotEqual(newToken, oldToken)
    }

    func test_rearmAfterCompletionAllowsAnotherResolve() {
        var gate = LiveFallbackGate()
        guard case let .resolve(token) = gate.failure() else { return XCTFail("Expected resolve") }
        XCTAssertTrue(gate.complete(token: token))
        gate.rearm()
        guard case .resolve = gate.failure() else { return XCTFail("Expected rearmed resolve") }
    }

    func test_rearmPreservesInFlightResolve() {
        var gate = LiveFallbackGate()
        guard case let .resolve(token) = gate.failure() else { return XCTFail("Expected resolve") }
        gate.rearm()
        XCTAssertEqual(gate.failure(), .ignore)
        XCTAssertTrue(gate.complete(token: token))
    }

    func test_staleCompletionDoesNotConsumeNewResolve() {
        var gate = LiveFallbackGate()
        guard case let .resolve(oldToken) = gate.failure() else { return XCTFail("Expected resolve") }
        gate.playing()
        guard case let .resolve(newToken) = gate.failure() else { return XCTFail("Expected new resolve") }
        XCTAssertFalse(gate.complete(token: oldToken))
        XCTAssertEqual(gate.failure(), .ignore)
        XCTAssertTrue(gate.complete(token: newToken))
        XCTAssertFalse(gate.complete(token: newToken))
    }

    func test_playingRearmsAfterOffline() {
        var gate = LiveFallbackGate()
        guard case let .resolve(token) = gate.failure() else { return XCTFail("Expected resolve") }
        XCTAssertTrue(gate.complete(token: token))
        XCTAssertEqual(gate.failure(), .goOffline)
        gate.playing()
        guard case .resolve = gate.failure() else { return XCTFail("Expected rearmed resolve") }
    }
}
