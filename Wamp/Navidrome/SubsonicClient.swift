import Foundation
import CryptoKit

/// Credentials for one Subsonic-compatible server (Navidrome, Airsonic,
/// Gonic …). Auth uses the salted-token scheme from API 1.13+:
/// `t = md5(password + salt)`, so the password itself never goes on the wire.
struct SubsonicCredentials: Equatable, Sendable {
    let serverURL: URL
    let username: String
    let password: String

    static let apiVersion = "1.16.1"
    static let clientName = "wamp"

    /// `md5(password + salt)` as lowercase hex — the Subsonic `t` parameter.
    static func token(password: String, salt: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func makeSalt() -> String {
        let bytes = (0..<8).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The common auth/format query items every request carries.
    func authQueryItems(salt: String = SubsonicCredentials.makeSalt()) -> [URLQueryItem] {
        [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: Self.token(password: password, salt: salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
    }

    /// Builds `<server>/rest/<method>?<auth>&<params>`.
    func endpoint(_ method: String, params: [URLQueryItem] = [], salt: String = SubsonicCredentials.makeSalt()) -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/rest/" + method
        components.queryItems = authQueryItems(salt: salt) + params
        return components.url!
    }

    /// Host shown in UIs and used in `navidrome://host/...` track URLs.
    var displayHost: String {
        let host = serverURL.host ?? serverURL.absoluteString
        if let port = serverURL.port { return "\(host):\(port)" }
        return host
    }
}

/// Thin async client over the Subsonic REST API. Every method is a single
/// GET; parsing goes through `SubsonicResponseParser` so server errors
/// surface as `SubsonicError.server`.
struct SubsonicClient: Sendable {
    let credentials: SubsonicCredentials
    let session: URLSession

    init(credentials: SubsonicCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    enum AlbumListType: String, Sendable {
        case newest, random, frequent, recent, starred
        case alphabeticalByName, alphabeticalByArtist
    }

    // MARK: - Endpoints

    func ping() async throws {
        let data = try await get("ping")
        try SubsonicResponseParser.validated(data)
    }

    /// All artists (ID3 view), flattened out of the alphabetical index.
    func artists() async throws -> [SubsonicArtist] {
        struct Payload: Decodable { let index: [SubsonicArtistIndex]? }
        let data = try await get("getArtists")
        let payload = try SubsonicResponseParser.decode(Payload.self, from: data, key: "artists")
        return (payload.index ?? []).flatMap { $0.artist ?? [] }
    }

    func artist(id: String) async throws -> SubsonicArtist {
        let data = try await get("getArtist", [URLQueryItem(name: "id", value: id)])
        return try SubsonicResponseParser.decode(SubsonicArtist.self, from: data, key: "artist")
    }

    func album(id: String) async throws -> SubsonicAlbum {
        let data = try await get("getAlbum", [URLQueryItem(name: "id", value: id)])
        return try SubsonicResponseParser.decode(SubsonicAlbum.self, from: data, key: "album")
    }

    func albumList(_ type: AlbumListType, size: Int = 50, offset: Int = 0) async throws -> [SubsonicAlbum] {
        struct Payload: Decodable { let album: [SubsonicAlbum]? }
        let data = try await get("getAlbumList2", [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try SubsonicResponseParser.decode(Payload.self, from: data, key: "albumList2").album ?? []
    }

    func randomSongs(size: Int = 50) async throws -> [SubsonicSong] {
        struct Payload: Decodable { let song: [SubsonicSong]? }
        let data = try await get("getRandomSongs", [URLQueryItem(name: "size", value: String(size))])
        return try SubsonicResponseParser.decode(Payload.self, from: data, key: "randomSongs").song ?? []
    }

    func search(_ query: String, artistCount: Int = 20, albumCount: Int = 40, songCount: Int = 200) async throws -> SubsonicSearchResult {
        let data = try await get("search3", [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: String(artistCount)),
            URLQueryItem(name: "albumCount", value: String(albumCount)),
            URLQueryItem(name: "songCount", value: String(songCount)),
        ])
        return try SubsonicResponseParser.decode(SubsonicSearchResult.self, from: data, key: "searchResult3")
    }

    func playlists() async throws -> [SubsonicPlaylist] {
        struct Payload: Decodable { let playlist: [SubsonicPlaylist]? }
        let data = try await get("getPlaylists")
        return try SubsonicResponseParser.decode(Payload.self, from: data, key: "playlists").playlist ?? []
    }

    func playlist(id: String) async throws -> SubsonicPlaylist {
        let data = try await get("getPlaylist", [URLQueryItem(name: "id", value: id)])
        return try SubsonicResponseParser.decode(SubsonicPlaylist.self, from: data, key: "playlist")
    }

    func starred() async throws -> SubsonicStarred {
        let data = try await get("getStarred2")
        return try SubsonicResponseParser.decode(SubsonicStarred.self, from: data, key: "starred2")
    }

    /// Tell the server a song was played (feeds Navidrome's play counts and
    /// "recently played"; also forwards to Last.fm/ListenBrainz if configured).
    func scrobble(id: String, submission: Bool = true) async throws {
        let data = try await get("scrobble", [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "submission", value: submission ? "true" : "false"),
        ])
        try SubsonicResponseParser.validated(data)
    }

    /// Lyrics blocks for a song (OpenSubsonic `getLyricsBySongId`). Empty
    /// when the server has none; throws only on transport/API failure.
    func lyrics(songID: String) async throws -> [SubsonicLyrics] {
        let data = try await get("getLyricsBySongId", [URLQueryItem(name: "id", value: songID)])
        return try SubsonicResponseParser.decode(SubsonicLyricsList.self, from: data, key: "lyricsList")
            .structuredLyrics ?? []
    }

    /// Legacy `getLyrics` lookup by artist/title — lets a connected server
    /// supply lyrics for *local* files too. Returns nil when there are none.
    func lyrics(artist: String, title: String) async throws -> String? {
        struct Payload: Decodable { let value: String?; let artist: String?; let title: String? }
        let data = try await get("getLyrics", [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "title", value: title),
        ])
        let text = try SubsonicResponseParser.decode(Payload.self, from: data, key: "lyrics").value ?? ""
        return text.isEmpty ? nil : text
    }

    /// URL that streams the song's bytes. `format: nil` asks for the original
    /// file (`format=raw`); pass e.g. `"mp3"` to have the server transcode.
    func streamURL(id: String, format: String? = nil, maxBitRate: Int? = nil) -> URL {
        var params = [URLQueryItem(name: "id", value: id)]
        params.append(URLQueryItem(name: "format", value: format ?? "raw"))
        if let maxBitRate { params.append(URLQueryItem(name: "maxBitRate", value: String(maxBitRate))) }
        return credentials.endpoint("stream", params: params)
    }

    // MARK: - Transport

    private func get(_ method: String, _ params: [URLQueryItem] = []) async throws -> Data {
        let url = credentials.endpoint(method, params: params)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Subsonic servers return 200 + JSON error for API failures, so a
            // non-2xx here means we're not talking to the API at all.
            throw SubsonicError.httpStatus(http.statusCode)
        }
        return data
    }
}
