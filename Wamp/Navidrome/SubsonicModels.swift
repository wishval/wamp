import Foundation

// Decodable views of the Subsonic API (v1.16.1) JSON responses as served by
// Navidrome. Only the fields Wamp needs are declared; everything else in the
// payload is ignored. All optionals default to sensible empties via the
// convenience accessors so the UI never has to nil-check display strings.

struct SubsonicSong: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let album: String?
    let artist: String?
    let albumId: String?
    let artistId: String?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let suffix: String?
    let contentType: String?
    let duration: Double?
    let bitRate: Int?
    let samplingRate: Int?
    let channelCount: Int?
    let size: Int64?
    let path: String?
}

struct SubsonicAlbum: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let year: Int?
    let genre: String?
    let songCount: Int?
    let duration: Double?
    /// Populated only by `getAlbum`.
    let song: [SubsonicSong]?
}

struct SubsonicArtist: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let albumCount: Int?
    /// Populated only by `getArtist`.
    let album: [SubsonicAlbum]?
}

struct SubsonicArtistIndex: Decodable, Equatable, Sendable {
    let name: String
    let artist: [SubsonicArtist]?
}

struct SubsonicPlaylist: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let owner: String?
    let songCount: Int?
    let duration: Double?
    /// Populated only by `getPlaylist`.
    let entry: [SubsonicSong]?
}

struct SubsonicSearchResult: Decodable, Equatable, Sendable {
    let artist: [SubsonicArtist]?
    let album: [SubsonicAlbum]?
    let song: [SubsonicSong]?
}

struct SubsonicStarred: Decodable, Equatable, Sendable {
    let artist: [SubsonicArtist]?
    let album: [SubsonicAlbum]?
    let song: [SubsonicSong]?
}

// MARK: - Envelope

enum SubsonicError: LocalizedError, Equatable {
    /// The server answered with `status: failed`. Code 40 = bad credentials,
    /// 70 = not found, 10 = missing parameter, 0 = generic.
    case server(code: Int, message: String)
    case malformedResponse
    case httpStatus(Int)
    case notAudio(contentType: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .server(let code, let message):
            switch code {
            case 40: return "Wrong username or password."
            case 70: return "Not found on the server."
            default: return message.isEmpty ? "Server error \(code)." : message
            }
        case .malformedResponse:
            return "The server sent a response Wamp couldn't understand. Is this a Subsonic/Navidrome server?"
        case .httpStatus(let status):
            return "The server answered with HTTP \(status)."
        case .notAudio(let contentType):
            return "The server sent \(contentType) instead of audio."
        case .notConfigured:
            return "Not connected to a Navidrome server."
        }
    }
}

enum SubsonicResponseParser {
    /// Unwraps the `subsonic-response` envelope, surfaces a server-side
    /// `error` as `SubsonicError.server`, and decodes the payload under `key`.
    /// Pass `key: nil` to only validate (e.g. `ping`).
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, key: String) throws -> T {
        let envelope = try validated(data)
        guard let payload = envelope[key] else {
            // A legitimately empty list (e.g. getPlaylists with no playlists)
            // arrives as an absent key on some servers. Model it as {}.
            let empty = try JSONSerialization.data(withJSONObject: [String: Any]())
            return try JSONDecoder().decode(T.self, from: empty)
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(T.self, from: payloadData)
    }

    /// Validates the envelope only. Throws for non-JSON bodies and for
    /// `status: failed`. Returns the inner `subsonic-response` object.
    @discardableResult
    static func validated(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["subsonic-response"] as? [String: Any],
              let status = response["status"] as? String else {
            throw SubsonicError.malformedResponse
        }
        if status != "ok" {
            let err = response["error"] as? [String: Any]
            throw SubsonicError.server(
                code: err?["code"] as? Int ?? 0,
                message: err?["message"] as? String ?? ""
            )
        }
        return response
    }
}

// MARK: - Lyrics (OpenSubsonic `songLyrics` extension)

struct SubsonicLyricsLine: Decodable, Equatable, Sendable {
    /// Offset from the start of the song in milliseconds; nil for unsynced text.
    let start: Int?
    let value: String
}

struct SubsonicLyrics: Decodable, Equatable, Sendable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String?
    let synced: Bool?
    let line: [SubsonicLyricsLine]?

    var lines: [SubsonicLyricsLine] { line ?? [] }
    /// Navidrome sets `synced`, but be defensive: treat lyrics as synced only
    /// when every line actually carries a timestamp.
    var isSynced: Bool {
        guard !lines.isEmpty else { return false }
        return (synced ?? true) && lines.allSatisfy { $0.start != nil }
    }
    var plainText: String { lines.map(\.value).joined(separator: "\n") }
}

struct SubsonicLyricsList: Decodable, Equatable, Sendable {
    let structuredLyrics: [SubsonicLyrics]?
}
