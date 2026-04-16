import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("JumpToFile playback integration")
struct JumpToFilePlaybackTests {

    private func track(_ title: String, artist: String = "A") -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/\(title).m4a"),
            title: title,
            artist: artist,
            album: "",
            duration: 1
        )
    }

    /// Build the same Candidate list that AppDelegate.jumpCandidates produces.
    private func candidates(from pm: PlaylistManager) -> [JumpFilter.Candidate] {
        pm.tracks.enumerated().map { idx, t in
            JumpFilter.Candidate(
                index: idx,
                displayTitle: t.displayTitle,
                filename: t.url.lastPathComponent
            )
        }
    }

    @Test func filterAndPlay_setsCurrentIndexToMatchedTrack() {
        let pm = PlaylistManager()
        pm.addTracks([
            track("Money", artist: "Pink Floyd"),
            track("Bohemian Rhapsody", artist: "Queen"),
            track("Around the World", artist: "Daft Punk"),
        ])
        let cs = candidates(from: pm)
        let matches = JumpFilter.filter(query: "queen", candidates: cs)
        #expect(matches.count == 1)
        #expect(matches[0].index == 1)
        // Simulate the dialog calling playTrack(at:) with the top match.
        // PlaylistManager's audioEngine is nil in tests; playTrack uses
        // optional chaining and will safely no-op the load call.
        pm.playTrack(at: matches[0].index)
        #expect(pm.currentIndex == 1)
        #expect(pm.currentTrack?.title == "Bohemian Rhapsody")
    }

    @Test func filterEmpty_returnsAllTracks() {
        let pm = PlaylistManager()
        pm.addTracks([track("a"), track("b"), track("c")])
        let cs = candidates(from: pm)
        let matches = JumpFilter.filter(query: "", candidates: cs)
        #expect(matches.count == 3)
    }
}
