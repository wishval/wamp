import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("Persistence round-trip")
struct PersistenceRoundTripTests {

    @Test func fullSessionRestoresAfterReload() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WampRoundTrip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Session A — populate and persist.
        let pmA = PlaylistManager()
        pmA.addTracks([
            Track(url: URL(fileURLWithPath: "/tmp/song1.m4a"), title: "Song 1", artist: "Band", album: "Alb", duration: 180),
            Track(url: URL(fileURLWithPath: "/tmp/song2.m4a"), title: "Song 2", artist: "Band", album: "Alb", duration: 240),
        ])
        pmA.currentIndex = 1

        var appState = AppState()
        appState.volume = 0.3
        appState.repeatMode = 1
        appState.lastTrackIndex = pmA.currentIndex
        appState.lastPlaybackPosition = 42

        let eqState = EQState(
            bands: [1, 2, 3, 4, 5, -5, -4, -3, -2, -1],
            preampGain: 2.0,
            presetName: "Custom",
            autoMode: false
        )

        let smA = StateManager(directory: dir)
        smA.saveAppState(appState)
        smA.saveEQState(eqState)
        smA.savePlaylist(playlistManager: pmA)

        // Session B — fresh StateManager against the same directory.
        let smB = StateManager(directory: dir)
        let loadedApp = smB.loadAppState()
        let loadedEQ = smB.loadEQState()
        let loadedTracks = smB.loadSavedPlaylist()

        #expect(loadedApp.volume == 0.3)
        #expect(loadedApp.repeatMode == 1)
        #expect(loadedApp.lastTrackIndex == 1)
        #expect(loadedApp.lastPlaybackPosition == 42)

        #expect(loadedEQ.bands == [1, 2, 3, 4, 5, -5, -4, -3, -2, -1])
        #expect(loadedEQ.preampGain == 2.0)
        #expect(loadedEQ.presetName == "Custom")

        #expect(loadedTracks.count == 2)
        #expect(loadedTracks.map(\.title) == ["Song 1", "Song 2"])
        #expect(loadedTracks[1].duration == 240)
    }
}
