import Foundation

/// Downloads remote tracks into `~/Library/Caches/Wamp/Navidrome/` and hands
/// back local file URLs. `AudioEngine` plays local files only (AVAudioFile
/// can't read HTTP), and routing streams through the same graph is what
/// keeps EQ and the spectrum analyzer working for server music.
///
/// Files are keyed `<songID>.<ext>`. Concurrent requests for the same song
/// share one download. When the cache exceeds `sizeLimit`, the least
/// recently used files are evicted after each new download.
actor StreamCache {
    let directory: URL
    var sizeLimit: Int64

    private var inFlight: [String: Task<URL, Error>] = [:]
    private let session: URLSession

    init(directory: URL = StreamCache.defaultDirectory,
         sizeLimit: Int64 = 4 * 1024 * 1024 * 1024,
         session: URLSession = StreamCache.makeSession()) {
        self.directory = directory
        self.sizeLimit = sizeLimit
        self.session = session
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("Wamp/Navidrome", isDirectory: true)
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    nonisolated func fileURL(id: String, ext: String) -> URL {
        directory.appendingPathComponent("\(id).\(ext)")
    }

    /// Already-downloaded file, or nil. Cheap and synchronous-friendly.
    nonisolated func cachedURL(id: String, ext: String) -> URL? {
        let url = fileURL(id: id, ext: ext)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Returns a local file for the song, downloading it from `remote` on a
    /// cache miss. Concurrent callers for the same id await one download.
    func localURL(id: String, ext: String, remote: URL) async throws -> URL {
        let target = fileURL(id: id, ext: ext)
        if FileManager.default.fileExists(atPath: target.path) {
            touch(target)
            return target
        }
        if let existing = inFlight[id] {
            return try await existing.value
        }
        let task = Task<URL, Error> { [session] in
            let (temp, response) = try await session.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: temp)
                throw SubsonicError.httpStatus(http.statusCode)
            }
            // Auth failures on `stream` come back as 200 + JSON/XML envelope.
            let contentType = response.mimeType ?? ""
            if contentType.contains("json") || contentType.contains("xml") {
                let body = (try? Data(contentsOf: temp)) ?? Data()
                try? FileManager.default.removeItem(at: temp)
                // Surfaces `.server(code:message:)` for a failed envelope,
                // `.malformedResponse` for anything else non-audio.
                try SubsonicResponseParser.validated(body)
                throw SubsonicError.notAudio(contentType: contentType)
            }
            let fm = FileManager.default
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: temp)
            } else {
                try fm.moveItem(at: temp, to: target)
            }
            return target
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let url = try await task.value
        evictIfNeeded(keeping: url)
        return url
    }

    func removeAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Total bytes on disk.
    func size() -> Int64 {
        entries().reduce(0) { $0 + $1.size }
    }

    // MARK: - Private

    private struct Entry { let url: URL; let size: Int64; let accessed: Date }

    private func entries() -> [Entry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return Entry(url: url, size: Int64(values.fileSize ?? 0), accessed: values.contentModificationDate ?? .distantPast)
        }
    }

    /// Bump the modification date so LRU eviction sees the file as fresh.
    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func evictIfNeeded(keeping keep: URL) {
        var all = entries().sorted { $0.accessed < $1.accessed }
        var total = all.reduce(0) { $0 + $1.size }
        while total > sizeLimit, let oldest = all.first {
            all.removeFirst()
            if oldest.url == keep { continue }
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
        }
    }
}
