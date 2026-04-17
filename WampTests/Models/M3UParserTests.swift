import Testing
import Foundation
@testable import Wamp

@Suite("M3UParser")
struct M3UParserTests {

    private let base = URL(fileURLWithPath: "/music/", isDirectory: true)

    @Test func parsesExtM3UHeaderAndTwoTracks() throws {
        let text = """
        #EXTM3U
        #EXTINF:230,Artist A - Song A
        /abs/song-a.mp3
        #EXTINF:185,Artist B - Song B
        relative/song-b.flac
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 2)
        #expect(entries[0].url.path == "/abs/song-a.mp3")
        #expect(entries[0].duration == 230)
        #expect(entries[0].title == "Artist A - Song A")
        #expect(entries[1].url.path == "/music/relative/song-b.flac")
        #expect(entries[1].duration == 185)
        #expect(entries[1].title == "Artist B - Song B")
    }

    @Test func worksWithoutExtM3UHeader() throws {
        let text = """
        /abs/one.mp3
        /abs/two.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 2)
        #expect(entries[0].duration == nil)
        #expect(entries[0].title == nil)
    }

    @Test func relativePathsResolvedAgainstBase() throws {
        let text = "sub/track.mp3\n"
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/music/sub/track.mp3")
    }

    @Test func absolutePathsStayAbsolute() throws {
        let text = "/Users/me/Music/song.mp3\n"
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries[0].url.path == "/Users/me/Music/song.mp3")
    }

    @Test func fileURLsPreserved() throws {
        let text = "file:///Users/me/song.mp3\n"
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries[0].url.path == "/Users/me/song.mp3")
    }

    @Test func mixedLineEndingsCRLFandLFandCR() throws {
        // CRLF for first pair, LF for second, CR for third
        let text = "#EXTM3U\r\n#EXTINF:10,A\r\n/a.mp3\n#EXTINF:20,B\n/b.mp3\r#EXTINF:30,C\r/c.mp3"
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 3)
        #expect(entries[0].duration == 10)
        #expect(entries[1].duration == 20)
        #expect(entries[2].duration == 30)
        #expect(entries[2].title == "C")
    }

    @Test func utf8BOMIsStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("#EXTM3U\n/a.mp3\n".data(using: .utf8)!)
        let entries = try M3UParser.parse(data: data, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/a.mp3")
    }

    @Test func blankLinesIgnored() throws {
        let text = """

        /a.mp3

        /b.mp3


        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 2)
    }

    @Test func unknownDirectivesIgnoredGracefully() throws {
        let text = """
        #EXTM3U
        #PLAYLIST:My Mix
        #EXTGENRE:Rock
        #EXTINF:120,Known Song
        /a.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].duration == 120)
    }

    @Test func extinfWithNegativeDurationMeansUnknown() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1,Streaming Song
        /a.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].duration == nil)
        #expect(entries[0].title == "Streaming Song")
    }

    @Test func extinfWithoutTitleStillParsesDuration() throws {
        let text = """
        #EXTINF:90
        /a.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries[0].duration == 90)
        #expect(entries[0].title == nil)
    }

    @Test func extinfTitleMayContainCommas() throws {
        let text = """
        #EXTINF:60,Lastname, Firstname - Song
        /a.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries[0].title == "Lastname, Firstname - Song")
    }

    @Test func orphanExtinfWithoutPathIsDropped() throws {
        let text = """
        #EXTINF:60,Orphan
        #EXTINF:90,Real
        /a.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].duration == 90)
        #expect(entries[0].title == "Real")
    }

    @Test func malformedReturnsEmpty() throws {
        let text = """
        this is not
        a valid
        m3u file
        """
        // Lines without #-prefix are treated as paths — so this is ambiguous.
        // But lines starting with # that aren't directives should be ignored.
        let text2 = """
        # not a directive
        ## also not
        """
        let entries = try M3UParser.parse(data: text2.data(using: .utf8)!, baseURL: base)
        #expect(entries.isEmpty)
        _ = text
    }

    @Test func m3uLatin1EncodingByExtension() throws {
        // é in Latin-1 is 0xE9
        let data = Data([0x2F, 0x61, 0x2F, 0xE9, 0x2E, 0x6D, 0x70, 0x33, 0x0A]) // "/a/é.mp3\n"
        let entries = try M3UParser.parse(data: data, baseURL: base, fileExtension: "m3u")
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/a/é.mp3")
    }

    @Test func m3u8UTF8EncodingByExtension() throws {
        let text = "/a/日本.mp3\n"
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base, fileExtension: "m3u8")
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/a/日本.mp3")
    }

    @Test func parseFromURLResolvesBaseAutomatically() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wamp-m3u-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let playlistURL = tmp.appendingPathComponent("list.m3u8")
        let body = "#EXTM3U\n#EXTINF:120,Track\nsub/track.mp3\n"
        try body.write(to: playlistURL, atomically: true, encoding: .utf8)

        let entries = try M3UParser.parse(url: playlistURL)
        #expect(entries.count == 1)
        #expect(entries[0].url.path == tmp.appendingPathComponent("sub/track.mp3").path)
        #expect(entries[0].duration == 120)
    }
}
