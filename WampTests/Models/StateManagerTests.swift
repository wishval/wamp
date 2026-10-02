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

    @Test func appState_autoPlay_defaultsOnAndRoundTrips() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        #expect(AppState().autoPlay == true)
        var state = AppState()
        state.autoPlay = false
        StateManager(directory: dir).saveAppState(state)
        #expect(StateManager(directory: dir).loadAppState().autoPlay == false)
    }

    @Test func loadAppState_legacyFileMissingNewKeys_keepsSavedFields() throws {
        // A state.json written before a field existed must not decode-fail
        // into all-defaults (wiping volume, window position, skin…).
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let legacy = """
        {"volume":0.3,"balance":0,"repeatMode":1,"eqEnabled":true,
         "showEqualizer":false,"showPlaylist":true,"windowX":250,"windowY":90,
         "alwaysOnTop":true,"lastTrackIndex":4,"lastPlaybackPosition":0,
         "skinPath":"/tmp/legacy.wsz"}
        """
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("state.json"))

        let loaded = StateManager(directory: dir).loadAppState()
        #expect(loaded.volume == 0.3)
        #expect(loaded.repeatMode == 1)
        #expect(loaded.windowX == 250)
        #expect(loaded.alwaysOnTop == true)
        #expect(loaded.skinPath == "/tmp/legacy.wsz")
        #expect(loaded.autoPlay == true)
    }

    @Test func saveState_preservesFieldsItDoesNotManage() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let sm = StateManager(directory: dir)
        var prior = AppState()
        prior.skinPath = "/tmp/cool-skin.wsz"
        prior.windowX = 333
        prior.windowY = 444
        prior.alwaysOnTop = true
        prior.showEqualizer = false
        sm.saveAppState(prior)

        // A debounced save (volume change etc.) must not wipe skin/window state.
        sm.saveState(audioEngine: AudioEngine(), playlistManager: PlaylistManager())

        let loaded = sm.loadAppState()
        #expect(loaded.skinPath == "/tmp/cool-skin.wsz")
        #expect(loaded.windowX == 333)
        #expect(loaded.windowY == 444)
        #expect(loaded.alwaysOnTop == true)
        #expect(loaded.showEqualizer == false)
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
