import Foundation
import XCTest
@testable import CodeFM

final class CatalogRefreshActionTests: XCTestCase {
    private func makeStream(
        displayName: String = "Station",
        description: String = "Music for coding",
        type: StreamType = .youtubeLive(
            videoId: "old-video",
            channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!,
            liveFallback: true
        )
    ) -> CodeFM.Stream {
        CodeFM.Stream(
            id: "station",
            displayName: displayName,
            subgenre: .lofi,
            type: type,
            attribution: Attribution(artist: "Artist", website: URL(string: "https://example.com")!),
            description: description,
            providerLabel: "Provider"
        )
    }

    func test_identicalEntryIsUnchanged() {
        for isPlaybackRequested in [false, true] {
            XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: makeStream(), isPlaybackRequested: isPlaybackRequested), .unchanged)
        }
    }

    func test_displayNameChangeUpdatesDetails() {
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: makeStream(displayName: "Renamed Station"), isPlaybackRequested: true), .updateDetails)
    }

    func test_descriptionChangeUpdatesDetails() {
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: makeStream(description: "Updated description"), isPlaybackRequested: false), .updateDetails)
    }

    func test_videoIdChangeReloadsWithPlayRequest() {
        let refreshed = makeStream(type: .youtubeLive(
            videoId: "new-video",
            channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!,
            liveFallback: true
        ))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: refreshed, isPlaybackRequested: true), .reload(autoplay: true))
    }

    func test_videoIdChangeReloadsWithoutPlayRequest() {
        let refreshed = makeStream(type: .youtubeLive(
            videoId: "new-video",
            channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!,
            liveFallback: true
        ))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: refreshed, isPlaybackRequested: false), .reload(autoplay: false))
    }

    func test_channelLiveUrlChangeReloads() {
        let refreshed = makeStream(type: .youtubeLive(
            videoId: "old-video",
            channelLiveUrl: URL(string: "https://www.youtube.com/@new-station/live")!,
            liveFallback: true
        ))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: refreshed, isPlaybackRequested: true), .reload(autoplay: true))
    }

    func test_liveFallbackChangeReloads() {
        let refreshed = makeStream(type: .youtubeLive(
            videoId: "old-video",
            channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!,
            liveFallback: false
        ))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: refreshed, isPlaybackRequested: true), .reload(autoplay: true))
    }

    func test_directAudioUrlChangeReloads() {
        let loaded = makeStream(type: .directAudio(url: URL(string: "https://example.com/old.mp3")!))
        let refreshed = makeStream(type: .directAudio(url: URL(string: "https://example.com/new.mp3")!))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: loaded, refreshed: refreshed, isPlaybackRequested: true), .reload(autoplay: true))
    }

    func test_youtubeBecomingDirectAudioReloads() {
        let refreshed = makeStream(type: .directAudio(url: URL(string: "https://example.com/live.mp3")!))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: refreshed, isPlaybackRequested: true), .reload(autoplay: true))
    }

    func test_playbackAndDisplayNameChangesReload() {
        let refreshed = makeStream(displayName: "Renamed Station", type: .youtubeLive(
            videoId: "new-video",
            channelLiveUrl: URL(string: "https://www.youtube.com/@station/live")!,
            liveFallback: true
        ))
        XCTAssertEqual(CatalogRefreshAction.decide(loaded: makeStream(), refreshed: refreshed, isPlaybackRequested: true), .reload(autoplay: true))
    }
}
