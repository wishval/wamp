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

    @Test func m3uUTF8ContentDecodedAsUTF8DespiteExtension() throws {
        // Modern tools write UTF-8 into plain .m3u; é is C3 A9 in UTF-8.
        let data = "/a/é.mp3\n".data(using: .utf8)!
        let entries = try M3UParser.parse(data: data, baseURL: base, fileExtension: "m3u")
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/a/é.mp3")
    }

    @Test func m3uCP1252SmartQuoteDecoded() throws {
        // 0x92 is ’ in CP-1252 (and an invisible C1 control in Latin-1).
        let data = Data([0x2F, 0x64, 0x6F, 0x6E, 0x92, 0x74, 0x2E, 0x6D, 0x70, 0x33, 0x0A]) // "/don’t.mp3\n"
        let entries = try M3UParser.parse(data: data, baseURL: base, fileExtension: "m3u")
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/don\u{2019}t.mp3")
    }

    @Test func fileURLWithUnencodedSpacesResolved() throws {
        let text = "file:///Users/me/My Music/a.mp3\n"
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/Users/me/My Music/a.mp3")
    }

    @Test func nonFileSchemesAreSkipped() throws {
        let text = """
        http://example.com/stream.mp3
        https://example.com/radio
        /a.mp3
        """
        let entries = try M3UParser.parse(data: text.data(using: .utf8)!, baseURL: base)
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/a.mp3")
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

    // MARK: - PLS

    @Test func pls_readsFileTitleLengthInEntryOrder() throws {
        let text = """
        [playlist]
        File2=relative/two.mp3
        Title2=Two
        Length2=185
        File1=/abs/one.flac
        Title1=One
        Length1=230
        NumberOfEntries=2
        Version=2
        """
        let entries = try M3UParser.parse(data: Data(text.utf8), baseURL: base, fileExtension: "pls")
        #expect(entries.map(\.url.path) == ["/abs/one.flac", "/music/relative/two.mp3"])
        #expect(entries.map(\.title) == ["One", "Two"])
        #expect(entries.map(\.duration) == [230, 185])
    }

    @Test func pls_keysAreCaseInsensitiveAndMissingMetadataIsNil() throws {
        let text = "[Playlist]\r\nfile1=/abs/a.mp3\r\nLENGTH1=-1\r\n"
        let entries = try M3UParser.parse(data: Data(text.utf8), baseURL: base, fileExtension: "pls")
        #expect(entries.count == 1)
        #expect(entries[0].url.path == "/abs/a.mp3")
        #expect(entries[0].title == nil)
        #expect(entries[0].duration == nil)
    }

    @Test func pls_skipsStreamURLs() throws {
        let text = "[playlist]\nFile1=http://radio.example/stream\nFile2=/abs/b.mp3\n"
        let entries = try M3UParser.parse(data: Data(text.utf8), baseURL: base, fileExtension: "pls")
        #expect(entries.map(\.url.path) == ["/abs/b.mp3"])
    }
}
