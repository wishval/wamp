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
}
