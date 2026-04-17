import Foundation

struct CueSheet: Equatable {
    let title: String?
    let performer: String?
    let genre: String?
    let date: String?
    let files: [CueFile]

    /// Convert CD-frame count (1/75 sec) to seconds.
    static func framesToSeconds(_ frames: Int) -> Double {
        Double(frames) / 75.0
    }
}

struct CueFile: Equatable {
    let path: String
    let format: String
    let tracks: [CueTrack]
}

struct CueTrack: Equatable {
    let number: Int
    let title: String?
    let performer: String?
    /// 1/75-second units, as authored in INDEX 01.
    let startFrames: Int
}

enum CueParseError: Error, Equatable {
    case encoding
    case malformed(line: Int, reason: String)
    case noTracks
}
