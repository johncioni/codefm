import XCTest
@testable import CodeFM

final class PLSParserTests: XCTestCase {
    func test_parsesFirstFileLineFromPLS() {
        let pls = """
        [playlist]
        NumberOfEntries=3
        File1=https://ice5.somafm.com/groovesalad-256-mp3
        Title1=SomaFM Groove Salad
        Length1=-1
        File2=https://ice6.somafm.com/groovesalad-256-mp3
        Version=2
        """
        let url = PLSParser.firstStreamURL(in: pls)
        XCTAssertEqual(url, URL(string: "https://ice5.somafm.com/groovesalad-256-mp3"))
    }

    func test_parsesM3UFirstNonCommentLine() {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Some Title
        https://example.com/stream.mp3
        https://example.com/backup.mp3
        """
        let url = PLSParser.firstStreamURL(in: m3u)
        XCTAssertEqual(url, URL(string: "https://example.com/stream.mp3"))
    }

    func test_returnsNilForGarbage() {
        XCTAssertNil(PLSParser.firstStreamURL(in: "nope, this is not a playlist"))
    }
}
