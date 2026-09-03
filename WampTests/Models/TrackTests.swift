import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("Track")
struct TrackTests {

    private func fixtureURL(file: StaticString = #filePath) -> URL {
        // #filePath → .../WampTests/Models/TrackTests.swift
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // WampTests/Models
            .deletingLastPathComponent()   // WampTests
            .appendingPathComponent("Fixtures/sample.m4a")
    }

    @Test func fromURL_parsesMetadataTags() async {
        let track = await Track.fromURL(fixtureURL())
        #expect(track.title == "Wamp Fixture Title")
        #expect(track.artist == "Wamp Fixture Artist")
        #expect(track.album == "Wamp Fixture Album")
        #expect(track.genre == "Electronic")
    }

    @Test func fromURL_parsesAudioFormat() async {
        let track = await Track.fromURL(fixtureURL())
        #expect(track.channels == 2)
        #expect(track.sampleRate == 44_100)
        #expect(track.duration > 0.3)
        #expect(track.duration < 0.8)
    }

    @Test func fromURL_unreadableFile_fallsBackToFilename() async {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")
        let track = await Track.fromURL(bogus)
        #expect(track.title == bogus.deletingPathExtension().lastPathComponent)
        #expect(track.duration == 0)
    }

    @Test func displayTitle_formatsArtistAndTitle() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Band", album: "", duration: 0)
        #expect(track.displayTitle == "Band - Song")
    }

    @Test func displayTitle_withoutArtist_returnsTitleOnly() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Unknown Artist", album: "", duration: 0)
        #expect(track.displayTitle == "Song")
    }

    @Test func formattedDuration_minutesAndSeconds() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "", artist: "", album: "", duration: 125)
        #expect(track.formattedDuration == "2:05")
    }

    @Test func isCueVirtualFalseByDefault() {
        let t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 1)
        #expect(t.cueStart == nil)
        #expect(t.cueEnd == nil)
        #expect(t.isCueVirtual == false)
    }

    @Test func isCueVirtualTrueWhenCueStartSet() {
        var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 30)
        t.cueStart = 10
        t.cueEnd = 40
        #expect(t.isCueVirtual == true)
    }

    @Test func codableRoundTripPreservesCueRange() throws {
        var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                      title: "x", artist: "", album: "", duration: 30)
        t.cueStart = 10.5
        t.cueEnd = 40.25
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded.cueStart == 10.5)
        #expect(decoded.cueEnd == 40.25)
    }

    // MARK: - Remote (Navidrome) tracks

    @Test func isRemoteFalseByDefault() {
        let t = Track(url: URL(fileURLWithPath: "/tmp/x.mp3"),
                      title: "x", artist: "", album: "", duration: 1)
        #expect(t.remoteID == nil)
        #expect(t.isRemote == false)
    }

    @Test func isRemoteTrueWhenRemoteIDSet() {
        let t = Track(url: URL(string: "navidrome://host/Artist/Album/01%20-%20x.mp3")!,
                      title: "x", artist: "", album: "", duration: 1,
                      remoteID: "abc123")
        #expect(t.isRemote == true)
        #expect(t.url.lastPathComponent == "01 - x.mp3")
    }

    @Test func codableRoundTripPreservesRemoteID() throws {
        let t = Track(url: URL(string: "navidrome://host/a.flac")!,
                      title: "x", artist: "", album: "", duration: 1,
                      remoteID: "song-1")
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded.remoteID == "song-1")
        #expect(decoded.isRemote == true)
    }

    @Test func decodingLegacyTrackWithoutRemoteIDIsLocal() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","url":"file:///tmp/x.m4a","title":"x",
         "artist":"a","album":"b","duration":3,"genre":"","bitrate":0,"sampleRate":0,"channels":2}
        """
        let decoded = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        #expect(decoded.isRemote == false)
    }
}
