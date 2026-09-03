import Testing
import Foundation
@testable import Wamp

@Suite("Subsonic client")
struct SubsonicClientTests {

    private let creds = SubsonicCredentials(
        serverURL: URL(string: "http://music.local:4533")!,
        username: "james",
        password: "sesame"
    )

    // Reference vector from the Subsonic API docs: md5("sesame" + "c19b2d").
    @Test func token_matchesSubsonicReferenceVector() {
        #expect(SubsonicCredentials.token(password: "sesame", salt: "c19b2d")
                == "26719a1196d2a940705a59634eb18eab")
    }

    @Test func endpoint_buildsRestURLWithAuthAndParams() throws {
        let url = creds.endpoint("getAlbum", params: [URLQueryItem(name: "id", value: "x y")], salt: "c19b2d")
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.path == "/rest/getAlbum")
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(q["u"] == "james")
        #expect(q["t"] == "26719a1196d2a940705a59634eb18eab")
        #expect(q["s"] == "c19b2d")
        #expect(q["v"] == "1.16.1")
        #expect(q["c"] == "wamp")
        #expect(q["f"] == "json")
        #expect(q["id"] == "x y")
        #expect(url.absoluteString.contains("id=x%20y"))
    }

    @Test func endpoint_toleratesSubpathAndTrailingSlash() {
        let c = SubsonicCredentials(serverURL: URL(string: "https://example.com/navidrome/")!,
                                    username: "u", password: "p")
        #expect(c.endpoint("ping").path == "/navidrome/rest/ping")
    }

    @Test func streamURL_requestsRawByDefault_andTranscodeWhenAsked() {
        let client = SubsonicClient(credentials: creds)
        #expect(client.streamURL(id: "abc").query?.contains("format=raw") == true)
        let t = client.streamURL(id: "abc", format: "mp3", maxBitRate: 320).query ?? ""
        #expect(t.contains("format=mp3"))
        #expect(t.contains("maxBitRate=320"))
    }

    @Test func displayHost_includesPort() {
        #expect(creds.displayHost == "music.local:4533")
    }

    // MARK: - Envelope parsing

    @Test func parser_unwrapsPayloadUnderKey() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","randomSongs":{"song":[
          {"id":"s1","title":"Remember Tomorrow","album":"A Real Dead One","artist":"Iron Maiden",
           "track":5,"year":1993,"genre":"Heavy Metal","suffix":"mp3","contentType":"audio/mpeg",
           "duration":352,"bitRate":320,"path":"Iron Maiden/A Real Dead One/05 - Remember Tomorrow.mp3",
           "channelCount":2,"samplingRate":44100}]}}}
        """
        struct Payload: Decodable { let song: [SubsonicSong]? }
        let p = try SubsonicResponseParser.decode(Payload.self, from: Data(json.utf8), key: "randomSongs")
        let song = try #require(p.song?.first)
        #expect(song.id == "s1")
        #expect(song.artist == "Iron Maiden")
        #expect(song.duration == 352)
        #expect(song.samplingRate == 44100)
    }

    @Test func parser_surfacesServerErrorCode() {
        let json = """
        {"subsonic-response":{"status":"failed","version":"1.16.1",
          "error":{"code":40,"message":"Wrong username or password"}}}
        """
        #expect(throws: SubsonicError.server(code: 40, message: "Wrong username or password")) {
            try SubsonicResponseParser.validated(Data(json.utf8))
        }
    }

    @Test func parser_rejectsNonSubsonicBody() {
        #expect(throws: SubsonicError.malformedResponse) {
            try SubsonicResponseParser.validated(Data("<html>nope</html>".utf8))
        }
    }

    @Test func parser_missingKeyDecodesAsEmptyPayload() throws {
        let json = #"{"subsonic-response":{"status":"ok","version":"1.16.1","playlists":{}}}"#
        struct Payload: Decodable { let playlist: [SubsonicPlaylist]? }
        let p = try SubsonicResponseParser.decode(Payload.self, from: Data(json.utf8), key: "playlists")
        #expect(p.playlist == nil)
    }

    // MARK: - Track conversion

    @Test func fromSubsonicSong_buildsDescriptiveURLAndMetadata() {
        let song = SubsonicSong(
            id: "s1", title: "Remember Tomorrow", album: "A Real Dead One", artist: "Iron Maiden",
            albumId: nil, artistId: nil, track: 5, discNumber: nil, year: 1993, genre: "Heavy Metal",
            suffix: "mp3", contentType: "audio/mpeg", duration: 352, bitRate: 320,
            samplingRate: 44100, channelCount: 2, size: nil,
            path: "Iron Maiden/A Real Dead One/05 - Remember Tomorrow.mp3"
        )
        let t = Track.fromSubsonicSong(song, host: "music.local:4533")
        #expect(t.isRemote)
        #expect(t.remoteID == "s1")
        #expect(t.url.scheme == "navidrome")
        #expect(t.url.host == "music.local")
        #expect(t.url.port == 4533)
        #expect(t.url.lastPathComponent == "05 - Remember Tomorrow.mp3")
        #expect(t.url.pathExtension == "mp3")
        #expect(t.displayTitle == "Iron Maiden - Remember Tomorrow")
        #expect(t.bitrate == 320)
        #expect(t.sampleRate == 44100)
    }

    @Test func fromSubsonicSong_withoutPathFallsBackToID() {
        let song = SubsonicSong(
            id: "s2", title: "x", album: nil, artist: nil, albumId: nil, artistId: nil, track: nil,
            discNumber: nil, year: nil, genre: nil, suffix: "flac", contentType: nil, duration: nil,
            bitRate: nil, samplingRate: nil, channelCount: nil, size: nil, path: nil
        )
        let t = Track.fromSubsonicSong(song, host: "h")
        #expect(t.url.lastPathComponent == "s2.flac")
        #expect(t.artist == "Unknown Artist")
    }

    @Test func cacheExtension_transcodesUnsupportedFormats() {
        #expect(NavidromeService.cacheExtension(forSuffix: "flac") == "flac")
        #expect(NavidromeService.cacheExtension(forSuffix: "MP3") == "mp3")
        #expect(NavidromeService.cacheExtension(forSuffix: "ogg") == "mp3")
        #expect(NavidromeService.cacheExtension(forSuffix: "opus") == "mp3")
        #expect(NavidromeService.cacheExtension(forSuffix: nil) == "mp3")
    }

    @Test func normalizeServerURL_addsSchemeAndStripsRest() {
        #expect(NavidromeAccountStore.normalizeServerURL("192.168.1.10:4533")?.absoluteString == "http://192.168.1.10:4533")
        #expect(NavidromeAccountStore.normalizeServerURL("https://m.example.com/rest/")?.absoluteString == "https://m.example.com")
        #expect(NavidromeAccountStore.normalizeServerURL("   ") == nil)
    }
}
