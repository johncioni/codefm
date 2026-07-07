import XCTest
@testable import CodeFM

final class DefaultStreamResolverTests: XCTestCase {
    private func catalog(ids: [String], defaultId: String) -> StreamCatalog {
        let streams = ids.map { id in
            let json = """
            { "id": "\(id)", "displayName": "\(id)", "subgenre": "lofi",
              "type": "direct_audio", "url": "https://example.com/\(id).pls",
              "attribution": { "artist": "X", "website": "https://example.com" },
              "description": "", "providerLabel": "X" }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(Stream.self, from: json)
        }
        return StreamCatalog(schemaVersion: 1, defaultStreamId: defaultId, streams: streams)
    }

    func test_userOverrideWins() {
        let cat = catalog(ids: ["a", "b", "c"], defaultId: "a")
        let stream = DefaultStreamResolver.resolve(catalog: cat, userDefaultId: "b")
        XCTAssertEqual(stream.id, "b")
    }

    func test_userOverrideMissingFallsBackToCatalogDefault() {
        let cat = catalog(ids: ["a", "b"], defaultId: "a")
        let stream = DefaultStreamResolver.resolve(catalog: cat, userDefaultId: "gone")
        XCTAssertEqual(stream.id, "a")
    }

    func test_catalogDefaultMissingFallsBackToFirstStream() {
        let cat = catalog(ids: ["a", "b"], defaultId: "ghost")
        let stream = DefaultStreamResolver.resolve(catalog: cat, userDefaultId: nil)
        XCTAssertEqual(stream.id, "a")
    }

    func test_randomSentinelPicksRandom() {
        let cat = catalog(ids: ["a", "b", "c"], defaultId: "a")
        for _ in 0..<50 {
            let stream = DefaultStreamResolver.resolve(catalog: cat, userDefaultId: "random")
            XCTAssertTrue(["a", "b", "c"].contains(stream.id))
        }
    }
}
