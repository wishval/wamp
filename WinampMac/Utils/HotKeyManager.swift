import Foundation
import MediaPlayer

class HotKeyManager {
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?

    init(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager
        setupRemoteCommands()
        setupNowPlayingUpdates()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.audioEngine?.play()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.audioEngine?.pause()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.audioEngine?.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playlistManager?.playNext()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playlistManager?.playPrevious()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.audioEngine?.seek(to: posEvent.positionTime)
            return .success
        }
    }

    private func setupNowPlayingUpdates() {
        // Update periodically
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNowPlaying()
        }
    }

    func updateNowPlaying() {
        guard let engine = audioEngine,
              let track = playlistManager?.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: engine.isPlaying ? 1.0 : 0.0
        ]

        if !track.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = track.album
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
