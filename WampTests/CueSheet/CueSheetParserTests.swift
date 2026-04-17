import XCTest
@testable import Wamp

final class CueSheetParserTests: XCTestCase {
    func test_cueTrack_framesToSeconds_75framesIsOneSecond() {
        let track = CueTrack(number: 1, title: nil, performer: nil, startFrames: 75)
        XCTAssertEqual(CueSheet.framesToSeconds(track.startFrames), 1.0, accuracy: 1e-9)
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
