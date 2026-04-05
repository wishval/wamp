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
            if Track.supportedExtensions.contains(ext) {
                let track = await Track.fromURL(url)
                newTracks.append(track)
            }
        }
        addTracks(newTracks)
    }

    func addFolder(_ folderURL: URL) async {
        let urls = collectAudioURLs(in: folderURL)
        await addURLs(urls)
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
        audioEngine?.loadAndPlay(url: tracks[index].url)
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

    // MARK: - Private
    private func advanceToNext() {
        print("⚡ advanceToNext: repeatMode=\(String(describing: audioEngine?.repeatMode))")
        guard audioEngine?.repeatMode != .track else { return }
        playNext()
    }

}
