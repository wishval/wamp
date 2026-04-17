import Testing
import Foundation
@testable import Wamp

@Suite("CueSheetParser")
struct CueSheetParserTests {

    private func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // WampTests/CueSheet
            .deletingLastPathComponent()   // WampTests
            .appendingPathComponent("Fixtures/cue/\(name).cue")
    }

    @Test func cueTrack_framesToSeconds_75framesIsOneSecond() {
        let track = CueTrack(number: 1, title: nil, performer: nil, startFrames: 75)
        #expect(abs(CueSheet.framesToSeconds(track.startFrames) - 1.0) < 1e-9)
    }

    @Test func parsesSingleFileWithTwoTracks() throws {
        let cue = """
        PERFORMER "DJ X"
        TITLE "DJ Mix vol. 3"
        FILE "mix.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Opening"
            PERFORMER "DJ X"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Second tune"
            PERFORMER "DJ Y"
            INDEX 01 05:32:40
        """
        let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
        #expect(sheet.title == "DJ Mix vol. 3")
        #expect(sheet.performer == "DJ X")
        #expect(sheet.files.count == 1)
        let fileEntry = sheet.files[0]
        #expect(fileEntry.path == "mix.flac")
        #expect(fileEntry.format == "WAVE")
        #expect(fileEntry.tracks.count == 2)
        #expect(fileEntry.tracks[0].number == 1)
        #expect(fileEntry.tracks[0].title == "Opening")
        #expect(fileEntry.tracks[0].performer == "DJ X")
        #expect(fileEntry.tracks[0].startFrames == 0)
        #expect(fileEntry.tracks[1].number == 2)
        #expect(fileEntry.tracks[1].title == "Second tune")
        #expect(fileEntry.tracks[1].startFrames == (5*60 + 32)*75 + 40)
    }

    @Test func parsesTopLevelMetadataWithNoFiles() {
        let cue = """
        REM GENRE "Electronic"
        REM DATE 2003
        PERFORMER "Various Artists"
        TITLE "DJ Mix vol. 3"
        """
        #expect(throws: CueParseError.noTracks) {
            try CueSheetParser.parse(cue.data(using: .utf8)!)
        }
    }

    @Test func index00PregapIsIgnoredWhenIndex01Present() throws {
        let cue = """
        FILE "a.wav" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            INDEX 00 05:30:00
            INDEX 01 05:32:40
        """
        let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
        #expect(sheet.files[0].tracks[1].startFrames == (5*60 + 32)*75 + 40)
    }

    @Test func multiFileCue() throws {
        let cue = """
        FILE "a.wav" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        FILE "b.wav" WAVE
          TRACK 02 AUDIO
            INDEX 01 00:00:00
        """
        let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
        #expect(sheet.files.count == 2)
        #expect(sheet.files[0].path == "a.wav")
        #expect(sheet.files[0].tracks.first?.number == 1)
        #expect(sheet.files[1].path == "b.wav")
        #expect(sheet.files[1].tracks.first?.number == 2)
    }

    @Test func trackWithoutIndex01IsMalformed() throws {
        let cue = """
        FILE "a.wav" WAVE
          TRACK 01 AUDIO
            TITLE "x"
        """
        do {
            _ = try CueSheetParser.parse(cue.data(using: .utf8)!)
            Issue.record("expected throw")
        } catch let err as CueParseError {
            guard case .malformed(let line, let reason) = err else {
                Issue.record("expected .malformed, got \(err)")
                return
            }
            #expect(line > 0)
            #expect(reason.contains("INDEX 01"))
        }
    }

    @Test func trackBeforeFileIsMalformedWithLineNumber() throws {
        let cue = """
        TRACK 01 AUDIO
          INDEX 01 00:00:00
        """
        do {
            _ = try CueSheetParser.parse(cue.data(using: .utf8)!)
            Issue.record("expected throw")
        } catch let err as CueParseError {
            guard case .malformed(let line, _) = err else {
                Issue.record("expected .malformed, got \(err)")
                return
            }
            #expect(line == 1)
        }
    }

    @Test func invalidTimecodeIsMalformed() throws {
        let cue = """
        FILE "a.wav" WAVE
          TRACK 01 AUDIO
            INDEX 01 99:99:99
        """
        do {
            _ = try CueSheetParser.parse(cue.data(using: .utf8)!)
            Issue.record("expected throw")
        } catch let err as CueParseError {
            guard case .malformed(_, let reason) = err else {
                Issue.record("expected .malformed, got \(err)")
                return
            }
            #expect(reason.contains("timecode"))
        }
    }

    @Test func unquotedFilePath() throws {
        let cue = """
        FILE mix.flac WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """
        let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
        #expect(sheet.files[0].path == "mix.flac")
        #expect(sheet.files[0].format == "WAVE")
    }

    @Test func filePathWithSpacesInQuotes() throws {
        let cue = """
        FILE "a long name.flac" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """
        let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
        #expect(sheet.files[0].path == "a long name.flac")
    }

    // MARK: - Fixture-backed tests

    @Test func basicFixture() throws {
        let sheet = try CueSheetParser.parse(url: fixtureURL("basic"))
        #expect(sheet.title == "DJ Mix vol. 3")
        #expect(sheet.genre == "Electronic")
        #expect(sheet.date == "2003")
        #expect(sheet.files.first?.tracks.count == 2)
        #expect(sheet.files.first?.tracks[1].startFrames == (5*60 + 32)*75 + 40)
    }

    @Test func multiFileFixture() throws {
        let sheet = try CueSheetParser.parse(url: fixtureURL("multi-file"))
        #expect(sheet.files.count == 2)
        #expect(sheet.files[1].tracks.first?.number == 3)
    }

    @Test func zeroTracksFixtureThrowsNoTracks() {
        #expect(throws: CueParseError.noTracks) {
            try CueSheetParser.parse(url: self.fixtureURL("zero-tracks"))
        }
    }

    @Test func cp1251FixtureDecodesCyrillicTitles() throws {
        let sheet = try CueSheetParser.parse(url: fixtureURL("cp1251"))
        #expect(sheet.title == "Микс №3")
        #expect(sheet.files.first?.tracks.first?.title == "Начало")
    }

    @Test func shiftJisFixtureDecodesJapaneseTitles() throws {
        let sheet = try CueSheetParser.parse(url: fixtureURL("shift-jis"))
        #expect(sheet.title == "日本のミックス")
        #expect(sheet.files.first?.tracks.first?.title == "序章")
    }

    @Test func cp1252FixtureDecodesFrenchDiacritics() throws {
        let sheet = try CueSheetParser.parse(url: fixtureURL("cp1252"))
        #expect(sheet.title == "Été")
        #expect(sheet.performer == "Café Crème")
    }
}
