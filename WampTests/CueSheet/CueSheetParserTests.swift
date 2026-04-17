import XCTest
@testable import Wamp

final class CueSheetParserTests: XCTestCase {
    func test_cueTrack_framesToSeconds_75framesIsOneSecond() {
        let track = CueTrack(number: 1, title: nil, performer: nil, startFrames: 75)
        XCTAssertEqual(CueSheet.framesToSeconds(track.startFrames), 1.0, accuracy: 1e-9)
    }

    func test_parses_single_file_with_two_tracks() throws {
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
        XCTAssertEqual(sheet.title, "DJ Mix vol. 3")
        XCTAssertEqual(sheet.performer, "DJ X")
        XCTAssertEqual(sheet.files.count, 1)
        let file = sheet.files[0]
        XCTAssertEqual(file.path, "mix.flac")
        XCTAssertEqual(file.format, "WAVE")
        XCTAssertEqual(file.tracks.count, 2)
        XCTAssertEqual(file.tracks[0].number, 1)
        XCTAssertEqual(file.tracks[0].title, "Opening")
        XCTAssertEqual(file.tracks[0].performer, "DJ X")
        XCTAssertEqual(file.tracks[0].startFrames, 0)
        XCTAssertEqual(file.tracks[1].number, 2)
        XCTAssertEqual(file.tracks[1].title, "Second tune")
        // 5 min 32 sec 40 frames = (5*60 + 32)*75 + 40 = 24 940
        XCTAssertEqual(file.tracks[1].startFrames, (5*60 + 32)*75 + 40)
    }

    func test_parses_top_level_metadata_with_no_files() {
        let cue = """
        REM GENRE "Electronic"
        REM DATE 2003
        PERFORMER "Various Artists"
        TITLE "DJ Mix vol. 3"
        """
        let data = cue.data(using: .utf8)!
        XCTAssertThrowsError(try CueSheetParser.parse(data)) { error in
            XCTAssertEqual(error as? CueParseError, .noTracks)
        }
    }
}
