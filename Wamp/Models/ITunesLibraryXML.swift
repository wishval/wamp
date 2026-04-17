import Foundation

/// Representation of a user's `iTunes Music Library.xml` export from macOS Music.app.
/// Only the fields Wamp needs for local import are parsed.
struct ITunesLibrary: Equatable {
    let tracks: [Int: ITunesTrack]
    let playlists: [ITunesPlaylist]
}

struct ITunesTrack: Equatable {
    let trackID: Int
    let name: String
    let artist: String
    let album: String
    let genre: String
    let duration: TimeInterval   // seconds
    let location: URL?           // absolute file URL, or nil for streaming-only tracks

    var isStreamingOnly: Bool { location == nil }
}

struct ITunesPlaylist: Equatable {
    let id: Int
    let name: String
    let isSmart: Bool
    let isBuiltIn: Bool
    let trackIDs: [Int]
}

enum ITunesLibraryParseError: Error {
    case notAPropertyList
    case wrongSchema
}

enum ITunesLibraryXMLParser {
    static func parse(url: URL) throws -> ITunesLibrary {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ITunesLibrary {
        let raw: Any
        do {
            raw = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            )
        } catch {
            throw ITunesLibraryParseError.notAPropertyList
        }
        guard let root = raw as? [String: Any] else {
            throw ITunesLibraryParseError.wrongSchema
        }

        let tracksDict = (root["Tracks"] as? [String: Any]) ?? [:]
        var tracks: [Int: ITunesTrack] = [:]
        tracks.reserveCapacity(tracksDict.count)
        for (_, value) in tracksDict {
            guard let dict = value as? [String: Any],
                  let track = parseTrack(dict) else { continue }
            tracks[track.trackID] = track
        }

        let playlistsArray = (root["Playlists"] as? [[String: Any]]) ?? []
        var playlists: [ITunesPlaylist] = []
        playlists.reserveCapacity(playlistsArray.count)
        for dict in playlistsArray {
            if let p = parsePlaylist(dict) {
                playlists.append(p)
            }
        }

        return ITunesLibrary(tracks: tracks, playlists: playlists)
    }

    // MARK: - Track

    private static func parseTrack(_ dict: [String: Any]) -> ITunesTrack? {
        guard let trackID = intValue(dict["Track ID"]) else { return nil }

        let location = (dict["Location"] as? String).flatMap(URL.init(string:))

        let filenameFallback = location?.deletingPathExtension().lastPathComponent ?? ""
        let name: String
        if let n = dict["Name"] as? String, !n.isEmpty {
            name = n
        } else if !filenameFallback.isEmpty {
            name = filenameFallback
        } else {
            name = "Untitled"
        }

        let totalTimeMs = intValue(dict["Total Time"]) ?? 0
        return ITunesTrack(
            trackID: trackID,
            name: name,
            artist: (dict["Artist"] as? String) ?? "",
            album: (dict["Album"] as? String) ?? "",
            genre: (dict["Genre"] as? String) ?? "",
            duration: TimeInterval(totalTimeMs) / 1000.0,
            location: location
        )
    }

    // MARK: - Playlist

    private static func parsePlaylist(_ dict: [String: Any]) -> ITunesPlaylist? {
        guard let id = intValue(dict["Playlist ID"]),
              let name = dict["Name"] as? String else { return nil }

        let isSmart = dict["Smart Info"] != nil || dict["Smart Criteria"] != nil
        let master = (dict["Master"] as? Bool) ?? false
        let distinguished = intValue(dict["Distinguished Kind"]) != nil
        let isBuiltIn = master || distinguished

        var trackIDs: [Int] = []
        if let items = dict["Playlist Items"] as? [[String: Any]] {
            trackIDs.reserveCapacity(items.count)
            for item in items {
                if let tid = intValue(item["Track ID"]) {
                    trackIDs.append(tid)
                }
            }
        }

        return ITunesPlaylist(
            id: id, name: name,
            isSmart: isSmart, isBuiltIn: isBuiltIn,
            trackIDs: trackIDs
        )
    }

    /// Plist integer fields are usually NSNumber (bridged Int); accept both.
    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}
