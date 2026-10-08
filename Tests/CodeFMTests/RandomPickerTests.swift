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

    func test_pickExcludesUnavailableIds() {
        let catalog = makeCatalog(ids: ["a", "b", "c"])
        XCTAssertEqual(RandomPicker.pick(from: catalog, excluding: ["a", "c"])?.id, "b")
    }

    func test_pickReturnsNilWhenEverythingIsExcluded() {
        let catalog = makeCatalog(ids: ["a", "b"])
        XCTAssertNil(RandomPicker.pick(from: catalog, excluding: ["a", "b"]))
    }

    func test_provisionalOfflineStreamGetsAvailableReplacement() {
        let catalog = makeCatalog(ids: ["a", "b", "c"])
        XCTAssertEqual(RandomLaunchPolicy.replacement(
            in: catalog, currentStreamId: "a", unavailableIds: ["a", "b"], isProvisional: true
        )?.id, "c")
    }

    func test_settledStreamIsNotReplaced() {
        let catalog = makeCatalog(ids: ["a", "b"])
        XCTAssertNil(RandomLaunchPolicy.replacement(
            in: catalog, currentStreamId: "a", unavailableIds: ["a"], isProvisional: false
        ))
    }

    func test_anotherOfflineStreamDoesNotReplaceCurrentStream() {
        let catalog = makeCatalog(ids: ["a", "b", "c"])
        XCTAssertNil(RandomLaunchPolicy.replacement(
            in: catalog, currentStreamId: "a", unavailableIds: ["b"], isProvisional: true
        ))
    }

    func test_noReplacementWhenNoOtherStationIsAvailable() {
        let catalog = makeCatalog(ids: ["a", "b"])
        XCTAssertNil(RandomLaunchPolicy.replacement(
            in: catalog, currentStreamId: "a", unavailableIds: ["a", "b"], isProvisional: true
        ))
    }

}
