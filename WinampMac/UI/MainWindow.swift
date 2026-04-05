import Cocoa
import Combine

class MainWindow: NSWindow {
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()
    private var cancellables = Set<AnyCancellable>()

    var showEqualizer: Bool = true {
        didSet {
            equalizerView.isHidden = !showEqualizer
            recalculateSize()
        }
    }

    var showPlaylist: Bool = true {
        didSet {
            playlistView.isHidden = !showPlaylist
            recalculateSize()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let height = WinampTheme.mainPlayerHeight + WinampTheme.equalizerHeight + WinampTheme.playlistMinHeight
        let rect = NSRect(x: 100, y: 100, width: WinampTheme.windowWidth, height: height)
        super.init(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
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

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager)

        mainPlayerView.onToggleEQ = { [weak self] in
            self?.showEqualizer.toggle()
        }
        mainPlayerView.onTogglePL = { [weak self] in
            self?.showPlaylist.toggle()
        }
    }
}
