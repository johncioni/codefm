import XCTest
@testable import CodeFM

final class ProbeResultPolicyTests: XCTestCase {
    func test_resultForCurrentDefinitionApplies() {
        let youtube = StreamType.youtubeLive(videoId: "current", channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!, liveFallback: true)
        let audio = StreamType.directAudio(url: URL(string: "https://example.com/current.pls")!)

        XCTAssertTrue(ProbeResultPolicy.shouldApply(probed: youtube, current: youtube))
        XCTAssertTrue(ProbeResultPolicy.shouldApply(probed: audio, current: audio))
    }

    func test_resultForReplacedDefinitionIsIgnored() {
        let channelLiveUrl = URL(string: "https://www.youtube.com/@station/live")!
        let oldYouTube = StreamType.youtubeLive(videoId: "old", channelLiveUrl: channelLiveUrl, liveFallback: true)
        let currentYouTube = StreamType.youtubeLive(videoId: "current", channelLiveUrl: channelLiveUrl, liveFallback: true)
        let oldAudio = StreamType.directAudio(url: URL(string: "https://example.com/old.pls")!)
        let currentAudio = StreamType.directAudio(url: URL(string: "https://example.com/current.pls")!)

        XCTAssertFalse(ProbeResultPolicy.shouldApply(probed: oldYouTube, current: currentYouTube))
        XCTAssertFalse(ProbeResultPolicy.shouldApply(probed: oldAudio, current: currentAudio))
    }

    func test_resultWithNoRecordedDefinitionApplies() {
        let youtube = StreamType.youtubeLive(videoId: "current", channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!, liveFallback: true)

        XCTAssertTrue(ProbeResultPolicy.shouldApply(probed: youtube, current: nil))
    }
}
