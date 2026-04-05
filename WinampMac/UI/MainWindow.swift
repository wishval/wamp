import Cocoa
import Combine

class MainWindow: NSWindow {
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    var showEqualizer: Bool = true {
        didSet {
            equalizerView.isHidden = !showEqualizer
            mainPlayerView.isEQActive = showEqualizer
            recalculateSize()
        }
    }

    var showPlaylist: Bool = true {
        didSet {
            playlistView.isHidden = !showPlaylist
            mainPlayerView.isPLActive = showPlaylist
            recalculateSize()
        }
    }

    var alwaysOnTop: Bool = true {
        didSet {
            level = alwaysOnTop ? .floating : .normal
            mainPlayerView.isPinned = alwaysOnTop
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let height = WinampTheme.mainPlayerHeight + WinampTheme.equalizerHeight + WinampTheme.playlistMinHeight
        let rect = NSRect(x: 100, y: 100, width: WinampTheme.windowWidth, height: height)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = false
        level = .floating
        backgroundColor = WinampTheme.frameBackground
        isOpaque = true
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: WinampTheme.windowWidth, height: height))
        container.wantsLayer = true
        contentView = container

        container.addSubview(mainPlayerView)
        container.addSubview(equalizerView)
        container.addSubview(playlistView)

        layoutSections()
    }

    private func layoutSections() {
        let w = WinampTheme.windowWidth
        let totalHeight = frame.height
        var y = totalHeight

        // Main player — always at top
        y -= WinampTheme.mainPlayerHeight
        mainPlayerView.frame = NSRect(x: 0, y: y, width: w, height: WinampTheme.mainPlayerHeight)

        // Equalizer — below player
        if showEqualizer {
            y -= WinampTheme.equalizerHeight
            equalizerView.frame = NSRect(x: 0, y: y, width: w, height: WinampTheme.equalizerHeight)
        }

        // Playlist — fills remaining space
        if showPlaylist {
            let playlistHeight = y
            playlistView.frame = NSRect(x: 0, y: 0, width: w, height: playlistHeight)
        }
    }

    func recalculateSize() {
        var height: CGFloat = WinampTheme.mainPlayerHeight
        if showEqualizer { height += WinampTheme.equalizerHeight }
        if showPlaylist { height += WinampTheme.playlistMinHeight }

        let origin = frame.origin
        let newFrame = NSRect(
            x: origin.x,
            y: origin.y + frame.height - height,
            width: WinampTheme.windowWidth,
            height: height
        )
        setFrame(newFrame, display: true, animate: true)

        contentView?.frame = NSRect(x: 0, y: 0, width: WinampTheme.windowWidth, height: height)
        layoutSections()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            NSApp.sendAction(#selector(AppDelegate.togglePlayPause), to: nil, from: self)
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            let seekStep: TimeInterval = 5
            switch event.keyCode {
            case 123: // left arrow
                if let engine = audioEngine {
                    engine.seek(to: max(0, engine.currentTime - seekStep))
                }
                return
            case 124: // right arrow
                if let engine = audioEngine {
                    engine.seek(to: min(engine.duration, engine.currentTime + seekStep))
                }
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        self.audioEngine = audioEngine
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager)

        mainPlayerView.onToggleEQ = { [weak self] in
            self?.showEqualizer.toggle()
        }
        mainPlayerView.onTogglePL = { [weak self] in
            self?.showPlaylist.toggle()
        }
        mainPlayerView.onTogglePin = { [weak self] in
            self?.alwaysOnTop.toggle()
        }
    }
}
