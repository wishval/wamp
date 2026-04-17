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

    func test_decodes_cp1251_cyrillic() throws {
        // "TITLE \"Тест\"\r\n" in CP-1251
        let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0xD2,0xE5,0xF1,0xF2,0x22,0x0D,0x0A])
        let result = try CueDecoder.decode(data)
        XCTAssertEqual(result.encoding, .windowsCP1251)
        XCTAssertTrue(result.text.contains("Тест"), "got '\(result.text)'")
    }

    func test_decodes_shift_jis_japanese() throws {
        // "TITLE \"日本\"\n" in Shift-JIS
        let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0x93,0xFA,0x96,0x7B,0x22,0x0A])
        let result = try CueDecoder.decode(data)
        XCTAssertEqual(result.encoding, .shiftJIS)
        XCTAssertTrue(result.text.contains("日本"), "got '\(result.text)'")
    }

    func test_decodes_cp1252_french_diacritics() throws {
        // "TITLE \"Café\"\n" in CP-1252 (é = 0xE9)
        let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0x43,0x61,0x66,0xE9,0x22,0x0A])
        let result = try CueDecoder.decode(data)
        // Foundation may pick CP-1252 or ISO Latin 1 — both render é identically.
        XCTAssertTrue([.windowsCP1252, .isoLatin1].contains(result.encoding),
                      "got \(result.encoding)")
        XCTAssertTrue(result.text.contains("Café"), "got '\(result.text)'")
    }
}
