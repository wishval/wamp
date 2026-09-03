import AppKit
import Combine

/// Borderless, skin-aware lyrics window (View → Lyrics, ⌘Y). Content bounds
/// stay logical and the frame is scaled by `WinampTheme.scale`, exactly like
/// `MainWindow`, so Double Size applies here too.
final class LyricsWindow: NSWindow {
    let panel = LyricsPanelView()

    static let defaultLogicalSize = NSSize(width: WinampTheme.windowWidth, height: WinampTheme.playlistMinHeight)

    init() {
        let s = WinampTheme.scale
        let size = Self.defaultLogicalSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size.width * s, height: size.height * s),
            styleMask: [.borderless, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        isMovableByWindowBackground = false
        title = "Lyrics" // not drawn (borderless) but named for accessibility / Window menu
        backgroundColor = WinampTheme.frameBackground
        isOpaque = true
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        minSize = NSSize(width: 180 * s, height: 120 * s)
        panel.wantsLayer = true
        contentView = panel
        applyScale()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keep `panel.bounds` in logical Winamp pixels for the current frame.
    func applyScale() {
        let s = WinampTheme.scale
        let size = contentView?.frame.size ?? frame.size
        panel.setBoundsSize(NSSize(width: size.width / s, height: size.height / s))
        panel.needsLayout = true
        panel.needsDisplay = true
    }

    /// Called from AppDelegate.toggleDoubleSize: rescale keeping the top-left corner put.
    func recalculateSize() {
        let s = WinampTheme.scale
        let logical = panel.bounds.size
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y + frame.height - logical.height * s,
            width: logical.width * s,
            height: logical.height * s
        )
        setFrame(newFrame, display: true)
        applyScale()
    }
}

/// Feeds the lyrics window from the connected Navidrome server. Synced
/// (LRC/SYLT) lyrics highlight the current line and keep it centred as the
/// track plays; plain lyrics are shown as text.
@MainActor
final class LyricsWindowController: NSWindowController, NSWindowDelegate {

    private let service: NavidromeService
    private let playlistManager: PlaylistManager
    private let audioEngine: AudioEngine
    private var cancellables = Set<AnyCancellable>()

    private var lyrics: SubsonicLyrics?
    private var lineStartsMs: [Int] = []
    private var currentLine: Int?
    private var loadGeneration = 0
    private var shownTrackID: UUID?

    private var lyricsWindow: LyricsWindow { window as! LyricsWindow }
    private var panel: LyricsPanelView { lyricsWindow.panel }

    init(service: NavidromeService, playlistManager: PlaylistManager, audioEngine: AudioEngine) {
        self.service = service
        self.playlistManager = playlistManager
        self.audioEngine = audioEngine
        let w = LyricsWindow()
        super.init(window: w)
        w.delegate = self
        w.setFrameAutosaveName("Lyrics")
        w.panel.onClose = { [weak self] in self?.window?.close() }
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Presentation

    func toggle() {
        if window?.isVisible == true { window?.close() } else { present() }
    }

    func present() {
        guard let window else { return }
        if !window.isVisible, !window.setFrameUsingName("Lyrics") {
            // First open: dock to the right of the main window, top-aligned.
            if let main = NSApp.windows.first(where: { $0 is MainWindow }) {
                let origin = NSPoint(x: main.frame.maxX, y: main.frame.maxY - window.frame.height)
                window.setFrameOrigin(origin)
            } else {
                window.center()
            }
        }
        lyricsWindow.applyScale()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        refresh(force: true)
    }

    func recalculateSize() {
        lyricsWindow.recalculateSize()
    }

    // MARK: - Bindings

    private func bind() {
        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(force: false) }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.follow(time: time) }
            .store(in: &cancellables)

        service.$client
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)
    }

    // MARK: - Loading

    private func refresh(force: Bool) {
        guard window?.isVisible == true else { return }
        guard let track = playlistManager.currentTrack else {
            shownTrackID = nil
            show(lyrics: nil, header: "Nothing playing", status: "Play a track to see its lyrics.")
            return
        }
        if !force, track.id == shownTrackID { return }
        shownTrackID = track.id
        loadGeneration += 1
        let generation = loadGeneration
        let header = track.displayTitle

        guard service.isConfigured else {
            show(lyrics: nil, header: header,
                 status: "Connect to a Navidrome server (File → Navidrome Server…) to fetch lyrics.")
            return
        }
        show(lyrics: nil, header: header, status: "Looking up lyrics…")
        Task { @MainActor in
            do {
                let result = try await service.lyrics(for: track)
                guard generation == loadGeneration else { return }
                if let result, !result.lines.isEmpty {
                    show(lyrics: result, header: header, status: result.isSynced ? "Synced lyrics" : "Lyrics")
                } else {
                    show(lyrics: nil, header: header, status: "The server has no lyrics for this track.")
                }
            } catch {
                guard generation == loadGeneration else { return }
                let text = (error as? SubsonicError)?.localizedDescription ?? (error as NSError).localizedDescription
                show(lyrics: nil, header: header, status: "Couldn't fetch lyrics: \(text)")
            }
        }
    }

    private func show(lyrics: SubsonicLyrics?, header: String, status: String) {
        self.lyrics = lyrics
        lineStartsMs = (lyrics?.isSynced == true) ? lyrics!.lines.map { $0.start ?? 0 } : []
        currentLine = nil
        var lines: [LyricsDisplayLine] = [.header(header), .status(status)]
        if let lyrics, !lyrics.lines.isEmpty {
            lines.append(.blank)
            lines += lyrics.lines.enumerated().map { .lyric(index: $0.offset, text: $0.element.value) }
        }
        panel.currentLine = nil
        panel.lines = lines
        panel.scrollToTop()
        follow(time: audioEngine.currentTime)
    }

    private func follow(time: TimeInterval) {
        guard window?.isVisible == true, !lineStartsMs.isEmpty else { return }
        let idx = LyricsSync.currentLineIndex(startsMs: lineStartsMs, time: time)
        guard idx != currentLine else { return }
        currentLine = idx
        panel.currentLine = idx
        panel.scrollToCurrentLine()
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        lyricsWindow.applyScale()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        panel.needsDisplay = true
        refresh(force: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.needsDisplay = true
    }
}
