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

    /// Sample-level continuity invariant: for any two adjacent virtual tracks the end
    /// of track N must equal the start of track N+1, so chained segment playback
    /// contains no silent gap and no duplicated samples across the boundary.
    @Test func adjacentTracksHaveContinuousOffsets() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wavURL = dir.appendingPathComponent("mix.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let writer = try AVAudioFile(forWriting: wavURL, settings: format.settings)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 120)!
        buf.frameLength = 44_100 * 120
        try writer.write(from: buf)

        let cueURL = dir.appendingPathComponent("mix.cue")
        try """
        FILE "mix.wav" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            INDEX 01 00:37:45
          TRACK 03 AUDIO
            INDEX 01 01:15:10
          TRACK 04 AUDIO
            INDEX 01 01:42:20
        """.write(to: cueURL, atomically: true, encoding: .utf8)

        let sheet = try CueSheetParser.parse(url: cueURL)
        let tracks = try await CueResolver.resolveTracks(
            cue: sheet, cueDirectory: cueURL.deletingLastPathComponent())

        for i in 0..<(tracks.count - 1) {
            let a = tracks[i]
            let b = tracks[i + 1]
            guard let aEnd = a.cueEnd, let bStart = b.cueStart else {
                Issue.record("track \(i) missing cueEnd or track \(i + 1) missing cueStart")
                continue
            }
            // Exact equality in Double — the resolver assigns track N+1's cueStart as
            // its own computed seconds and copies the same value into track N's cueEnd.
            // Any inequality means our arithmetic drifted and a gap/overlap exists.
            #expect(aEnd == bStart,
                    "boundary \(i)→\(i+1) not continuous: end=\(aEnd) start=\(bStart)")
        }
        // Last track extends to EOF.
        #expect(tracks.last?.cueEnd == nil)
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
