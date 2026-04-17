import XCTest
@testable import Wamp

final class CueDecoderTests: XCTestCase {
    func test_decodes_utf8_without_bom() throws {
        let data = "TITLE \"Hellø\"\n".data(using: .utf8)!
        let result = try CueDecoder.decode(data)
        XCTAssertEqual(result.text, "TITLE \"Hellø\"\n")
        XCTAssertEqual(result.encoding, .utf8)
    }

    func test_decodes_utf8_with_bom() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("TITLE \"X\"\n".data(using: .utf8)!)
        let result = try CueDecoder.decode(data)
        XCTAssertEqual(result.text, "TITLE \"X\"\n") // BOM stripped
        XCTAssertEqual(result.encoding, .utf8)
    }
}
