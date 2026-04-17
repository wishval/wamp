import Foundation
import AVFoundation

enum CueResolverError: Error {
    case audioFileMissing(URL)
    case audioFileUnreadable(URL, underlying: Error)
}

enum CueResolver {
    /// Resolve a parsed CUE sheet into one Track per CUE-track entry.
    /// - The audio file referenced by each FILE entry must exist relative to `cueDirectory`.
    /// - The end of track N is the start of track N+1, or EOF for the last track in a FILE.
    @MainActor
    static func resolveTracks(cue: CueSheet, cueDirectory: URL) async throws -> [Track] {
        var resolved: [Track] = []
        for fileEntry in cue.files {
            let audioURL = cueDirectory.appendingPathComponent(fileEntry.path)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw CueResolverError.audioFileMissing(audioURL)
            }

            let totalDuration: TimeInterval
            do {
                let asset = AVURLAsset(url: audioURL)
                let dur = try await asset.load(.duration)
                totalDuration = dur.seconds.isFinite ? dur.seconds : 0
            } catch {
                throw CueResolverError.audioFileUnreadable(audioURL, underlying: error)
            }

            for (i, t) in fileEntry.tracks.enumerated() {
                let start = CueSheet.framesToSeconds(t.startFrames)
                let end: TimeInterval?
                if i + 1 < fileEntry.tracks.count {
                    end = CueSheet.framesToSeconds(fileEntry.tracks[i + 1].startFrames)
                } else {
                    end = nil   // play to EOF
                }
                let trackDuration = (end ?? totalDuration) - start
                let title = t.title ?? "Track \(t.number)"
                let artist = t.performer ?? cue.performer ?? "Unknown Artist"
                let album = cue.title ?? ""
                resolved.append(Track(
                    url: audioURL,
                    title: title,
                    artist: artist,
                    album: album,
                    duration: max(0, trackDuration),
                    genre: cue.genre ?? "",
                    cueStart: start,
                    cueEnd: end
                ))
            }
        }
        return resolved
    }
}
