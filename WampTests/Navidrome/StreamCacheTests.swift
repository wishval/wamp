import Testing
import Foundation
@testable import Wamp

@Suite("StreamCache")
struct StreamCacheTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wamp-cache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func cachedURL_reportsHitOnlyWhenFileExists() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)
        #expect(cache.cachedURL(id: "a", ext: "mp3") == nil)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("a.mp3"))
        #expect(cache.cachedURL(id: "a", ext: "mp3") == dir.appendingPathComponent("a.mp3"))
    }

    @Test func localURL_returnsExistingFileWithoutNetwork() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = StreamCache(directory: dir)
        let file = dir.appendingPathComponent("b.flac")
        try Data([9]).write(to: file)
        // An unroutable URL: if the cache tried to download, this would fail.
        let url = try await cache.localURL(id: "b", ext: "flac", remote: URL(string: "http://0.0.0.0:1/x")!)
        #expect(url == file)
    }

    @Test func localURL_downloadsFromLocalFileURLAndEvictsLRU() async throws {
        let dir = tempDir()
        let src = tempDir()
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: src)
        }
        // file:// URLs go through URLSession like any other, so this covers the
        // download → move path without a server.
        let payload = Data(repeating: 7, count: 1000)
        let s1 = src.appendingPathComponent("one.bin"); try payload.write(to: s1)
        let s2 = src.appendingPathComponent("two.bin"); try payload.write(to: s2)

        let cache = StreamCache(directory: dir, sizeLimit: 1500)
        let u1 = try await cache.localURL(id: "one", ext: "mp3", remote: s1)
        #expect(try Data(contentsOf: u1) == payload)
        // Make "one" clearly older than "two" for the LRU sort.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: u1.path)
        let u2 = try await cache.localURL(id: "two", ext: "mp3", remote: s2)
        #expect(FileManager.default.fileExists(atPath: u2.path))
        #expect(!FileManager.default.fileExists(atPath: u1.path), "oldest entry evicted past the size limit")
        #expect(await cache.size() == 1000)
    }
}
