import Testing
import Foundation
@testable import Wamp

@Suite("FlacCueExtractor")
struct FlacCueExtractorTests {

    /// Build a minimal synthetic FLAC stream: "fLaC" + STREAMINFO block +
    /// a VORBIS_COMMENT block with the given tag list. No audio frames — the
    /// extractor stops after scanning metadata.
    private func makeFlac(comments: [(String, String)]) -> Data {
        var d = Data()
        d.append(contentsOf: [0x66, 0x4C, 0x61, 0x43])      // "fLaC"

        // STREAMINFO block: type 0, NOT last, length 34, zero payload.
        d.append(0x00)
        d.append(contentsOf: [0x00, 0x00, 0x22])            // len = 34
        d.append(Data(repeating: 0, count: 34))

        // VORBIS_COMMENT block, last metadata block.
        let vendor = "Wamp test".data(using: .utf8)!
        var body = Data()
        body.append(uint32LE(UInt32(vendor.count)))
        body.append(vendor)
        body.append(uint32LE(UInt32(comments.count)))
        for (k, v) in comments {
            let raw = "\(k)=\(v)".data(using: .utf8)!
            body.append(uint32LE(UInt32(raw.count)))
            body.append(raw)
        }

        let length = body.count
        d.append(0x84)                                       // last=1, type=4
        d.append(uint24BE(UInt32(length)))
        d.append(body)
        return d
    }

    private func uint32LE(_ v: UInt32) -> Data {
        var v = v.littleEndian
        return Data(bytes: &v, count: 4)
    }

    private func uint24BE(_ v: UInt32) -> Data {
        Data([UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }

    @Test func extractsEmbeddedCuesheetFromVorbisComment() throws {
        let cueText = """
        FILE "self.flac" FLAC
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let flacURL = dir.appendingPathComponent("a.flac")
        try makeFlac(comments: [("CUESHEET", cueText)]).write(to: flacURL)

        let extracted = try FlacCueExtractor.extractCueSheet(from: flacURL)
        #expect(extracted == cueText)
    }

    @Test func returnsNilWhenNoCuesheetTag() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let flacURL = dir.appendingPathComponent("a.flac")
        try makeFlac(comments: [("TITLE", "Foo"), ("ARTIST", "Bar")]).write(to: flacURL)

        let extracted = try FlacCueExtractor.extractCueSheet(from: flacURL)
        #expect(extracted == nil)
    }

    @Test func throwsForNonFlacFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("not.flac")
        try Data("This is not a FLAC file".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            _ = try FlacCueExtractor.extractCueSheet(from: url)
        }
    }
}
