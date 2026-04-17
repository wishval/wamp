import Testing
import Foundation
import AVFoundation
@testable import Wamp

@MainActor
@Suite("PlaylistManager")
struct PlaylistManagerTests {

    private func makeTrack(_ name: String, duration: TimeInterval = 10) -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/\(name).m4a"),
            title: name,
            artist: "A",
            album: "Alb",
            duration: duration
        )
    }

    @Test func addTracks_appends() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b")])
        #expect(pm.tracks.count == 2)
        #expect(pm.currentIndex == -1)
    }

    @Test func removeTrack_beforeCurrent_decrementsIndex() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 2
        pm.removeTrack(at: 0)
        #expect(pm.tracks.count == 2)
        #expect(pm.currentIndex == 1)
    }

    @Test func removeTrack_atCurrent_clampsIndex() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 2
        pm.removeTrack(at: 2)
        #expect(pm.currentIndex == 1)
    }

    @Test func removeTrack_lastRemaining_setsIndexMinusOne() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a")])
        pm.currentIndex = 0
        pm.removeTrack(at: 0)
        #expect(pm.tracks.isEmpty)
        #expect(pm.currentIndex == -1)
    }

    @Test func removeTrack_afterCurrent_leavesIndex() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 0
        pm.removeTrack(at: 2)
        #expect(pm.currentIndex == 0)
    }

    @Test func clearPlaylist_resets() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b")])
        pm.currentIndex = 1
        pm.clearPlaylist()
        #expect(pm.tracks.isEmpty)
        #expect(pm.currentIndex == -1)
    }

    @Test func moveTracks_preservesCurrentTrack() {
        let pm = PlaylistManager()
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("c")]
        pm.addTracks(tracks)
        pm.currentIndex = 1
        pm.moveTracks(from: IndexSet(integer: 0), to: 3)
        #expect(pm.tracks.map(\.title) == ["b", "c", "a"])
        #expect(pm.currentIndex == 0)
    }

    @Test func sortByTitle_sortsAlphabeticallyAndPreservesCurrent() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("Charlie"), makeTrack("alpha"), makeTrack("Bravo")])
        pm.currentIndex = 0 // "Charlie"
        pm.sortByTitle()
        #expect(pm.tracks.map(\.title) == ["alpha", "Bravo", "Charlie"])
        #expect(pm.currentIndex == 2)
    }

    @Test func sortByFilename_sortsByLastPathComponent() {
        let pm = PlaylistManager()
        let t1 = Track(url: URL(fileURLWithPath: "/z/zeta.m4a"),  title: "Z", artist: "", album: "", duration: 1)
        let t2 = Track(url: URL(fileURLWithPath: "/a/alpha.m4a"), title: "A", artist: "", album: "", duration: 1)
        let t3 = Track(url: URL(fileURLWithPath: "/m/mid.m4a"),   title: "M", artist: "", album: "", duration: 1)
        pm.addTracks([t1, t2, t3])
        pm.currentIndex = 0 // zeta
        pm.sortByFilename()
        #expect(pm.tracks.map { $0.url.lastPathComponent } == ["alpha.m4a", "mid.m4a", "zeta.m4a"])
        #expect(pm.currentIndex == 2)
    }

    @Test func sortByPath_sortsByFullPath() {
        let pm = PlaylistManager()
        let t1 = Track(url: URL(fileURLWithPath: "/b/song.m4a"), title: "B", artist: "", album: "", duration: 1)
        let t2 = Track(url: URL(fileURLWithPath: "/a/song.m4a"), title: "A", artist: "", album: "", duration: 1)
        pm.addTracks([t1, t2])
        pm.sortByPath()
        #expect(pm.tracks.map(\.url.path) == ["/a/song.m4a", "/b/song.m4a"])
    }

    @Test func reverseList_reversesAndFollowsCurrent() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c"), makeTrack("d")])
        pm.currentIndex = 1 // "b"
        pm.reverseList()
        #expect(pm.tracks.map(\.title) == ["d", "c", "b", "a"])
        #expect(pm.currentIndex == 2)
    }

    @Test func shuffleTracks_preservesCurrentTrackAndCount() {
        let pm = PlaylistManager()
        let tracks = (0..<20).map { makeTrack("t\($0)") }
        pm.addTracks(tracks)
        pm.currentIndex = 5
        let currentBefore = pm.tracks[pm.currentIndex]
        pm.shuffleTracks()
        #expect(pm.tracks.count == 20)
        #expect(Set(pm.tracks.map(\.url)) == Set(tracks.map(\.url)))
        #expect(pm.tracks[pm.currentIndex].url == currentBefore.url)
    }

    @Test func totalDuration_sumsAcrossTracks() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a", duration: 60), makeTrack("b", duration: 90)])
        #expect(pm.totalDuration == 150)
    }

    @Test func formattedTotalDurationCompact_stripsSeconds() {
        let pm = PlaylistManager()
        // 2h 3m 45s — seconds must be dropped, hours padded naturally.
        pm.addTracks([makeTrack("a", duration: 2 * 3600 + 3 * 60 + 45)])
        #expect(pm.formattedTotalDurationCompact == "2:03")
        // Under an hour: just minutes.
        pm.clearPlaylist()
        pm.addTracks([makeTrack("a", duration: 7 * 60 + 30)])
        #expect(pm.formattedTotalDurationCompact == "7")
    }

    @Test func filteredTracks_searchQueryMatchesTitle() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("Alpha"), makeTrack("Beta"), makeTrack("alphabet")])
        pm.searchQuery = "alpha"
        #expect(pm.filteredTracks.count == 2)
    }

    @Test func advanceToNext_viaNotification_advancesIndex() async {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 0
        NotificationCenter.default.post(name: .trackDidFinish, object: nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(pm.currentIndex == 1)
    }

    // MARK: - CUE sheet support

    private func makeSilentWav(in dir: URL, name: String = "mix.wav", seconds: Double = 1) throws -> URL {
        let wavURL = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
        return wavURL
    }

    @Test func addCueSheet_appendsVirtualTracks() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try makeSilentWav(in: dir)
        let cueURL = dir.appendingPathComponent("mix.cue")
        try """
        FILE "mix.wav" WAVE
          TRACK 01 AUDIO
            TITLE "A"
            INDEX 01 00:00:00
        """.write(to: cueURL, atomically: true, encoding: .utf8)

        let pm = PlaylistManager()
        try await pm.addCueSheet(url: cueURL)
        #expect(pm.tracks.count == 1)
        #expect(pm.tracks[0].isCueVirtual)
        #expect(pm.tracks[0].title == "A")
    }

    @Test func addURLs_flacWithSiblingCueExpandsToVirtualTracks() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The sibling cue refers to "song.wav" (a format AVFoundation can read).
        let wavURL = dir.appendingPathComponent("song.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        try file.write(from: buffer)
        // Place a zero-byte .flac beside it — the parser short-circuits to the sibling cue
        // before touching the flac content, so no real FLAC bytes are required.
        let flacURL = dir.appendingPathComponent("song.flac")
        try Data().write(to: flacURL)
        let cueURL = dir.appendingPathComponent("song.cue")
        try """
        FILE "song.wav" WAVE
          TRACK 01 AUDIO
            TITLE "A"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "B"
            INDEX 01 00:00:30
        """.write(to: cueURL, atomically: true, encoding: .utf8)

        let pm = PlaylistManager()
        await pm.addURLs([flacURL])
        #expect(pm.tracks.count == 2)
        #expect(pm.tracks[0].isCueVirtual)
        #expect(pm.tracks[0].title == "A")
        #expect(pm.tracks[1].title == "B")
    }

    @Test func addCueSheet_missingAudioThrows() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cueURL = dir.appendingPathComponent("orphan.cue")
        try """
        FILE "missing.wav" WAVE
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """.write(to: cueURL, atomically: true, encoding: .utf8)
        let pm = PlaylistManager()
        await #expect(throws: (any Error).self) {
            try await pm.addCueSheet(url: cueURL)
        }
    }
}
