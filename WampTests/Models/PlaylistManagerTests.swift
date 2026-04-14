import Testing
import Foundation
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
}
