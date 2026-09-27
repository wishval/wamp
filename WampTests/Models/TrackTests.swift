import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("Track")
struct TrackTests {

    private func fixtureURL(file: StaticString = #filePath) -> URL {
        // #filePath → .../WampTests/Models/TrackTests.swift
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // WampTests/Models
            .deletingLastPathComponent()   // WampTests
            .appendingPathComponent("Fixtures/sample.m4a")
    }

    @Test func fromURL_parsesMetadataTags() async {
        let track = await Track.fromURL(fixtureURL())
        #expect(track.title == "Wamp Fixture Title")
        #expect(track.artist == "Wamp Fixture Artist")
        #expect(track.album == "Wamp Fixture Album")
        #expect(track.genre == "Electronic")
    }

    @Test func fromURL_parsesAudioFormat() async {
        let track = await Track.fromURL(fixtureURL())
        #expect(track.channels == 2)
        #expect(track.sampleRate == 44_100)
        #expect(track.duration > 0.3)
        #expect(track.duration < 0.8)
    }

    @Test(arguments: [2, 3, 4])
    func fromURL_decodesWindows1251ID3v2(version: Int) async throws {
        let url = try taggedMP3(version: version, fields: [
            ("TIT2", "Группа крови", 0, .windowsCP1251),
            ("TPE1", "Кино", 0, .windowsCP1251),
            ("TALB", "Последний герой", 0, .windowsCP1251)
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let track = await Track.fromURL(url)
        #expect(track.title == "Группа крови")
        #expect(track.artist == "Кино")
        #expect(track.album == "Последний герой")
        #expect(track.duration > 0)
        #expect(track.sampleRate == 44_100)
    }

    @Test func fromURL_decodesWindows1251ID3v1() async throws {
        var data = try mp3Audio()
        data.append(contentsOf: "TAG".utf8)
        for value in ["Группа крови", "Кино", "Последний герой"] {
            let bytes = try #require(value.data(using: .windowsCP1251))
            data.append(bytes)
            data.append(Data(repeating: 0, count: 30 - bytes.count))
        }
        data.append(Data(repeating: 0, count: 35))
        let url = try writeMP3(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let track = await Track.fromURL(url)
        #expect(track.title == "Группа крови")
        #expect(track.artist == "Кино")
        #expect(track.album == "Последний герой")
    }

    @Test(arguments: [String.Encoding.utf8, .utf16, .utf16BigEndian])
    func fromURL_preservesUnicodeID3(encoding: String.Encoding) async throws {
        let marker: UInt8 = encoding == .utf8 ? 3 : (encoding == .utf16 ? 1 : 2)
        let url = try taggedMP3(version: 4, fields: [
            ("TIT2", "Привет — 日本語", marker, encoding),
            ("TPE1", "Björk", marker, encoding)
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let track = await Track.fromURL(url)
        #expect(track.title == "Привет — 日本語")
        #expect(track.artist == "Björk")
    }

    @Test func fromURL_preservesWesternID3() async throws {
        let url = try taggedMP3(version: 3, fields: [
            ("TIT2", "Crème brûlée", 0, .isoLatin1),
            ("TPE1", "Björk", 0, .isoLatin1),
            ("TALB", "Café", 0, .isoLatin1)
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let track = await Track.fromURL(url)
        #expect(track.title == "Crème brûlée")
        #expect(track.artist == "Björk")
        #expect(track.album == "Café")
    }

    private func mp3Audio(file: StaticString = #filePath) throws -> Data {
        // 0.5 seconds of silence, generated with ffmpeg/libmp3lame without ID3
        // or Xing headers. Tests write their own tag bytes onto this fixture.
        let url = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.mp3")
        return try Data(contentsOf: url)
    }

    private func writeMP3(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Wamp-ID3-\(UUID().uuidString).mp3")
        try data.write(to: url)
        return url
    }

    private func taggedMP3(version: Int, fields: [(String, String, UInt8, String.Encoding)]) throws -> URL {
        let v22Keys = ["TIT2": "TT2", "TPE1": "TP1", "TALB": "TAL"]
        var body = Data()
        for (key, value, marker, encoding) in fields {
            let text = try #require(value.data(using: encoding))
            let payload = Data([marker]) + text
            body.append(contentsOf: (version == 2 ? v22Keys[key]! : key).utf8)
            if version == 2 {
                body.append(contentsOf: [16, 8, 0].map { UInt8((payload.count >> $0) & 255) })
            } else {
                body.append(contentsOf: version == 4 ? syncsafe(payload.count)
                    : [24, 16, 8, 0].map { UInt8((payload.count >> $0) & 255) })
                body.append(contentsOf: [0, 0])
            }
            body.append(payload)
        }
        let header = Data("ID3".utf8) + Data([UInt8(version), 0, 0]) + Data(syncsafe(body.count))
        return try writeMP3(header + body + mp3Audio())
    }

    private func syncsafe(_ size: Int) -> [UInt8] {
        [21, 14, 7, 0].map { UInt8((size >> $0) & 127) }
    }

    @Test func fromURL_unreadableFile_fallsBackToFilename() async {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")
        let track = await Track.fromURL(bogus)
        #expect(track.title == bogus.deletingPathExtension().lastPathComponent)
        #expect(track.duration == 0)
    }

    @Test func displayTitle_formatsArtistAndTitle() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Band", album: "", duration: 0)
        #expect(track.displayTitle == "Band - Song")
    }

    @Test func displayTitle_withoutArtist_returnsTitleOnly() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Unknown Artist", album: "", duration: 0)
        #expect(track.displayTitle == "Song")
    }

    @Test func formattedDuration_minutesAndSeconds() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "", artist: "", album: "", duration: 125)
        #expect(track.formattedDuration == "2:05")
    }

    @Test func isCueVirtualFalseByDefault() {
        let t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 1)
        #expect(t.cueStart == nil)
        #expect(t.cueEnd == nil)
        #expect(t.isCueVirtual == false)
    }

    @Test func isCueVirtualTrueWhenCueStartSet() {
        var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 30)
        t.cueStart = 10
        t.cueEnd = 40
        #expect(t.isCueVirtual == true)
    }

    @Test func codableRoundTripPreservesCueRange() throws {
        var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 30)
        t.cueStart = 10.5
        t.cueEnd = 40.25
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded.cueStart == 10.5)
        #expect(decoded.cueEnd == 40.25)
    }
}
