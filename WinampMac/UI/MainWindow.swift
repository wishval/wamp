import Cocoa
import Combine

class MainWindow: NSWindow {
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()
    private let stackView = NSStackView()
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

    init() {
        let rect = NSRect(x: 100, y: 100, width: WinampTheme.windowWidth, height: 510)
        super.init(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = WinampTheme.frameBackground
        hasShadow = true
        isReleasedWhenClosed = false

        setupStackView()
    }

    private func setupStackView() {
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(mainPlayerView)
        stackView.addArrangedSubview(equalizerView)
        stackView.addArrangedSubview(playlistView)

        contentView = NSView(frame: .zero)
        contentView!.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])

        // Section width constraints
        for view in [mainPlayerView, equalizerView, playlistView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: WinampTheme.windowWidth).isActive = true
        }

        mainPlayerView.heightAnchor.constraint(equalToConstant: WinampTheme.mainPlayerHeight).isActive = true
        equalizerView.heightAnchor.constraint(equalToConstant: WinampTheme.equalizerHeight).isActive = true
        playlistView.heightAnchor.constraint(greaterThanOrEqualToConstant: WinampTheme.playlistMinHeight).isActive = true

        recalculateSize()
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
    }

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager)

        // EQ/PL toggle callbacks
        mainPlayerView.onToggleEQ = { [weak self] in
            self?.showEqualizer.toggle()
        }
        mainPlayerView.onTogglePL = { [weak self] in
            self?.showPlaylist.toggle()
        }
    }
}
