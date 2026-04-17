import Testing
import Foundation
@testable import Wamp

@Suite("CueDecoder")
struct CueDecoderTests {
    @Test func decodesUtf8WithoutBom() throws {
        let data = "TITLE \"Hellø\"\n".data(using: .utf8)!
        let result = try CueDecoder.decode(data)
        #expect(result.text == "TITLE \"Hellø\"\n")
        #expect(result.encoding == .utf8)
    }

    @Test func decodesUtf8WithBom() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("TITLE \"X\"\n".data(using: .utf8)!)
        let result = try CueDecoder.decode(data)
        #expect(result.text == "TITLE \"X\"\n") // BOM stripped
        #expect(result.encoding == .utf8)
    }

    @Test func decodesCp1251Cyrillic() throws {
        // "TITLE \"Тест\"\r\n" in CP-1251
        let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0xD2,0xE5,0xF1,0xF2,0x22,0x0D,0x0A])
        let result = try CueDecoder.decode(data)
        #expect(result.encoding == .windowsCP1251)
        #expect(result.text.contains("Тест"))
    }

    @Test func decodesShiftJisJapanese() throws {
        // "TITLE \"日本\"\n" in Shift-JIS
        let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0x93,0xFA,0x96,0x7B,0x22,0x0A])
        let result = try CueDecoder.decode(data)
        #expect(result.encoding == .shiftJIS)
        #expect(result.text.contains("日本"))
    }

    @Test func decodesCp1252FrenchDiacritics() throws {
        // "TITLE \"Café\"\n" in CP-1252 (é = 0xE9)
        let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0x43,0x61,0x66,0xE9,0x22,0x0A])
        let result = try CueDecoder.decode(data)
        #expect([.windowsCP1252, .isoLatin1].contains(result.encoding))
        #expect(result.text.contains("Café"))
    }
}
