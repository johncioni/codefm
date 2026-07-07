import XCTest
@testable import CodeFM

final class RandomPickerTests: XCTestCase {
    private func makeCatalog(ids: [String]) -> StreamCatalog {
        let streams = ids.map { id in
            let json = """
            {
              "id": "\(id)", "displayName": "\(id)", "subgenre": "lofi",
              "type": "direct_audio", "url": "https://example.com/\(id).pls",
              "attribution": { "artist": "X", "website": "https://example.com" },
              "description": "", "providerLabel": "X"
            }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(Stream.self, from: json)
        }
        return StreamCatalog(schemaVersion: 1, defaultStreamId: ids[0], streams: streams)
    }

    func test_pickReturnsCatalogMember() {
        let catalog = makeCatalog(ids: ["a", "b", "c"])
        for _ in 0..<100 {
            let picked = RandomPicker.pick(from: catalog)
            XCTAssertTrue(catalog.streams.contains(picked))
        }
    }

    func test_pickEventuallyHitsEveryStream() {
        let catalog = makeCatalog(ids: ["a", "b", "c", "d", "e"])
        var seen = Set<String>()
        for _ in 0..<1000 {
            seen.insert(RandomPicker.pick(from: catalog).id)
        }
        XCTAssertEqual(seen.count, 5, "Every stream should be picked at least once over 1000 trials")
    }
}
