import Foundation
import Combine

class PlaylistManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1
    @Published var searchQuery = ""

    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    var currentTrack: Track? {
        guard currentIndex >= 0, currentIndex < tracks.count else { return nil }
        return tracks[currentIndex]
    }

    var filteredTracks: [Track] {
        guard !searchQuery.isEmpty else { return tracks }
        let query = searchQuery.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query)
        }
    }

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalDuration: String {
        let total = Int(totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// H:MM (or MM if under an hour). Used in the playlist footer LCD where
    /// the full HH:MM:SS form won't fit alongside the track count.
    var formattedTotalDurationCompact: String {
        let total = Int(totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        }
        return "\(minutes)"
    }

    init() {
        NotificationCenter.default.publisher(for: .trackDidFinish)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.advanceToNext() }
            .store(in: &cancellables)
    }

    func setAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }

    // MARK: - Track Management
    func addTracks(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
    }

    func addURLs(_ urls: [URL]) async {
        var newTracks: [Track] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Track.supportedExtensions.contains(ext) else { continue }

            if ext == "flac" {
                // External sibling .cue wins — it's the more explicit user action.
                let siblingCue = url.deletingPathExtension().appendingPathExtension("cue")
                if FileManager.default.fileExists(atPath: siblingCue.path) {
                    do {
                        try await self.addCueSheet(url: siblingCue)
                        continue
                    } catch {
                        print("🟡 addURLs: sibling .cue failed (\(error)), falling through")
                    }
                }
                // Embedded CUESHEET.
                if let cueText = (try? FlacCueExtractor.extractCueSheet(from: url)) ?? nil,
                   let cueData = cueText.data(using: .utf8) {
                    do {
                        let sheet = try CueSheetParser.parse(cueData)
                        let resolved = try await CueResolver.resolveTracks(
                            cue: sheet, cueDirectory: url.deletingLastPathComponent()
                        )
                        newTracks.append(contentsOf: resolved)
                        continue
                    } catch {
                        print("🟡 addURLs: embedded CUESHEET unusable (\(error)), falling through")
                    }
                }
            }

            let track = await Track.fromURL(url)
            newTracks.append(track)
        }
        addTracks(newTracks)
    }

    func addFolder(_ folderURL: URL) async {
        let urls = collectAudioURLs(in: folderURL)
        await addURLs(urls)
    }

    struct M3UImportSummary: Equatable {
        let imported: Int
        let missing: Int
    }

    /// Parse an M3U/M3U8 playlist and append tracks whose files exist to the current
    /// playlist. Missing files are counted so callers can surface a warning; they are
    /// not added as placeholder tracks (the task spec prescribes greying-out on
    /// reload, not on initial import).
    @discardableResult
    func addM3U(url: URL) async throws -> M3UImportSummary {
        let entries = try M3UParser.parse(url: url)
        var present: [URL] = []
        var missing = 0
        for entry in entries {
            if FileManager.default.fileExists(atPath: entry.url.path) {
                present.append(entry.url)
            } else {
                missing += 1
            }
        }
        let before = tracks.count
        await addURLs(present)
        return M3UImportSummary(imported: tracks.count - before, missing: missing)
    }

    private func collectAudioURLs(in folderURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if Track.supportedExtensions.contains(ext) {
                urls.append(fileURL)
            }
        }
        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return urls
    }

    func removeTrack(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, tracks.count - 1)
        }
    }

    func moveTracks(from sourceIndexes: IndexSet, to destinationIndex: Int) {
        guard !sourceIndexes.isEmpty else { return }

        let currentTrack = currentIndex >= 0 && currentIndex < tracks.count ? tracks[currentIndex] : nil

        // Collect tracks to move
        let movedTracks = sourceIndexes.map { tracks[$0] }

        // Calculate destination adjustment for indexes before destination
        let countBefore = sourceIndexes.filter { $0 < destinationIndex }.count
        let adjustedDestination = destinationIndex - countBefore

        // Remove from original positions (reverse order to preserve indexes)
        for index in sourceIndexes.reversed() {
            tracks.remove(at: index)
        }

        // Insert at destination
        for (offset, track) in movedTracks.enumerated() {
            tracks.insert(track, at: adjustedDestination + offset)
        }

        // Restore currentIndex to follow the playing track
        if let currentTrack {
            currentIndex = tracks.firstIndex(where: { $0.id == currentTrack.id }) ?? -1
        }
    }

    func clearPlaylist() {
        tracks.removeAll()
        currentIndex = -1
    }

    // MARK: - Playback Navigation
    func playTrack(at index: Int) {
        guard index >= 0, index < tracks.count else {
            print("⚡ playTrack: invalid index \(index), tracks.count=\(tracks.count)")
            return
        }
        print("⚡ playTrack(at: \(index)) — \(tracks[index].url.lastPathComponent)")
        currentIndex = index
        let track = tracks[index]
        if let start = track.cueStart {
            audioEngine?.loadAndPlay(url: track.url, startTime: start, endTime: track.cueEnd)
        } else {
            audioEngine?.loadAndPlay(url: track.url)
        }
        prepareGaplessChain(after: index)
    }

    /// If the *next* track in the playlist is on the same underlying audio file as the
    /// one just started, schedule it back-to-back on the engine so the handoff is
    /// sample-accurate.
    private func prepareGaplessChain(after index: Int) {
        guard index + 1 < tracks.count else { return }
        let cur = tracks[index]
        let next = tracks[index + 1]
        guard cur.isCueVirtual, next.isCueVirtual, cur.url == next.url else { return }
        guard let start = next.cueStart else { return }
        _ = audioEngine?.chainNextSegment(url: next.url, startTime: start, endTime: next.cueEnd)
    }

    // MARK: - CUE sheets

    /// Load a .cue sheet, resolve its virtual tracks, and append them to the playlist.
    /// Throws if the cue can't be parsed or the referenced audio file is missing.
    @MainActor
    func addCueSheet(url: URL) async throws {
        let sheet = try CueSheetParser.parse(url: url)
        let resolved = try await CueResolver.resolveTracks(
            cue: sheet, cueDirectory: url.deletingLastPathComponent()
        )
        addTracks(resolved)
    }

    func playNext() {
        print("⚡ playNext: currentIndex=\(currentIndex), tracks.count=\(tracks.count)")
        guard !tracks.isEmpty else { return }

        let nextIndex = currentIndex + 1
        if nextIndex >= tracks.count {
            if audioEngine?.repeatMode == .playlist {
                playTrack(at: 0)
            } else {
                audioEngine?.stop()
            }
        } else {
            playTrack(at: nextIndex)
        }
    }

    func playPrevious() {
        guard !tracks.isEmpty else { return }

        if let engine = audioEngine, engine.currentTime > 3.0 {
            engine.seek(to: 0)
            return
        }

        let prevIndex = currentIndex - 1
        if prevIndex < 0 {
            playTrack(at: tracks.count - 1)
        } else {
            playTrack(at: prevIndex)
        }
    }

    // MARK: - Sorting (MISC menu)
    /// Case-insensitive sort by track title. Preserves currentIndex → playing track.
    func sortByTitle() {
        sortTracks { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Sort by URL.lastPathComponent (filename only), localized case-insensitive.
    func sortByFilename() {
        sortTracks { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    /// Sort by full URL.path, localized case-insensitive.
    func sortByPath() {
        sortTracks { $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending }
    }

    /// Reverse the current list order.
    func reverseList() {
        sortTracks(using: nil, reverse: true)
    }

    private func sortTracks(using predicate: ((Track, Track) -> Bool)? = nil, reverse: Bool = false) {
        let current = currentIndex >= 0 && currentIndex < tracks.count ? tracks[currentIndex] : nil
        if let predicate {
            tracks.sort(by: predicate)
        }
        if reverse {
            tracks.reverse()
        }
        if let current {
            currentIndex = tracks.firstIndex(where: { $0.id == current.id }) ?? -1
        }
    }

    func shuffleTracks() {
        guard tracks.count > 1 else { return }
        let currentTrack = currentIndex >= 0 && currentIndex < tracks.count ? tracks[currentIndex] : nil
        tracks.shuffle()
        if let currentTrack = currentTrack {
            currentIndex = tracks.firstIndex(where: { $0.url == currentTrack.url }) ?? -1
        }
    }

    // MARK: - Saved Playlists
    func savePlaylist(name: String, to directory: URL) {
        let fileURL = directory.appendingPathComponent("\(name).json")
        let urls = tracks.map { $0.url.path }
        if let data = try? JSONEncoder().encode(urls) {
            try? data.write(to: fileURL)
        }
    }

    func loadPlaylist(from fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        clearPlaylist()
        let urls = paths.map { URL(fileURLWithPath: $0) }
        await addURLs(urls)
    }

    /// Write the current playlist as an M3U file (one track URL/path per line).
    func savePlaylistM3U(to fileURL: URL) {
        var lines: [String] = ["#EXTM3U"]
        for track in tracks {
            lines.append("#EXTINF:\(Int(track.duration.rounded())),\(track.displayTitle)")
            lines.append(track.url.path)
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Load an M3U/M3U8/PLS playlist, replacing the current track list.
    /// Returns an import summary (present vs missing entry count).
    @discardableResult
    func loadPlaylistM3U(from fileURL: URL) async -> M3UImportSummary {
        let ext = fileURL.pathExtension.lowercased()
        var urls: [URL] = []
        var missing = 0
        if ext == "pls" {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return M3UImportSummary(imported: 0, missing: 0)
            }
            let baseDir = fileURL.deletingLastPathComponent()
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix("file"),
                      let eq = trimmed.firstIndex(of: "=") else { continue }
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                let candidate = resolvePLSEntry(value, baseDir: baseDir)
                if candidate.isFileURL, !FileManager.default.fileExists(atPath: candidate.path) {
                    missing += 1
                } else {
                    urls.append(candidate)
                }
            }
        } else {
            guard let entries = try? M3UParser.parse(url: fileURL) else {
                return M3UImportSummary(imported: 0, missing: 0)
            }
            for entry in entries {
                if FileManager.default.fileExists(atPath: entry.url.path) {
                    urls.append(entry.url)
                } else {
                    missing += 1
                }
            }
        }
        clearPlaylist()
        let before = tracks.count
        await addURLs(urls)
        return M3UImportSummary(imported: tracks.count - before, missing: missing)
    }

    private func resolvePLSEntry(_ entry: String, baseDir: URL) -> URL {
        if let url = URL(string: entry), url.scheme != nil { return url }
        if entry.hasPrefix("/") { return URL(fileURLWithPath: entry) }
        return baseDir.appendingPathComponent(entry)
    }

    // MARK: - Private
    private func advanceToNext() {
        print("⚡ advanceToNext: repeatMode=\(String(describing: audioEngine?.repeatMode))")
        guard audioEngine?.repeatMode != .track else { return }
        guard !tracks.isEmpty else { return }

        let nextIndex = currentIndex + 1
        if nextIndex >= tracks.count {
            if audioEngine?.repeatMode == .playlist {
                playTrack(at: 0)
            } else {
                audioEngine?.stop()
            }
            return
        }

        // If a gapless chain is in flight (previous and next are CUE-virtual on the
        // same underlying file) the engine has already started the next segment —
        // just promote currentIndex and prepare the segment *after* it.
        let prev = currentIndex >= 0 && currentIndex < tracks.count ? tracks[currentIndex] : nil
        let next = tracks[nextIndex]
        if let prev = prev,
           prev.isCueVirtual, next.isCueVirtual, prev.url == next.url {
            currentIndex = nextIndex
            prepareGaplessChain(after: nextIndex)
            return
        }
        playTrack(at: nextIndex)
    }

}
