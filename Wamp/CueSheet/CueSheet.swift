import Foundation

public struct CueSheet: Equatable {
    public let title: String?
    public let performer: String?
    public let genre: String?
    public let date: String?
    public let files: [CueFile]

    /// Convert CD-frame count (1/75 sec) to seconds.
    public static func framesToSeconds(_ frames: Int) -> Double {
        Double(frames) / 75.0
    }
}

public struct CueFile: Equatable {
    public let path: String
    public let format: String
    public let tracks: [CueTrack]
}

public struct CueTrack: Equatable {
    public let number: Int
    public let title: String?
    public let performer: String?
    /// 1/75-second units, as authored in INDEX 01.
    public let startFrames: Int
}

public enum CueParseError: Error, Equatable {
    case encoding
    case malformed(line: Int, reason: String)
    case noTracks
}
