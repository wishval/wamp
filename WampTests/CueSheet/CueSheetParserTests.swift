import XCTest
@testable import Wamp

final class CueSheetParserTests: XCTestCase {
    func test_cueTrack_framesToSeconds_75framesIsOneSecond() {
        let track = CueTrack(number: 1, title: nil, performer: nil, startFrames: 75)
        XCTAssertEqual(CueSheet.framesToSeconds(track.startFrames), 1.0, accuracy: 1e-9)
    }
}
