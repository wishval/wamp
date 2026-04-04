import Foundation
import AVFoundation

struct Track: Identifiable, Codable, Equatable {
    nonisolated static let supportedExtensions: Set<String> = [
        "mp3", "aac", "m4a", "flac", "wav", "aiff", "aif"
    ]

    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var genre: String
    var bitrate: Int
    var sampleRate: Int
    var channels: Int

    init(
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        genre: String = "",
        bitrate: Int = 0,
        sampleRate: Int = 0,
        channels: Int = 2
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.genre = genre
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
    }

    var displayTitle: String {
        if artist.isEmpty || artist == "Unknown Artist" {
            return title
        }
        return "\(artist) - \(title)"
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var isStereo: Bool { channels >= 2 }

    @MainActor
    static func fromURL(_ url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = ""
        var genre = ""
        var duration: TimeInterval = 0
        var bitrate = 0
        var sampleRate = 0
        var channels = 2

        do {
            let metadata = try await asset.load(.commonMetadata)
            let dur = try await asset.load(.duration)
            duration = dur.seconds.isFinite ? dur.seconds : 0

            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        title = val
                    }
                case .commonKeyArtist:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        artist = val
                    }
                case .commonKeyAlbumName:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        album = val
                    }
                case .commonKeyType:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        genre = val
                    }
                default:
                    break
                }
            }

            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let descriptions = try await audioTrack.load(.formatDescriptions)
                if let desc = descriptions.first {
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
                    if let asbd = asbd {
                        sampleRate = Int(asbd.mSampleRate)
                        channels = Int(asbd.mChannelsPerFrame)
                    }
                }
                let estimatedRate = try await audioTrack.load(.estimatedDataRate)
                bitrate = Int(estimatedRate / 1000)
            }
        } catch {
            // Fallback: use filename as title
        }

        return Track(
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            genre: genre,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels
        )
    }
}
