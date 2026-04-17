import Foundation
import iTunesLibrary

/// Errors thrown by `AppleMusicLibrarySource`. Conforms to `LocalizedError`
/// so the UI can present `error.localizedDescription` directly.
enum AppleMusicLibraryError: LocalizedError {
    /// `ITLibrary` init failed. Typically this means the user denied access
    /// in the TCC prompt, but macOS doesn't expose a dedicated authorization
    /// API for iTunesLibrary (unlike Photos or Contacts), so we treat any
    /// init failure as "couldn't read" and surface the underlying reason.
    case cannotRead(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let err):
            return "Wamp couldn't read your Music library: \(err.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cannotRead:
            return "If you denied permission earlier, open System Settings → Privacy & Security → Media & Apple Music and enable Wamp."
        }
    }

    /// Whether the UI should offer an "Open System Settings" button.
    var canOpenSystemSettings: Bool {
        switch self {
        case .cannotRead: return true
        }
    }
}

/// Loads the user's Music.app library via the `iTunesLibrary` framework.
/// This is the preferred backend on macOS — it reads the live `.musiclibrary`
/// bundle, so no XML export needs to be enabled. Permission is handled by
/// macOS TCC automatically based on `NSAppleMusicUsageDescription`.
enum AppleMusicLibrarySource {
    /// Attempt to read the library. If TCC has not yet prompted, the system
    /// shows the dialog synchronously on first call; subsequent denials
    /// surface as an `ITLibrary` init error, which we map to `.cannotRead`.
    static func loadLibrary() throws -> ITunesLibrary {
        do {
            let lib = try ITLibrary(apiVersion: "1.1")
            return mapLibrary(lib)
        } catch {
            throw AppleMusicLibraryError.cannotRead(underlying: error)
        }
    }

    // MARK: - Mapping ITLib* → ITunesLibrary

    private static func mapLibrary(_ lib: ITLibrary) -> ITunesLibrary {
        var tracks: [Int: ITunesTrack] = [:]
        tracks.reserveCapacity(lib.allMediaItems.count)
        for item in lib.allMediaItems {
            guard item.mediaKind == .kindSong else { continue }
            let id = Int(truncatingIfNeeded: item.persistentID.uint64Value)
            let filenameFallback = item.location?.deletingPathExtension().lastPathComponent ?? ""
            let name: String
            if !item.title.isEmpty {
                name = item.title
            } else if !filenameFallback.isEmpty {
                name = filenameFallback
            } else {
                name = "Untitled"
            }
            tracks[id] = ITunesTrack(
                trackID: id,
                name: name,
                artist: item.artist?.name ?? "",
                album: item.album.title ?? "",
                genre: item.genre,
                duration: TimeInterval(item.totalTime) / 1000.0,
                location: item.location
            )
        }

        var playlists: [ITunesPlaylist] = []
        playlists.reserveCapacity(lib.allPlaylists.count)
        for p in lib.allPlaylists {
            let ids = p.items.map { Int(truncatingIfNeeded: $0.persistentID.uint64Value) }
            playlists.append(ITunesPlaylist(
                id: Int(truncatingIfNeeded: p.persistentID.uint64Value),
                name: p.name,
                isSmart: p.kind == .smart,
                isBuiltIn: p.isPrimary || p.distinguishedKind != .kindNone,
                trackIDs: ids
            ))
        }
        return ITunesLibrary(tracks: tracks, playlists: playlists)
    }
}
