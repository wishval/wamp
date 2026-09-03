import Testing
import Foundation
import AVFoundation
@testable import Wamp

/// End-to-end check against a real server. Skipped unless the runner sets
/// WAMP_NAVIDROME_URL / WAMP_NAVIDROME_USER / WAMP_NAVIDROME_PASSWORD, e.g.
///
///   TEST_RUNNER_WAMP_NAVIDROME_URL=http://host:4533 \
///   TEST_RUNNER_WAMP_NAVIDROME_USER=me TEST_RUNNER_WAMP_NAVIDROME_PASSWORD=pw \
///   xcodebuild ... test -only-testing:WampTests/NavidromeLiveTests
/// Read once so the `@Suite` enablement trait doesn't reference the suite's
/// own members (that trips the macro's circular-reference check).
private let liveCredentials: SubsonicCredentials? = {
    let env = ProcessInfo.processInfo.environment
    guard let urlText = env["WAMP_NAVIDROME_URL"], let url = URL(string: urlText),
          let user = env["WAMP_NAVIDROME_USER"], let pw = env["WAMP_NAVIDROME_PASSWORD"] else { return nil }
    return SubsonicCredentials(serverURL: url, username: user, password: pw)
}()

@MainActor
@Suite("Navidrome live server", .enabled(if: liveCredentials != nil))
struct NavidromeLiveTests {

    static var credentials: SubsonicCredentials? { liveCredentials }

    @Test func pingAndBrowse() async throws {
        let client = SubsonicClient(credentials: try #require(Self.credentials))
        try await client.ping()
        let artists = try await client.artists()
        #expect(!artists.isEmpty)
        let first = try #require(artists.first)
        let full = try await client.artist(id: first.id)
        #expect(full.name == first.name)
        let albums = try await client.albumList(.newest, size: 3)
        #expect(!albums.isEmpty)
        let search = try await client.search(String(first.name.prefix(3)))
        #expect((search.artist ?? []).count + (search.album ?? []).count + (search.song ?? []).count > 0)
    }

    @Test func streamRandomSongThroughCacheAndDecode() async throws {
        let creds = try #require(Self.credentials)
        let client = SubsonicClient(credentials: creds)
        let song = try #require(try await client.randomSongs(size: 1).first)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wamp-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)

        let ext = NavidromeService.cacheExtension(forSuffix: song.suffix)
        let transcode = ext != (song.suffix ?? "").lowercased()
        let remote = client.streamURL(id: song.id, format: transcode ? "mp3" : nil, maxBitRate: transcode ? 320 : nil)
        let local = try await cache.localURL(id: song.id, ext: ext, remote: remote)

        // The whole point of the cache: AudioEngine must be able to open it.
        let file = try AVAudioFile(forReading: local)
        #expect(file.length > 0)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        if let expected = song.duration {
            #expect(abs(seconds - expected) < 2, "decoded \(seconds)s vs server \(expected)s for \(song.title)")
        }
    }

    @Test func wrongPasswordIsReportedAsCode40() async throws {
        let creds = try #require(Self.credentials)
        let bad = SubsonicClient(credentials: SubsonicCredentials(
            serverURL: creds.serverURL, username: creds.username, password: creds.password + "x"))
        await #expect(throws: SubsonicError.server(code: 40, message: "Wrong username or password")) {
            try await bad.ping()
        }
    }
}
