import AppKit
import Combine

/// Floating "Lyrics" window fed by the connected Navidrome server. Synced
/// (LRC/SYLT) lyrics highlight the current line and keep it centred as the
/// track plays; plain lyrics are shown as text. Colours follow the active
/// skin's playlist palette so it sits next to the player naturally.
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

    private let headerLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    init(service: NavidromeService, playlistManager: PlaylistManager, audioEngine: AudioEngine) {
        self.service = service
        self.playlistManager = playlistManager
        self.audioEngine = audioEngine
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Lyrics"
        w.minSize = NSSize(width: 260, height: 240)
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("Lyrics")
        super.init(window: w)
        w.delegate = self
        buildLayout()
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
        if !window.isVisible, !window.setFrameUsingName("Lyrics") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        refresh(force: true)
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let contentView = window?.contentView else { return }

        headerLabel.font = NSFont.boldSystemFont(ofSize: 13)
        headerLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true

        let top = NSStackView(views: [headerLabel, statusLabel])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 2
        top.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 6, right: 14)
        top.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(top)
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: contentView.topAnchor),
            top.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerLabel.widthAnchor.constraint(equalTo: top.widthAnchor, constant: -28),
            statusLabel.widthAnchor.constraint(equalTo: top.widthAnchor, constant: -28),
            scrollView.topAnchor.constraint(equalTo: top.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        applySkinColors()
    }

    private func applySkinColors() {
        let style = WinampTheme.provider.playlistStyle
        textView.backgroundColor = style.normalBG
        scrollView.backgroundColor = style.normalBG
        window?.backgroundColor = style.normalBG
        headerLabel.textColor = style.current
        statusLabel.textColor = style.normal.withAlphaComponent(0.7)
        render()
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

        SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySkinColors() }
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
                    let status = result.isSynced ? "Synced lyrics" : "Lyrics"
                    show(lyrics: result, header: header, status: status)
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
        headerLabel.stringValue = header
        statusLabel.stringValue = status
        render()
        follow(time: audioEngine.currentTime)
    }

    private func follow(time: TimeInterval) {
        guard window?.isVisible == true, !lineStartsMs.isEmpty else { return }
        let idx = LyricsSync.currentLineIndex(startsMs: lineStartsMs, time: time)
        guard idx != currentLine else { return }
        currentLine = idx
        render()
        scrollToCurrentLine()
    }

    // MARK: - Rendering

    private func render() {
        guard let storage = textView.textStorage else { return }
        let style = WinampTheme.provider.playlistStyle
        let fontSize: CGFloat = 14
        let baseFont = NSFont(name: style.font, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 2

        let out = NSMutableAttributedString()
        guard let lyrics else {
            storage.setAttributedString(out)
            return
        }
        let synced = !lineStartsMs.isEmpty
        for (i, line) in lyrics.lines.enumerated() {
            let isCurrent = synced && i == currentLine
            let dim = synced && currentLine != nil && !isCurrent
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isCurrent ? boldFont : baseFont,
                .foregroundColor: isCurrent ? style.current : style.normal.withAlphaComponent(dim ? 0.55 : 0.9),
                .paragraphStyle: paragraph,
            ]
            let text = line.value.isEmpty ? " " : line.value
            out.append(NSAttributedString(string: text + "\n", attributes: attrs))
        }
        storage.setAttributedString(out)
    }

    private func scrollToCurrentLine() {
        guard let idx = currentLine, let lyrics, idx < lyrics.lines.count,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        // Character offset of the line: lengths of all previous lines + newlines.
        var location = 0
        for i in 0..<idx {
            let text = lyrics.lines[i].value.isEmpty ? " " : lyrics.lines[i].value
            location += (text as NSString).length + 1
        }
        let text = lyrics.lines[idx].value.isEmpty ? " " : lyrics.lines[idx].value
        let range = NSRange(location: location, length: (text as NSString).length)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.y += textView.textContainerInset.height
        let visible = scrollView.contentView.bounds
        let targetY = max(0, rect.midY - visible.height / 2)
        let maxY = max(0, textView.bounds.height - visible.height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: min(targetY, maxY)))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        refresh(force: false)
    }
}
