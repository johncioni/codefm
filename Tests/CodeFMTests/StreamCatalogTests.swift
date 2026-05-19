import XCTest
@testable import CodeFM

final class StreamCatalogTests: XCTestCase {
    func test_decodesYouTubeStream() throws {
        let json = """
        {
          "id": "lofigirl-main",
          "displayName": "Lofi Girl — Beats to Relax/Study",
          "subgenre": "lofi",
          "type": "youtube_live",
          "videoId": "jfKfPfyJRdk",
          "channelLiveUrl": "https://www.youtube.com/@LofiGirl/live",
          "attribution": { "artist": "Lofi Girl", "website": "https://lofigirl.com" },
          "description": "The original 24/7 lo-fi study stream.",
          "providerLabel": "YouTube"
        }
        """.data(using: .utf8)!

        let stream = try JSONDecoder().decode(Stream.self, from: json)

        XCTAssertEqual(stream.id, "lofigirl-main")
        XCTAssertEqual(stream.subgenre, .lofi)
        XCTAssertEqual(stream.providerLabel, "YouTube")
        guard case let .youtubeLive(videoId, channelLiveUrl) = stream.type else {
            return XCTFail("expected youtubeLive type")
        }
        XCTAssertEqual(videoId, "jfKfPfyJRdk")
        XCTAssertEqual(channelLiveUrl, URL(string: "https://www.youtube.com/@LofiGirl/live"))
    }

    func test_decodesDirectAudioStream() throws {
        let json = """
        {
          "id": "somafm-groovesalad",
          "displayName": "SomaFM — Groove Salad",
          "subgenre": "ambient",
          "type": "direct_audio",
          "url": "https://somafm.com/groovesalad256.pls",
          "attribution": { "artist": "SomaFM", "website": "https://somafm.com/groovesalad/" },
          "description": "Chilled ambient downtempo.",
          "providerLabel": "SomaFM"
        }
        """.data(using: .utf8)!

        let stream = try JSONDecoder().decode(Stream.self, from: json)

        guard case let .directAudio(url) = stream.type else {
            return XCTFail("expected directAudio type")
        }
        XCTAssertEqual(url, URL(string: "https://somafm.com/groovesalad256.pls"))
    }

    func test_unknownSubgenreMapsToOther() throws {
        let json = """
        {
          "id": "x", "displayName": "X", "subgenre": "weird-new-genre",
          "type": "direct_audio", "url": "https://example.com/x.pls",
          "attribution": { "artist": "X", "website": "https://example.com" },
          "description": "x", "providerLabel": "X"
        }
        """.data(using: .utf8)!

        let stream = try JSONDecoder().decode(Stream.self, from: json)
        XCTAssertEqual(stream.subgenre, .other)
    }
}
