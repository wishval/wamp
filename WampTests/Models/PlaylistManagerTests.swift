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

    @Test func shuffleTracks_followsCurrentTrackIdentityWithDuplicateURLs() {
        // Two entries share one URL (duplicate file in the playlist). After a
        // shuffle the *instance* being played must stay current — matching by
        // URL snaps to whichever duplicate shuffled in front.
        let url = URL(fileURLWithPath: "/tmp/dup.m4a")
        let dup1 = Track(url: url, title: "dup", artist: "A", album: "X", duration: 10)
        let dup2 = Track(url: url, title: "dup", artist: "A", album: "X", duration: 10)
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), dup1, makeTrack("b"), dup2, makeTrack("c")])
        pm.currentIndex = 3 // dup2
        let playingID = dup2.id
        for _ in 0..<20 {
            pm.shuffleTracks()
            #expect(pm.tracks[pm.currentIndex].id == playingID)
        }
    }

    @Test func removeTrack_currentlyPlaying_engineStopsClaimingRemovedTrack() {
        // Deleting the playing row must not leave the engine "playing" the
        // removed file while the highlight shows the next track. The engine
        // either starts the track that slid into the slot or stops.
        let engine = AudioEngine()
        engine.isPlaying = true
        engine.playState = .playing
        let pm = PlaylistManager()
        pm.setAudioEngine(engine)
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 1
        pm.removeTrack(at: 1)
        #expect(pm.tracks.map(\.title) == ["a", "c"])
        #expect(pm.currentIndex == 1)
        #expect(engine.playState != .playing)
    }

    @Test func removeTrack_playingLastTrack_stops() {
        let engine = AudioEngine()
        engine.isPlaying = true
        engine.playState = .playing
        let pm = PlaylistManager()
        pm.setAudioEngine(engine)
        pm.addTracks([makeTrack("a"), makeTrack("b")])
        pm.currentIndex = 1
        pm.removeTrack(at: 1)
        #expect(pm.tracks.map(\.title) == ["a"])
        #expect(pm.currentIndex == 0)
        #expect(engine.isPlaying == false)
    }

    @Test func clearPlaylist_whilePlaying_stopsEngine() {
        let engine = AudioEngine()
        engine.isPlaying = true
        engine.playState = .playing
        let pm = PlaylistManager()
        pm.setAudioEngine(engine)
        pm.addTracks([makeTrack("a")])
        pm.currentIndex = 0
        pm.clearPlaylist()
        #expect(engine.isPlaying == false)
        #expect(pm.currentIndex == -1)
    }

    @Test func clearPlaylist_whilePaused_stopsEngine() {
        // A paused, now-orphaned file must not be resumable by Play.
        let engine = AudioEngine()
        engine.playState = .paused
        let pm = PlaylistManager()
        pm.setAudioEngine(engine)
        pm.addTracks([makeTrack("a")])
        pm.currentIndex = 0
        pm.clearPlaylist()
        #expect(engine.playState == .stopped)
    }

    // MARK: - Play button

    private func makeStoppedManager(_ names: [String], current: Int) -> (PlaylistManager, AudioEngine) {
        let engine = AudioEngine()
        let pm = PlaylistManager()
        pm.setAudioEngine(engine)
        pm.addTracks(names.map { makeTrack($0) })
        pm.currentIndex = current
        return (pm, engine)
    }

    @Test func play_whenStopped_startsPreferredRow() {
        let (pm, _) = makeStoppedManager(["a", "b", "c"], current: 0)
        pm.play(preferring: 2)
        #expect(pm.currentIndex == 2)
    }

    @Test func play_whenStoppedWithoutSelection_startsCurrentTrack() {
        let (pm, _) = makeStoppedManager(["a", "b", "c"], current: 1)
        pm.play(preferring: nil)
        #expect(pm.currentIndex == 1)
    }

    @Test func play_whenStoppedWithNoCurrentTrack_startsFirstTrack() {
        // Issue #7: after loading a new list there is no current track, and
        // Play used to resume the engine's leftover file from the old list.
        let (pm, _) = makeStoppedManager(["a", "b"], current: -1)
        pm.play(preferring: nil)
        #expect(pm.currentIndex == 0)
    }

    @Test func play_whenPaused_resumesInsteadOfJumpingToSelection() {
        let (pm, engine) = makeStoppedManager(["a", "b", "c"], current: 0)
        engine.playState = .paused
        pm.play(preferring: 2)
        #expect(pm.currentIndex == 0)
    }

    @Test func play_emptyPlaylist_doesNothing() {
        let (pm, engine) = makeStoppedManager([], current: -1)
        pm.play(preferring: nil)
        #expect(pm.currentIndex == -1)
        #expect(engine.playState == .stopped)
    }

    @Test func addURLs_mixedBatchPreservesInputOrder() async throws {
        // A FLAC with a sibling cue inside a batch must expand *in place*,
        // not jump ahead of files listed before it.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plainURL = try makeSilentWav(in: dir, name: "plain.wav")
        _ = try makeSilentWav(in: dir, name: "album.wav")
        let flacURL = dir.appendingPathComponent("album.flac")
        try Data().write(to: flacURL)
        try """
        FILE "album.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Cue A"
            INDEX 01 00:00:00
        """.write(to: dir.appendingPathComponent("album.cue"), atomically: true, encoding: .utf8)

        let pm = PlaylistManager()
        await pm.addURLs([plainURL, flacURL])
        #expect(pm.tracks.map(\.title) == ["plain", "Cue A"])
    }

    // MARK: - Gapless chain promotion decision

    private func makeCueTrack(_ title: String, url: URL, start: TimeInterval, end: TimeInterval?) -> Track {
        Track(url: url, title: title, artist: "A", album: "X",
              duration: (end ?? start + 10) - start, cueStart: start, cueEnd: end)
    }

    @Test func shouldPromoteChain_trueOnlyWhenEngineActuallyChained() {
        let url = URL(fileURLWithPath: "/tmp/album.flac")
        let a = makeCueTrack("A", url: url, start: 0, end: 30)
        let b = makeCueTrack("B", url: url, start: 30, end: 60)
        #expect(PlaylistManager.shouldPromoteChain(prev: a, next: b, engineChained: true))
        // After a seek the engine dropped the queued segment — promotion would
        // silently skip track B's audio.
        #expect(!PlaylistManager.shouldPromoteChain(prev: a, next: b, engineChained: false))
    }

    @Test func shouldPromoteChain_requiresSameFileCueNeighbors() {
        let url = URL(fileURLWithPath: "/tmp/album.flac")
        let other = URL(fileURLWithPath: "/tmp/other.flac")
        let a = makeCueTrack("A", url: url, start: 0, end: 30)
        let b = makeCueTrack("B", url: other, start: 30, end: 60)
        let plain = makeTrack("plain")
        #expect(!PlaylistManager.shouldPromoteChain(prev: a, next: b, engineChained: true))
        #expect(!PlaylistManager.shouldPromoteChain(prev: a, next: plain, engineChained: true))
        #expect(!PlaylistManager.shouldPromoteChain(prev: nil, next: b, engineChained: true))
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

    // MARK: - M3U import

    @Test func addM3U_countsPresentAndMissing() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wavURL = try makeSilentWav(in: dir, name: "one.wav")
        _ = try makeSilentWav(in: dir, name: "two.wav")

        let m3uURL = dir.appendingPathComponent("list.m3u8")
        try """
        #EXTM3U
        #EXTINF:1,One
        one.wav
        #EXTINF:1,Two
        two.wav
        #EXTINF:1,Ghost
        missing.wav
        """.write(to: m3uURL, atomically: true, encoding: .utf8)

        let pm = PlaylistManager()
        let summary = try await pm.addM3U(url: m3uURL)
        #expect(summary.imported == 2)
        #expect(summary.missing == 1)
        #expect(pm.tracks.count == 2)
        #expect(pm.tracks.contains { $0.url.path == wavURL.path })
    }

    @Test func addM3U_appendsRatherThanReplaces() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try makeSilentWav(in: dir, name: "new.wav")

        let m3uURL = dir.appendingPathComponent("list.m3u8")
        try "new.wav\n".write(to: m3uURL, atomically: true, encoding: .utf8)

        let pm = PlaylistManager()
        pm.addTracks([makeTrack("existing")])
        _ = try await pm.addM3U(url: m3uURL)
        #expect(pm.tracks.count == 2)
        #expect(pm.tracks[0].title == "existing")
    }

    // MARK: - Music library import

    @Test func importMusicLibrary_skipsStreamingOnlyAndMissingFiles() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let realA = try makeSilentWav(in: dir, name: "a.wav")
        let realB = try makeSilentWav(in: dir, name: "b.wav")

        let sources: [ITunesTrack] = [
            ITunesTrack(trackID: 1, name: "A", artist: "X", album: "Z",
                        genre: "", duration: 5, location: realA),
            ITunesTrack(trackID: 2, name: "B", artist: "Y", album: "Z",
                        genre: "", duration: 6, location: realB),
            ITunesTrack(trackID: 3, name: "Cloud", artist: "?", album: "?",
                        genre: "", duration: 10, location: nil),
            ITunesTrack(trackID: 4, name: "Ghost", artist: "?", album: "?",
                        genre: "", duration: 10,
                        location: dir.appendingPathComponent("nope.wav")),
        ]
        let pm = PlaylistManager()
        let summary = pm.importMusicLibraryTracks(sources, replaceCurrent: false)
        #expect(summary.imported == 2)
        #expect(summary.skippedStreamingOnly == 1)
        #expect(summary.skippedMissing == 1)
        #expect(pm.tracks.count == 2)
        #expect(pm.tracks.contains { $0.url.path == realA.path })
        #expect(pm.tracks.contains { $0.url.path == realB.path })
    }

    @Test func importMusicLibrary_replaceCurrentClearsFirst() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = try makeSilentWav(in: dir, name: "new.wav")

        let pm = PlaylistManager()
        pm.addTracks([makeTrack("stale")])
        let sources: [ITunesTrack] = [
            ITunesTrack(trackID: 1, name: "N", artist: "", album: "",
                        genre: "", duration: 1, location: real)
        ]
        _ = pm.importMusicLibraryTracks(sources, replaceCurrent: true)
        #expect(pm.tracks.count == 1)
        #expect(pm.tracks[0].title == "N")
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
