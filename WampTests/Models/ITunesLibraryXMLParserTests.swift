import Testing
import Foundation
@testable import Wamp

@Suite("ITunesLibraryXMLParser")
struct ITunesLibraryXMLParserTests {

    private func xml(_ body: String) -> Data {
        let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """
        return header.data(using: .utf8)!
    }

    @Test func emptyLibraryParses() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict></dict>
            <key>Playlists</key><array></array>
        """))
        #expect(lib.tracks.isEmpty)
        #expect(lib.playlists.isEmpty)
    }

    @Test func parsesTrackWithLocation() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict>
                <key>1001</key>
                <dict>
                    <key>Track ID</key><integer>1001</integer>
                    <key>Name</key><string>Song A</string>
                    <key>Artist</key><string>Artist A</string>
                    <key>Album</key><string>Album A</string>
                    <key>Total Time</key><integer>210000</integer>
                    <key>Location</key><string>file:///Users/me/Music/song-a.mp3</string>
                </dict>
            </dict>
            <key>Playlists</key><array></array>
        """))
        #expect(lib.tracks.count == 1)
        let t = lib.tracks[1001]!
        #expect(t.name == "Song A")
        #expect(t.artist == "Artist A")
        #expect(t.album == "Album A")
        #expect(t.duration == 210.0)
        #expect(t.location?.path == "/Users/me/Music/song-a.mp3")
    }

    @Test func trackWithoutLocationIsStreamingOnly() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict>
                <key>1002</key>
                <dict>
                    <key>Track ID</key><integer>1002</integer>
                    <key>Name</key><string>Cloud Song</string>
                </dict>
            </dict>
            <key>Playlists</key><array></array>
        """))
        let t = lib.tracks[1002]!
        #expect(t.location == nil)
        #expect(t.isStreamingOnly)
    }

    @Test func percentEncodedLocationIsDecoded() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict>
                <key>1</key>
                <dict>
                    <key>Track ID</key><integer>1</integer>
                    <key>Name</key><string>X</string>
                    <key>Location</key><string>file:///Users/me/My%20Music/a%20file.mp3</string>
                </dict>
            </dict>
            <key>Playlists</key><array></array>
        """))
        #expect(lib.tracks[1]?.location?.path == "/Users/me/My Music/a file.mp3")
    }

    @Test func parsesPlaylistWithTrackReferences() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict>
                <key>1</key><dict><key>Track ID</key><integer>1</integer><key>Name</key><string>A</string></dict>
                <key>2</key><dict><key>Track ID</key><integer>2</integer><key>Name</key><string>B</string></dict>
            </dict>
            <key>Playlists</key><array>
                <dict>
                    <key>Playlist ID</key><integer>500</integer>
                    <key>Name</key><string>My Mix</string>
                    <key>Playlist Items</key>
                    <array>
                        <dict><key>Track ID</key><integer>1</integer></dict>
                        <dict><key>Track ID</key><integer>2</integer></dict>
                    </array>
                </dict>
            </array>
        """))
        #expect(lib.playlists.count == 1)
        let p = lib.playlists[0]
        #expect(p.name == "My Mix")
        #expect(p.trackIDs == [1, 2])
        #expect(!p.isSmart)
    }

    @Test func smartPlaylistFlagged() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict></dict>
            <key>Playlists</key><array>
                <dict>
                    <key>Playlist ID</key><integer>501</integer>
                    <key>Name</key><string>90s Hits</string>
                    <key>Smart Info</key><data>YWJj</data>
                    <key>Playlist Items</key><array/>
                </dict>
            </array>
        """))
        #expect(lib.playlists[0].isSmart)
    }

    @Test func builtInPlaylistsAreMarked() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict></dict>
            <key>Playlists</key><array>
                <dict>
                    <key>Playlist ID</key><integer>1</integer>
                    <key>Name</key><string>Library</string>
                    <key>Master</key><true/>
                    <key>Playlist Items</key><array/>
                </dict>
                <dict>
                    <key>Playlist ID</key><integer>2</integer>
                    <key>Name</key><string>Music</string>
                    <key>Distinguished Kind</key><integer>4</integer>
                    <key>Playlist Items</key><array/>
                </dict>
                <dict>
                    <key>Playlist ID</key><integer>3</integer>
                    <key>Name</key><string>My Mix</string>
                    <key>Playlist Items</key><array/>
                </dict>
            </array>
        """))
        #expect(lib.playlists.count == 3)
        #expect(lib.playlists[0].isBuiltIn)
        #expect(lib.playlists[1].isBuiltIn)
        #expect(!lib.playlists[2].isBuiltIn)
    }

    @Test func tracksWithoutNameUseFilenameFallback() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict>
                <key>1</key>
                <dict>
                    <key>Track ID</key><integer>1</integer>
                    <key>Location</key><string>file:///Users/me/noname.mp3</string>
                </dict>
            </dict>
            <key>Playlists</key><array></array>
        """))
        #expect(lib.tracks[1]?.name == "noname")
    }

    @Test func ignoresMalformedTracksButKeepsValidOnes() throws {
        let lib = try ITunesLibraryXMLParser.parse(data: xml("""
            <key>Tracks</key><dict>
                <key>1</key>
                <dict>
                    <key>Track ID</key><integer>1</integer>
                    <key>Name</key><string>Valid</string>
                </dict>
                <key>2</key>
                <string>not a dict</string>
            </dict>
            <key>Playlists</key><array></array>
        """))
        #expect(lib.tracks.count == 1)
        #expect(lib.tracks[1]?.name == "Valid")
    }

    @Test func throwsWhenTopLevelIsNotPlist() throws {
        let data = "not a plist".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try ITunesLibraryXMLParser.parse(data: data)
        }
    }

    @Test func parseFromURLRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wamp-lib-xml-test-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let body = """
            <key>Tracks</key><dict>
                <key>7</key>
                <dict>
                    <key>Track ID</key><integer>7</integer>
                    <key>Name</key><string>Seven</string>
                    <key>Location</key><string>file:///tmp/seven.mp3</string>
                </dict>
            </dict>
            <key>Playlists</key><array></array>
        """
        try xml(body).write(to: tmp)
        let lib = try ITunesLibraryXMLParser.parse(url: tmp)
        #expect(lib.tracks[7]?.name == "Seven")
    }
}
