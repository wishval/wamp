import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("StateManager")
struct StateManagerTests {

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WampTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func appState_roundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        var state = AppState()
        state.volume = 0.42
        state.balance = -0.25
        state.repeatMode = 2
        state.eqEnabled = false
        state.showEqualizer = false
        state.showPlaylist = true
        state.windowX = 300
        state.windowY = 420
        state.alwaysOnTop = false
        state.lastTrackIndex = 7
        state.lastPlaybackPosition = 123.5
        state.skinPath = "/tmp/some-skin"

        StateManager(directory: dir).saveAppState(state)
        let loaded = StateManager(directory: dir).loadAppState()

        #expect(loaded.volume == 0.42)
        #expect(loaded.balance == -0.25)
        #expect(loaded.repeatMode == 2)
        #expect(loaded.eqEnabled == false)
        #expect(loaded.showEqualizer == false)
        #expect(loaded.showPlaylist == true)
        #expect(loaded.windowX == 300)
        #expect(loaded.windowY == 420)
        #expect(loaded.alwaysOnTop == false)
        #expect(loaded.lastTrackIndex == 7)
        #expect(loaded.lastPlaybackPosition == 123.5)
        #expect(loaded.skinPath == "/tmp/some-skin")
    }

    @Test func loadAppState_missingFile_returnsDefaults() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let loaded = StateManager(directory: dir).loadAppState()
        #expect(loaded.volume == 0.75)
        #expect(loaded.lastTrackIndex == -1)
    }

    @Test func loadAppState_corruptFile_returnsDefaults() throws {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let corrupt = dir.appendingPathComponent("state.json")
        try "not valid json".write(to: corrupt, atomically: true, encoding: .utf8)

        let loaded = StateManager(directory: dir).loadAppState()
        #expect(loaded.volume == 0.75)
    }

    @Test func eqState_roundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let eq = EQState(
            bands: [-6, -3, 0, 3, 6, 6, 3, 0, -3, -6],
            preampGain: 4.5,
            presetName: "Rock",
            autoMode: true
        )
        StateManager(directory: dir).saveEQState(eq)

        let loaded = StateManager(directory: dir).loadEQState()
        #expect(loaded.bands == [-6, -3, 0, 3, 6, 6, 3, 0, -3, -6])
        #expect(loaded.preampGain == 4.5)
        #expect(loaded.presetName == "Rock")
        #expect(loaded.autoMode == true)
    }

    @Test func loadEQState_missingFile_returnsDefaults() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let loaded = StateManager(directory: dir).loadEQState()
        #expect(loaded.bands == Array(repeating: Float(0), count: 10))
        #expect(loaded.preampGain == 0)
        #expect(loaded.presetName == "Flat")
    }

    @Test func saveAndLoadPlaylist_roundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let sm = StateManager(directory: dir)
        let pm = PlaylistManager()
        pm.addTracks([
            Track(url: URL(fileURLWithPath: "/tmp/one.m4a"), title: "One", artist: "A", album: "X", duration: 10),
            Track(url: URL(fileURLWithPath: "/tmp/two.m4a"), title: "Two", artist: "B", album: "Y", duration: 20),
        ])
        sm.savePlaylist(playlistManager: pm)

        let loaded = sm.loadSavedPlaylist()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.title) == ["One", "Two"])
        #expect(loaded.map(\.duration) == [10, 20])
    }
}
