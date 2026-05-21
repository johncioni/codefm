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

    func test_parsesPLSWithCRLFLineEndings() {
        // HTTP-normative line endings; many Icecast/Shoutcast servers emit CRLF.
        // Without trimming \r the parsed URL has a trailing control char and fails.
        let pls = "[playlist]\r\nNumberOfEntries=1\r\nFile1=https://ice5.somafm.com/groovesalad-256-mp3\r\nTitle1=SomaFM Groove Salad\r\nVersion=2\r\n"
        let url = PLSParser.firstStreamURL(in: pls)
        XCTAssertEqual(url, URL(string: "https://ice5.somafm.com/groovesalad-256-mp3"))
    }

    func test_parsesM3UWithCRLFLineEndings() {
        let m3u = "#EXTM3U\r\n#EXTINF:-1,Some Title\r\nhttps://example.com/stream.mp3\r\n"
        let url = PLSParser.firstStreamURL(in: m3u)
        XCTAssertEqual(url, URL(string: "https://example.com/stream.mp3"))
    }
}
