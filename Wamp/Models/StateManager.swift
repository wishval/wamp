import Foundation
import Combine

struct AppState: Codable {
    var volume: Float = 0.75
    var balance: Float = 0
    var repeatMode: Int = 0 // RepeatMode raw value
    var eqEnabled: Bool = true
    var showEqualizer: Bool = true
    var showPlaylist: Bool = true
    var windowX: Double = 100
    var windowY: Double = 100
    var alwaysOnTop: Bool = false
    var lastTrackIndex: Int = -1
    var lastPlaybackPosition: Double = 0
    var skinPath: String?
    /// Main-window visualizer: 0 = spectrum analyzer, 1 = oscilloscope, 2 = off.
    var visualizerMode: Int = 0

    init() {}

    /// Lenient decoding: every key is optional and falls back to the default
    /// above. Synthesized Decodable would reject a state.json written by an
    /// older build the moment a new field is added — silently resetting the
    /// user's volume, window position and skin on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        balance = try c.decodeIfPresent(Float.self, forKey: .balance) ?? balance
        repeatMode = try c.decodeIfPresent(Int.self, forKey: .repeatMode) ?? repeatMode
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? eqEnabled
        showEqualizer = try c.decodeIfPresent(Bool.self, forKey: .showEqualizer) ?? showEqualizer
        showPlaylist = try c.decodeIfPresent(Bool.self, forKey: .showPlaylist) ?? showPlaylist
        windowX = try c.decodeIfPresent(Double.self, forKey: .windowX) ?? windowX
        windowY = try c.decodeIfPresent(Double.self, forKey: .windowY) ?? windowY
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? alwaysOnTop
        lastTrackIndex = try c.decodeIfPresent(Int.self, forKey: .lastTrackIndex) ?? lastTrackIndex
        lastPlaybackPosition = try c.decodeIfPresent(Double.self, forKey: .lastPlaybackPosition) ?? lastPlaybackPosition
        skinPath = try c.decodeIfPresent(String.self, forKey: .skinPath)
        visualizerMode = try c.decodeIfPresent(Int.self, forKey: .visualizerMode) ?? visualizerMode
    }
}

struct EQState: Codable {
    var bands: [Float] = Array(repeating: 0, count: 10)
    var preampGain: Float = 0
    var presetName: String = "Flat"
    var autoMode: Bool = false
}

class StateManager {
    private let appSupportDir: URL
    private var cancellables = Set<AnyCancellable>()
    private var saveWorkItem: DispatchWorkItem?

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Wamp")
    }

    init(directory: URL = StateManager.defaultDirectory) {
        appSupportDir = directory
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    var playlistsDirectory: URL {
        let dir = appSupportDir.appendingPathComponent("playlists")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Subscribe to Changes
    func observe(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        audioEngine.$volume
            .merge(with: audioEngine.$balance.map { _ in audioEngine.volume })
            .merge(with: audioEngine.$repeatMode.map { _ in audioEngine.volume })
            .merge(with: audioEngine.$eqEnabled.map { _ in audioEngine.volume })
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveState(audioEngine: audioEngine, playlistManager: playlistManager) }
            .store(in: &cancellables)

        playlistManager.$tracks
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.savePlaylist(playlistManager: playlistManager) }
            .store(in: &cancellables)

    }

    // MARK: - Save
    func saveState(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        // Start from the persisted state so fields managed elsewhere
        // (skinPath, window position, panel visibility) survive debounced saves.
        var state = loadAppState()
        state.volume = audioEngine.volume
        state.balance = audioEngine.balance
        state.repeatMode = audioEngine.repeatMode.rawValue

        state.eqEnabled = audioEngine.eqEnabled
        state.lastTrackIndex = playlistManager.currentIndex
        state.lastPlaybackPosition = audioEngine.currentTime
        write(state, to: "state.json")
    }

    func saveEQState(audioEngine: AudioEngine, presetName: String = "Custom", autoMode: Bool = false) {
        let eqState = EQState(
            bands: audioEngine.eqBands,
            preampGain: audioEngine.preampGain,
            presetName: presetName,
            autoMode: autoMode
        )
        write(eqState, to: "equalizer.json")
    }

    func saveEQState(_ state: EQState) {
        write(state, to: "equalizer.json")
    }

    func savePlaylist(playlistManager: PlaylistManager) {
        let trackData = playlistManager.tracks.map { $0 }
        write(trackData, to: "playlist.json")
    }

    func saveWindowState(x: Double, y: Double, showEQ: Bool, showPlaylist: Bool, alwaysOnTop: Bool, audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        var state = loadAppState()
        state.windowX = x
        state.windowY = y
        state.showEqualizer = showEQ
        state.showPlaylist = showPlaylist
        state.alwaysOnTop = alwaysOnTop
        state.volume = audioEngine.volume
        state.balance = audioEngine.balance
        state.repeatMode = audioEngine.repeatMode.rawValue

        state.eqEnabled = audioEngine.eqEnabled
        state.lastTrackIndex = playlistManager.currentIndex
        state.lastPlaybackPosition = audioEngine.currentTime
        write(state, to: "state.json")
    }

    func saveAppState(_ state: AppState) {
        write(state, to: "state.json")
    }

    // MARK: - Load
    func loadAppState() -> AppState {
        read("state.json") ?? AppState()
    }

    func loadEQState() -> EQState {
        read("equalizer.json") ?? EQState()
    }

    func loadSavedPlaylist() -> [Track] {
        read("playlist.json") ?? []
    }

    // MARK: - Private I/O
    private func write<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportDir.appendingPathComponent(filename)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("StateManager: failed to write \(filename): \(error)")
        }
    }

    private func read<T: Decodable>(_ filename: String) -> T? {
        let url = appSupportDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
