import Testing
import Foundation
@testable import Wamp

@Suite("Lyrics")
struct LyricsTests {

    @Test func parser_decodesSyncedStructuredLyrics() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","lyricsList":{"structuredLyrics":[
          {"displayArtist":"Iron Maiden","displayTitle":"Iron Maiden","lang":"xxx","synced":true,
           "line":[{"start":19540,"value":"Won't you come into my room?"},{"start":22000,"value":"I wanna show you all my wares"}]}
        ]}}}
        """
        let list = try SubsonicResponseParser.decode(SubsonicLyricsList.self, from: Data(json.utf8), key: "lyricsList")
        let block = try #require(list.structuredLyrics?.first)
        #expect(block.isSynced)
        #expect(block.lines.count == 2)
        #expect(block.lines[0].start == 19540)
        #expect(block.plainText.hasPrefix("Won't you come"))
    }

    @Test func parser_unsyncedLyricsHaveNoTimestamps() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","lyricsList":{"structuredLyrics":[
          {"displayArtist":"2Pac","displayTitle":"2 Gangsta","lang":"xxx","synced":false,
           "line":[{"value":"2Pac on a radio"}]}]}}}
        """
        let list = try SubsonicResponseParser.decode(SubsonicLyricsList.self, from: Data(json.utf8), key: "lyricsList")
        let block = try #require(list.structuredLyrics?.first)
        #expect(!block.isSynced)
        #expect(block.lines.first?.start == nil)
    }

    @Test func parser_emptyLyricsListMeansNoLyrics() throws {
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1","lyricsList":{}}}"#
        let list = try SubsonicResponseParser.decode(SubsonicLyricsList.self, from: Data(json.utf8), key: "lyricsList")
        #expect(list.structuredLyrics == nil)
        #expect(LyricsSync.preferred(list.structuredLyrics ?? []) == nil)
    }

    @Test func preferred_choosesSyncedBlockOverUnsynced() {
        let unsynced = SubsonicLyrics(displayArtist: nil, displayTitle: nil, lang: "eng", synced: false,
                                      line: [SubsonicLyricsLine(start: nil, value: "a")])
        let synced = SubsonicLyrics(displayArtist: nil, displayTitle: nil, lang: "eng", synced: true,
                                    line: [SubsonicLyricsLine(start: 0, value: "a")])
        #expect(LyricsSync.preferred([unsynced, synced]) == synced)
        #expect(LyricsSync.preferred([unsynced]) == unsynced)
    }

    @Test func currentLineIndex_followsTimestamps() {
        let starts = [1000, 5000, 9000]
        #expect(LyricsSync.currentLineIndex(startsMs: starts, time: 0.5) == nil)
        #expect(LyricsSync.currentLineIndex(startsMs: starts, time: 1.0) == 0)
        #expect(LyricsSync.currentLineIndex(startsMs: starts, time: 4.999) == 0)
        #expect(LyricsSync.currentLineIndex(startsMs: starts, time: 5.0) == 1)
        #expect(LyricsSync.currentLineIndex(startsMs: starts, time: 60) == 2)
        #expect(LyricsSync.currentLineIndex(startsMs: [], time: 3) == nil)
    }
}
