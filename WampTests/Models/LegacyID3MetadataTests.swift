import Testing
import Foundation
@testable import Wamp

@Suite("Legacy ID3 metadata")
struct LegacyID3MetadataTests {
    @Test func detectsCyrillicAcrossShortAndLongFields() throws {
        let fields = try ["TIT2": "Группа крови", "TPE1": "ДДТ", "TALB": "Ёж"]
            .mapValues { try #require($0.data(using: .windowsCP1251)) }
        #expect(LegacyID3Metadata.decode(fields) == ["TIT2": "Группа крови", "TPE1": "ДДТ", "TALB": "Ёж"])
    }

    @Test func leavesWesternTextToAVFoundation() throws {
        let fields = try ["TIT2": "Crème brûlée", "TPE1": "Björk", "TALB": "ÁÉÍÓÚ"]
            .mapValues { try #require($0.data(using: .isoLatin1)) }
        #expect(LegacyID3Metadata.decode(fields).isEmpty)
    }

    @Test func leavesNumericGenresToAVFoundation() throws {
        let fields = ["TIT2": try #require("Привет мир".data(using: .windowsCP1251)),
                      "TCON": Data("(17)".utf8)]
        #expect(LegacyID3Metadata.decode(fields)["TIT2"] == "Привет мир")
        #expect(LegacyID3Metadata.decode(fields)["TCON"] == nil)
    }

    @Test(arguments: [3, 4])
    func handlesExtendedHeaders(version: Int) throws {
        let extended = version == 3 ? Data([0, 0, 0, 6] + Array(repeating: 0, count: 6))
            : Data([0, 0, 0, 6, 1, 0])
        let body = extended + frame(payload: try text("Привет мир"), version: version)
        #expect(try read(tag(body: body, version: version, flags: 0x40))["TIT2"] == "Привет мир")
    }

    @Test(arguments: [3, 4])
    func handlesUnsynchronisation(version: Int) throws {
        let payload = try text("Песня") + Data([0])
        let body: Data
        if version == 3 {
            body = unsynchronise(frame(payload: payload, version: version))
        } else {
            body = frame(payload: unsynchronise(payload), version: version, flags: 0x02)
        }
        #expect(try read(tag(body: body, version: version, flags: version == 3 ? 0x80 : 0))["TIT2"] == "Песня")
    }

    @Test(arguments: [3, 4])
    func skipsGroupingAndDataLengthPrefixes(version: Int) throws {
        let prefix = version == 3 ? Data([42]) : Data([42, 0, 0, 0, 20])
        let body = frame(payload: prefix + (try text("Привет мир")), version: version,
                         flags: version == 3 ? 0x20 : 0x41)
        #expect(try read(tag(body: body, version: version))["TIT2"] == "Привет мир")
    }

    @Test(arguments: [UInt8(0x80), 0x40])
    func skipsCompressedAndEncryptedFrames(flags: UInt8) throws {
        let body = frame(payload: try text("Привет мир"), version: 3, flags: flags)
        #expect(try read(tag(body: body, version: 3)).isEmpty)
    }

    @Test func unicodeV2TitleTakesPrecedenceOverLegacyV1() throws {
        let unicode = Data([1]) + (try #require("Unicode title".data(using: .utf16)))
        var bytes = tag(body: frame(payload: unicode, version: 3), version: 3)
        bytes.append(contentsOf: "TAG".utf8)
        bytes.append(try #require("Группа крови".data(using: .windowsCP1251)))
        bytes.append(Data(repeating: 0, count: 128 - 3 - "Группа крови".count))
        #expect(try read(bytes)["TIT2"] == nil)
    }

    @Test func rejectsTruncatedAndOversizedTags() throws {
        let body = frame(payload: try text("Привет мир"), version: 3)
        #expect(try read(Data(tag(body: body, version: 3).dropLast())).isEmpty)
        #expect(try read(Data("ID3".utf8) + Data([3, 0, 0, 127, 127, 127, 127])).isEmpty)
        #expect(try read(Data("ID3".utf8) + Data([4, 0, 0, 128, 0, 0, 0])).isEmpty)
        #expect(try read(tag(body: Data("TIT2".utf8) + Data([127, 127, 127, 127, 0, 0, 0]), version: 3)).isEmpty)
    }

    private func read(_ data: Data) throws -> [String: String] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wamp-ID3-\(UUID().uuidString).mp3")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return LegacyID3Metadata.read(from: url)
    }

    private func text(_ value: String) throws -> Data {
        Data([0]) + (try #require(value.data(using: .windowsCP1251)))
    }

    private func frame(payload: Data, version: Int, flags: UInt8 = 0) -> Data {
        let size = version == 4 ? syncsafe(payload.count)
            : [24, 16, 8, 0].map { UInt8((payload.count >> $0) & 255) }
        return Data("TIT2".utf8) + Data(size + [0, flags]) + payload
    }

    private func tag(body: Data, version: Int, flags: UInt8 = 0) -> Data {
        Data("ID3".utf8) + Data([UInt8(version), 0, flags] + syncsafe(body.count)) + body
    }

    private func syncsafe(_ size: Int) -> [UInt8] {
        [21, 14, 7, 0].map { UInt8((size >> $0) & 127) }
    }

    private func unsynchronise(_ data: Data) -> Data {
        var result = Data()
        for byte in data {
            result.append(byte)
            if byte == 0xFF { result.append(0) }
        }
        return result
    }
}
