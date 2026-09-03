import Foundation
import Combine

/// Owns the Navidrome connection for the app: the saved credentials, the
/// API client built from them, and the stream cache. `AppDelegate` plugs
/// `resolve`/`prefetch` into `PlaylistManager` so remote tracks play through
/// the normal `AudioEngine` path.
@MainActor
final class NavidromeService: ObservableObject {
    @Published private(set) var credentials: SubsonicCredentials?
    @Published private(set) var client: SubsonicClient?

    let cache: StreamCache
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    var isConfigured: Bool { client != nil }

    init(cache: StreamCache = StreamCache()) {
        self.cache = cache
        if let saved = NavidromeAccountStore.load() {
            apply(saved)
        }
    }

    // MARK: - Account

    /// Persist and activate new credentials. Callers should `ping` first via
    /// a throwaway `SubsonicClient` so bad logins never get saved.
    func connect(_ credentials: SubsonicCredentials) {
        NavidromeAccountStore.save(credentials)
        apply(credentials)
    }

    func disconnect() {
        NavidromeAccountStore.clear()
        credentials = nil
        client = nil
        for task in prefetchTasks.values { task.cancel() }
        prefetchTasks.removeAll()
        lyricsCache.removeAll()
    }

    private func apply(_ credentials: SubsonicCredentials) {
        self.credentials = credentials
        self.client = SubsonicClient(credentials: credentials)
    }

    // MARK: - Track conversion

    /// Wamp `Track` for a server song. `url` is `navidrome://host/<library
    /// path>` — descriptive, not fetchable; see `Track.remoteID`.
    func makeTrack(_ song: SubsonicSong) -> Track {
        let host = credentials?.displayHost ?? "navidrome"
        return Track.fromSubsonicSong(song, host: host)
    }

    // MARK: - Lyrics

    private var lyricsCache: [String: SubsonicLyrics?] = [:]

    /// Lyrics for any track. Remote tracks use the OpenSubsonic song-id
    /// lookup (synced when the file has LRC/SYLT data); local tracks fall
    /// back to the artist/title lookup. Nil when the server has none.
    /// Results are memoised per track for the app's lifetime.
    func lyrics(for track: Track) async throws -> SubsonicLyrics? {
        guard let client else { throw SubsonicError.notConfigured }
        let key = track.remoteID ?? "local|\(track.artist)|\(track.title)"
        if let cached = lyricsCache[key] { return cached }
        let result: SubsonicLyrics?
        if let id = track.remoteID {
            result = LyricsSync.preferred(try await client.lyrics(songID: id))
        } else if let text = try await client.lyrics(artist: track.artist, title: track.title) {
            result = SubsonicLyrics(
                displayArtist: track.artist, displayTitle: track.title, lang: nil, synced: false,
                line: text.components(separatedBy: .newlines).map { SubsonicLyricsLine(start: nil, value: $0) }
            )
        } else {
            result = nil
        }
        lyricsCache[key] = result
        return result
    }

    // MARK: - Playback resolution

    /// Extension the cached file gets. Formats AVFoundation can't decode
    /// (ogg, opus, wma …) are transcoded server-side to MP3.
    nonisolated static func cacheExtension(forSuffix suffix: String?) -> String {
        let ext = (suffix ?? "").lowercased()
        return Track.supportedExtensions.contains(ext) ? ext : "mp3"
    }

    private func streamRequest(for track: Track) throws -> (id: String, ext: String, url: URL) {
        guard let client else { throw SubsonicError.notConfigured }
        guard let id = track.remoteID else { throw SubsonicError.malformedResponse }
        let suffix = track.url.pathExtension
        let ext = Self.cacheExtension(forSuffix: suffix)
        let transcode = ext != suffix.lowercased()
        let url = client.streamURL(id: id, format: transcode ? "mp3" : nil, maxBitRate: transcode ? 320 : nil)
        return (id, ext, url)
    }

    /// Local file for `track`, downloading on a miss. Used as
    /// `PlaylistManager.remoteTrackResolver`.
    func resolve(_ track: Track) async throws -> URL {
        let req = try streamRequest(for: track)
        let url = try await cache.localURL(id: req.id, ext: req.ext, remote: req.url)
        // Fire-and-forget: play counts are a nicety, never a playback blocker.
        Task.detached { [client] in try? await client?.scrobble(id: req.id) }
        return url
    }

    /// Already-downloaded file for `track`, if any. Used at launch to
    /// re-arm the engine on a restored remote track without hitting the network.
    func cachedURL(for track: Track) -> URL? {
        guard let id = track.remoteID else { return nil }
        return cache.cachedURL(id: id, ext: Self.cacheExtension(forSuffix: track.url.pathExtension))
    }

    /// Warm the cache for the next track. Used as `PlaylistManager.remoteTrackPrefetch`.
    func prefetch(_ track: Track) {
        guard let req = try? streamRequest(for: track), prefetchTasks[req.id] == nil else { return }
        prefetchTasks[req.id] = Task { [cache] in
            _ = try? await cache.localURL(id: req.id, ext: req.ext, remote: req.url)
            await MainActor.run { self.prefetchTasks[req.id] = nil }
        }
    }
}

extension Track {
    /// Build a remote track from a Subsonic song. `host` becomes the URL
    /// authority so playlists saved against different servers stay distinct.
    static func fromSubsonicSong(_ song: SubsonicSong, host: String) -> Track {
        var components = URLComponents()
        components.scheme = "navidrome"
        // Host may carry a port ("host:4533"); URLComponents wants them split.
        let parts = host.split(separator: ":", maxSplits: 1).map(String.init)
        components.host = parts.first ?? host
        if parts.count == 2, let port = Int(parts[1]) { components.port = port }
        let suffix = song.suffix ?? "mp3"
        let path = song.path ?? "\(song.id).\(suffix)"
        components.path = "/" + path
        let url = components.url ?? URL(string: "navidrome://\(song.id)")!

        let artist = (song.artist ?? "").isEmpty ? "Unknown Artist" : song.artist!
        return Track(
            url: url,
            title: song.title,
            artist: artist,
            album: song.album ?? "",
            duration: song.duration ?? 0,
            genre: song.genre ?? "",
            bitrate: song.bitRate ?? 0,
            sampleRate: song.samplingRate ?? 0,
            channels: song.channelCount ?? 2,
            remoteID: song.id
        )
    }
}
