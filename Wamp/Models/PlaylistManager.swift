import Foundation
import Combine

class PlaylistManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1
    @Published var searchQuery = ""

    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    /// Start playing files as they're opened (Finder/Dock, Open File, or a
    /// drop into an empty playlist). Persisted in AppState.
    var autoPlay = true

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
            .sink { [weak self] note in
                let chained = (note.userInfo?[AudioEngine.gaplessChainedKey] as? Bool) ?? false
                self?.advanceToNext(engineChained: chained)
            }
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
                // Resolve into the local batch (not straight into `tracks`) so a
                // mixed batch keeps its input order.
                let siblingCue = url.deletingPathExtension().appendingPathExtension("cue")
                if FileManager.default.fileExists(atPath: siblingCue.path) {
                    do {
                        let sheet = try CueSheetParser.parse(url: siblingCue)
                        let resolved = try await CueResolver.resolveTracks(
                            cue: sheet, cueDirectory: siblingCue.deletingLastPathComponent()
                        )
                        newTracks.append(contentsOf: resolved)
                        continue
                    } catch {
                        debugLog("🟡 sibling .cue failed (\(error)), falling through")
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
                        debugLog("🟡 embedded CUESHEET unusable (\(error)), falling through")
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

    struct LibraryImportSummary: Equatable {
        let imported: Int
        let skippedStreamingOnly: Int
        let skippedMissing: Int
    }

    /// Convert a set of tracks from a Music.app library snapshot into Wamp
    /// tracks and append (or replace) the playlist. Streaming-only items (no
    /// local file) and items whose file has been removed are counted for the
    /// summary alert but not added. Skips the usual `Track.fromURL` asset
    /// parse — metadata comes from the library snapshot directly, so
    /// importing thousands of tracks stays fast.
    @discardableResult
    func importMusicLibraryTracks(
        _ sourceTracks: [ITunesTrack],
        replaceCurrent: Bool
    ) -> LibraryImportSummary {
        var newTracks: [Track] = []
        var streamingOnly = 0
        var missing = 0
        for t in sourceTracks {
            guard let location = t.location, location.isFileURL else {
                streamingOnly += 1
                continue
            }
            if !FileManager.default.fileExists(atPath: location.path) {
                missing += 1
                continue
            }
            let track = Track(
                url: location,
                title: t.name,
                artist: t.artist.isEmpty ? "Unknown Artist" : t.artist,
                album: t.album,
                duration: t.duration,
                genre: t.genre
            )
            newTracks.append(track)
        }
        if replaceCurrent {
            clearPlaylist()
        }
        addTracks(newTracks)
        return LibraryImportSummary(
            imported: newTracks.count,
            skippedStreamingOnly: streamingOnly,
            skippedMissing: missing
        )
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
        let removingCurrent = index == currentIndex
        let wasPlaying = removingCurrent && (audioEngine?.isPlaying ?? false)
        tracks.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if removingCurrent {
            if wasPlaying {
                // Don't leave the engine playing a track that's gone from the
                // list (highlight, Now Playing and auto-advance all desync) —
                // move on to the track that slid into the slot, or stop.
                if index < tracks.count {
                    playTrack(at: index)
                } else if !tracks.isEmpty, audioEngine?.repeatMode == .playlist {
                    playTrack(at: 0)
                } else {
                    audioEngine?.stop()
                    currentIndex = min(index, tracks.count - 1)
                }
            } else {
                currentIndex = min(currentIndex, tracks.count - 1)
            }
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
        // An orphaned playing track would otherwise finish into a dead state
        // (no reschedule), leaving play() a silent no-op afterwards.
        // A paused one could otherwise be resumed by Play after the list is gone.
        if let engine = audioEngine, engine.playState != .stopped {
            engine.stop()
        }
        tracks.removeAll()
        currentIndex = -1
    }

    // MARK: - Opening files

    enum OpenResponse: Equatable { case play, makeCurrent, none }

    /// What to do after an open batch appended tracks at `firstNewIndex...`.
    /// `interrupt` is true for explicit opens (Finder/Dock, Open File), which
    /// start the new files like Winamp does; drops only start playback when
    /// they land in an empty playlist. Without autoplay the first new track
    /// just becomes current if nothing was, so Play starts there.
    static func openResponse(autoPlay: Bool, interrupt: Bool, firstNewIndex: Int, hasCurrentTrack: Bool) -> OpenResponse {
        if autoPlay && (interrupt || firstNewIndex == 0) { return .play }
        return hasCurrentTrack ? .none : .makeCurrent
    }

    func didOpenTracks(startingAt firstNewIndex: Int, interrupt: Bool) {
        guard tracks.indices.contains(firstNewIndex) else { return }
        switch Self.openResponse(autoPlay: autoPlay, interrupt: interrupt,
                                 firstNewIndex: firstNewIndex, hasCurrentTrack: currentTrack != nil) {
        case .play: playTrack(at: firstNewIndex)
        case .makeCurrent: currentIndex = firstNewIndex
        case .none: break
        }
    }

    // MARK: - Playback Navigation
    /// Play-button semantics shared by the transport, mini player, menu and
    /// media keys. Paused → resume. Otherwise start `preferredIndex` (the
    /// selected row), falling back to the current track, then the first one —
    /// never the engine's leftover file, which may no longer be in the list.
    func play(preferring preferredIndex: Int?) {
        if audioEngine?.playState == .paused {
            audioEngine?.play()
            return
        }
        let candidates = [preferredIndex, currentIndex, 0].compactMap { $0 }
        guard let index = candidates.first(where: { tracks.indices.contains($0) }) else { return }
        playTrack(at: index)
    }

    func playTrack(at index: Int) {
        guard index >= 0, index < tracks.count else {
            debugLog("⚡ invalid index \(index), tracks.count=\(tracks.count)")
            return
        }
        debugLog("⚡ playTrack(at: \(index)) — \(tracks[index].url.lastPathComponent)")
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
        debugLog("⚡ currentIndex=\(currentIndex), tracks.count=\(tracks.count)")
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
            // Match by id, not URL — cue virtual tracks and duplicate entries
            // share URLs, and grabbing the first same-URL entry desyncs
            // auto-advance from the actually playing instance.
            currentIndex = tracks.firstIndex(where: { $0.id == currentTrack.id }) ?? -1
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
        guard let entries = try? M3UParser.parse(url: fileURL) else {
            return M3UImportSummary(imported: 0, missing: 0)
        }
        var urls: [URL] = []
        var missing = 0
        for entry in entries {
            if FileManager.default.fileExists(atPath: entry.url.path) {
                urls.append(entry.url)
            } else {
                missing += 1
            }
        }
        clearPlaylist()
        let before = tracks.count
        await addURLs(urls)
        return M3UImportSummary(imported: tracks.count - before, missing: missing)
    }

    /// Decides whether auto-advance may simply promote `currentIndex` because
    /// the engine is already playing the next track via a queued gapless
    /// segment. `engineChained` comes from the engine's `.trackDidFinish`
    /// userInfo — track properties alone aren't enough, because a seek (or
    /// repeat-one) drops the queued segment from the player node.
    static func shouldPromoteChain(prev: Track?, next: Track, engineChained: Bool) -> Bool {
        guard engineChained, let prev else { return false }
        return prev.isCueVirtual && next.isCueVirtual && prev.url == next.url
    }

    // MARK: - Private
    private func advanceToNext(engineChained: Bool = false) {
        debugLog("⚡ repeatMode=\(String(describing: audioEngine?.repeatMode)), chained=\(engineChained)")
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

        // If a gapless chain is in flight the engine has already started the
        // next segment — just promote currentIndex and prepare the segment
        // *after* it. Otherwise (including same-file cue neighbors after a
        // seek dropped the queued segment) start the next track for real.
        let prev = currentIndex >= 0 && currentIndex < tracks.count ? tracks[currentIndex] : nil
        let next = tracks[nextIndex]
        if Self.shouldPromoteChain(prev: prev, next: next, engineChained: engineChained) {
            currentIndex = nextIndex
            prepareGaplessChain(after: nextIndex)
            return
        }
        playTrack(at: nextIndex)
    }

}
