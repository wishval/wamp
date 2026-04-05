import Cocoa
import Combine
import UniformTypeIdentifiers

class MainPlayerView: NSView {
    // Callbacks
    var onToggleEQ: (() -> Void)?
    var onTogglePL: (() -> Void)?

    var isEQActive: Bool {
        get { eqButton.isActive }
        set { eqButton.isActive = newValue }
    }
    var isPLActive: Bool {
        get { plButton.isActive }
        set { plButton.isActive = newValue }
    }

    // Subviews
    private let titleBar = TitleBarView()
    private let timeDisplay = SevenSegmentView()
    private let spectrumView = SpectrumView()
    private let lcdDisplay = LCDDisplay()
    private let seekSlider = WinampSlider(style: .seek)
    private let volumeSlider = WinampSlider(style: .volume)
    private let balanceSlider = WinampSlider(style: .balance)
    private let transportBar = TransportBar()

    // Toggle buttons
    private let shuffleButton = WinampButton(title: "", style: .toggle)
    private let repeatButton = WinampButton(title: "", style: .toggle)
    private let eqButton = WinampButton(title: "EQ", style: .toggle)
    private let plButton = WinampButton(title: "PL", style: .toggle)

    // Info labels
    private let bitrateLabel = NSTextField(labelWithString: "")
    private let sampleRateLabel = NSTextField(labelWithString: "")
    private let monoLabel = NSTextField(labelWithString: "mono")
    private let stereoLabel = NSTextField(labelWithString: "stereo")

    // Panel backgrounds
    private let leftPanel = NSView()
    private let rightPanel = NSView()

    // Play state indicator
    private let playIndicator = NSView()

    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        // Title bar
        titleBar.titleText = "WAMP"
        titleBar.showButtons = true
        titleBar.onClose = { NSApp.terminate(nil) }
        titleBar.onMinimize = { NSApp.mainWindow?.miniaturize(nil) }
        addSubview(titleBar)

        // Left display panel background
        leftPanel.wantsLayer = true
        leftPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(leftPanel)

        // Time display
        timeDisplay.wantsLayer = true
        addSubview(timeDisplay)

        // Spectrum
        spectrumView.wantsLayer = true
        addSubview(spectrumView)

        // Right display panel
        rightPanel.wantsLayer = true
        rightPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(rightPanel)

        // LCD (track title)
        addSubview(lcdDisplay)

        // Info labels
        for label in [bitrateLabel, sampleRateLabel, monoLabel, stereoLabel] {
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.font = WinampTheme.bitrateFont
            label.textColor = WinampTheme.greenDimText
            addSubview(label)
        }

        // Seek slider
        seekSlider.maxValue = 1
        addSubview(seekSlider)

        // Volume
        volumeSlider.value = 0.75
        volumeSlider.maxValue = 1
        addSubview(volumeSlider)

        // Balance
        balanceSlider.value = 0.5
        balanceSlider.minValue = 0
        balanceSlider.maxValue = 1
        addSubview(balanceSlider)

        // Transport bar
        addSubview(transportBar)

        // Shuffle button (crossing arrows icon)
        shuffleButton.drawIcon = { rect, active in
            let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.move(to: NSPoint(x: rect.minX + 1, y: rect.midY - 2))
            path.line(to: NSPoint(x: rect.midX, y: rect.midY + 2))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY - 2))
            path.stroke()
            let path2 = NSBezierPath()
            path2.lineWidth = 1.2
            path2.move(to: NSPoint(x: rect.minX + 1, y: rect.midY + 2))
            path2.line(to: NSPoint(x: rect.midX, y: rect.midY - 2))
            path2.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY + 2))
            path2.stroke()
        }
        addSubview(shuffleButton)

        // Repeat button (loop arrows icon)
        repeatButton.drawIcon = { rect, active in
            let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            // Top arrow going right
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.midY + 1))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 1))
            path.stroke()
            // Arrow head right
            let arr1 = NSBezierPath()
            arr1.lineWidth = 1.2
            arr1.move(to: NSPoint(x: rect.maxX - 4, y: rect.midY + 3))
            arr1.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 1))
            arr1.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY - 1))
            arr1.stroke()
            // Bottom arrow going left
            let path2 = NSBezierPath()
            path2.lineWidth = 1.2
            path2.move(to: NSPoint(x: rect.maxX - 2, y: rect.midY - 2))
            path2.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 2))
            path2.stroke()
            // Arrow head left
            let arr2 = NSBezierPath()
            arr2.lineWidth = 1.2
            arr2.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            arr2.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 2))
            arr2.line(to: NSPoint(x: rect.minX + 4, y: rect.midY - 4))
            arr2.stroke()
        }
        addSubview(repeatButton)

        // EQ / PL buttons
        eqButton.isActive = true
        plButton.isActive = true
        addSubview(eqButton)
        addSubview(plButton)

        // Button actions
        shuffleButton.onClick = { [weak self] in
            self?.playlistManager?.toggleShuffle()
        }
        repeatButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            let next = RepeatMode(rawValue: (engine.repeatMode.rawValue + 1) % 3) ?? .off
            engine.repeatMode = next
        }
        eqButton.onClick = { [weak self] in self?.onToggleEQ?() }
        plButton.onClick = { [weak self] in self?.onTogglePL?() }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 3

        // Title bar
        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let contentTop = titleBar.frame.minY - pad
        let leftPanelW: CGFloat = 110
        let rightPanelX = leftPanelW + pad + pad
        let rightPanelW = w - rightPanelX - pad
        let displayH: CGFloat = 56

        // Left panel (black bg)
        leftPanel.frame = NSRect(x: pad, y: contentTop - displayH, width: leftPanelW, height: displayH)

        // Time + play state top row (inside left panel area)
        let timeH: CGFloat = 26
        let timeSpecGap: CGFloat = 6
        let specH = displayH - timeH - timeSpecGap - 2
        timeDisplay.frame = NSRect(x: pad + 2, y: contentTop - timeH - 2, width: leftPanelW - 4, height: timeH)
        spectrumView.frame = NSRect(x: pad + 2, y: contentTop - displayH + 2, width: leftPanelW - 4, height: specH)

        // Right panel (black bg)
        rightPanel.frame = NSRect(x: rightPanelX, y: contentTop - displayH, width: rightPanelW, height: displayH)

        // LCD display
        lcdDisplay.frame = NSRect(x: rightPanelX + 4, y: contentTop - 22, width: rightPanelW - 8, height: 16)

        // Bitrate info
        bitrateLabel.frame = NSRect(x: rightPanelX + 4, y: contentTop - 42, width: 30, height: 12)
        sampleRateLabel.frame = NSRect(x: rightPanelX + 40, y: contentTop - 42, width: 30, height: 12)
        monoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 50, y: contentTop - 42, width: 22, height: 12)
        stereoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 28, y: contentTop - 42, width: 28, height: 12)

        let controlsTop = contentTop - displayH - 3

        // Seek bar
        seekSlider.frame = NSRect(x: pad, y: controlsTop - 10, width: w - 2 * pad, height: 10)

        // Volume + Balance
        let sliderTop = controlsTop - 14
        let halfW = (w - 2 * pad - 4) / 2
        volumeSlider.frame = NSRect(x: pad, y: sliderTop - 8, width: halfW, height: 8)
        balanceSlider.frame = NSRect(x: pad + halfW + 4, y: sliderTop - 8, width: halfW, height: 8)

        // Transport row
        let transportTop = sliderTop - 12
        transportBar.frame = NSRect(x: pad, y: transportTop - 18, width: transportBar.intrinsicContentSize.width, height: 18)

        // Right side: shuffle, repeat, EQ, PL
        let btnH: CGFloat = 16
        let btnW: CGFloat = 20
        let toggleX = w - pad - (btnW * 4 + 3)
        let toggleY = transportTop - btnH - 1

        shuffleButton.frame = NSRect(x: toggleX, y: toggleY, width: btnW, height: btnH)
        repeatButton.frame = NSRect(x: toggleX + btnW + 1, y: toggleY, width: btnW, height: btnH)
        eqButton.frame = NSRect(x: toggleX + (btnW + 1) * 2, y: toggleY, width: btnW, height: btnH)
        plButton.frame = NSRect(x: toggleX + (btnW + 1) * 3, y: toggleY, width: btnW, height: btnH)
    }

    // MARK: - Binding
    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager

        // Time
        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.timeDisplay.timeInSeconds = time }
            .store(in: &cancellables)

        // Spectrum
        audioEngine.$spectrumData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.spectrumView.spectrumData = data }
            .store(in: &cancellables)

        // Track info
        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTrackInfo() }
            .store(in: &cancellables)

        // Seek slider
        audioEngine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in self?.seekSlider.maxValue = Float(dur) }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard self?.seekSlider.window != nil else { return }
                self?.seekSlider.value = Float(time)
            }
            .store(in: &cancellables)

        seekSlider.onChange = { [weak audioEngine] value in
            audioEngine?.seek(to: TimeInterval(value))
        }

        // Volume
        volumeSlider.value = audioEngine.volume
        volumeSlider.onChange = { [weak audioEngine] value in
            audioEngine?.volume = value
        }

        // Balance
        balanceSlider.value = (audioEngine.balance + 1) / 2 // convert -1..1 to 0..1
        balanceSlider.onChange = { [weak audioEngine] value in
            audioEngine?.balance = value * 2 - 1 // convert 0..1 to -1..1
        }

        // Transport
        transportBar.onPrevious = { [weak playlistManager] in playlistManager?.playPrevious() }
        transportBar.onPlay = { [weak audioEngine] in audioEngine?.play() }
        transportBar.onPause = { [weak audioEngine] in audioEngine?.pause() }
        transportBar.onStop = { [weak audioEngine] in audioEngine?.stop() }
        transportBar.onNext = { [weak playlistManager] in playlistManager?.playNext() }
        transportBar.onEject = { [weak self] in self?.showOpenFilePanel() }

        // Play state
        audioEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.transportBar.playButton.isActive = playing
            }
            .store(in: &cancellables)

        // Shuffle state
        playlistManager.$isShuffled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shuffled in
                self?.shuffleButton.isActive = shuffled
            }
            .store(in: &cancellables)

        // Repeat state
        audioEngine.$repeatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.repeatButton.isActive = mode != .off
            }
            .store(in: &cancellables)
    }

    private func updateTrackInfo() {
        guard let track = playlistManager?.currentTrack else {
            lcdDisplay.text = ""
            bitrateLabel.stringValue = ""
            sampleRateLabel.stringValue = ""
            return
        }
        let index = (playlistManager?.currentIndex ?? 0) + 1
        lcdDisplay.text = "\(index). \(track.displayTitle) (\(track.formattedDuration))"
        bitrateLabel.stringValue = "\(track.bitrate > 0 ? "\(track.bitrate)" : "---")"
        bitrateLabel.textColor = WinampTheme.greenBright
        sampleRateLabel.stringValue = "\(track.sampleRate > 0 ? "\(track.sampleRate / 1000)" : "--")"
        sampleRateLabel.textColor = WinampTheme.greenBright
        stereoLabel.textColor = track.isStereo ? WinampTheme.greenBright : WinampTheme.greenDimText
        monoLabel.textColor = track.isStereo ? WinampTheme.greenDimText : WinampTheme.greenBright
    }

    private func showOpenFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                for url in panel.urls {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        await self?.playlistManager?.addFolder(url)
                    } else {
                        await self?.playlistManager?.addURLs([url])
                    }
                }
            }
        }
    }
}
