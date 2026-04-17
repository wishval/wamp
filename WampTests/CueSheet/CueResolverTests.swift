import Testing
import Foundation
import AVFoundation
@testable import Wamp

@MainActor
@Suite("CueResolver")
struct CueResolverTests {

    /// Build a 60-second 44.1 kHz mono silent WAV in a temp dir, then a matching cue.
    private func makeSilentWavAndCue() throws -> (wavURL: URL, cueURL: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wavURL = dir.appendingPathComponent("mix.wav")

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * 60)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)

        let cueText = """
        FILE "mix.wav" WAVE
          TRACK 01 AUDIO
            TITLE "First"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Second"
            INDEX 01 00:30:00
        """
        let cueURL = dir.appendingPathComponent("mix.cue")
        try cueText.write(to: cueURL, atomically: true, encoding: .utf8)
        return (wavURL, cueURL)
    }

    @Test func resolvesTwoVirtualTracksWithCorrectRanges() async throws {
        let (_, cueURL) = try makeSilentWavAndCue()
        let sheet = try CueSheetParser.parse(url: cueURL)
        let tracks = try await CueResolver.resolveTracks(
            cue: sheet, cueDirectory: cueURL.deletingLastPathComponent())
        #expect(tracks.count == 2)

        #expect(tracks[0].isCueVirtual)
        #expect(tracks[0].cueStart == 0)
        let end0 = tracks[0].cueEnd ?? -1
        #expect(abs(end0 - 30) < 0.001)
        #expect(abs(tracks[0].duration - 30) < 0.001)
        #expect(tracks[0].title == "First")

        let start1 = tracks[1].cueStart ?? -1
        #expect(abs(start1 - 30) < 0.001)
        #expect(tracks[1].cueEnd == nil) // last track plays to EOF
        #expect(abs(tracks[1].duration - 30) < 0.01)
    }

    @Test func missingAudioFileThrows() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sheet = CueSheet(
            title: nil, performer: nil, genre: nil, date: nil,
            files: [CueFile(path: "missing.wav", format: "WAVE",
                            tracks: [CueTrack(number: 1, title: nil, performer: nil, startFrames: 0)])]
        )
        await #expect(throws: (any Error).self) {
            _ = try await CueResolver.resolveTracks(cue: sheet, cueDirectory: dir)
        }
    }
}
