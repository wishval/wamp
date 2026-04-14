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
    private let bitrateUnitLabel = NSTextField(labelWithString: "kbps")
    private let sampleRateUnitLabel = NSTextField(labelWithString: "khz")
    private let monoLabel = NSTextField(labelWithString: "mono")
    private let stereoLabel = NSTextField(labelWithString: "stereo")

    // Panel backgrounds
    private let leftPanel = NSView()
    private let rightPanel = NSView()


    // Play state indicator
    private let playIndicator = PlayStateIndicator()

    // Invisible click hit-zones for close/minimize/menu when skinned (replace hidden titleBar)
    private let closeHitZone = NSView()
    private let minimizeHitZone = NSView()
    private let menuHitZone = NSView()
    // Click target over the Nullsoft logo baked into main.bmp, right of the repeat button.
    private let githubHitZone = NSView()

    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?

    // Window dragging state for skinned mode (titleBar is hidden)
    private var dragOrigin: NSPoint?

    /// View height in logical (pre-scale) points. Winamp's main.bmp is exactly
    /// 116 px tall, so when a skin is active we shrink the view to match and
    /// lay out subviews at the sprite's native pixel coordinates. When no skin
    /// is loaded, we use Wamp's original 126 px layout.
    var desiredHeight: CGFloat {
        WinampTheme.skinIsActive ? 116 : WinampTheme.mainPlayerHeight
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySkinVisibility()
                self?.needsDisplay = true
                self?.needsLayout = true
            }
        applySkinVisibility()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        // Title bar
        titleBar.titleText = "WAMP"
        titleBar.showButtons = true
        titleBar.onClose = { NSApp.terminate(nil) }
        titleBar.onMinimize = { [weak self] in self?.window?.miniaturize(nil) }
        titleBar.onMenuClick = { [weak self] in self?.showWindowMenu() }
        addSubview(titleBar)

        // Left display panel background
        leftPanel.wantsLayer = true
        leftPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(leftPanel)


        // Time display
        timeDisplay.wantsLayer = true
        addSubview(timeDisplay)
        addSubview(playIndicator)

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
        for label in [bitrateLabel, sampleRateLabel, bitrateUnitLabel, sampleRateUnitLabel, monoLabel, stereoLabel] {
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
        repeatButton.drawIcon = { [weak self] rect, active in
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
            // Draw "1" for single-track repeat mode
            if self?.audioEngine?.repeatMode == .track {
                let font = NSFont.monospacedSystemFont(ofSize: 5.5, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                let str = "1"
                let size = str.size(withAttributes: attrs)
                let point = NSPoint(
                    x: rect.maxX - size.width + 2,
                    y: rect.minY - 3
                )
                str.draw(at: point, withAttributes: attrs)
            }
        }
        addSubview(repeatButton)

        // EQ / PL buttons
        eqButton.isActive = true
        plButton.isActive = true
        addSubview(eqButton)
        addSubview(plButton)

        // Wire skin sprite keys for the four toggle buttons
        shuffleButton.spriteKeyProvider = { active, pressed in .shuffleButton(active: active, pressed: pressed) }
        repeatButton.spriteKeyProvider  = { active, pressed in .repeatButton(active: active, pressed: pressed) }
        eqButton.spriteKeyProvider      = { active, pressed in .eqToggleButton(active: active, pressed: pressed) }
        plButton.spriteKeyProvider      = { active, pressed in .plToggleButton(active: active, pressed: pressed) }

        // Button actions
        shuffleButton.onClick = { [weak self] in
            self?.playlistManager?.shuffleTracks()
        }
        repeatButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            let next = RepeatMode(rawValue: (engine.repeatMode.rawValue + 1) % 3) ?? .off
            engine.repeatMode = next
        }
        eqButton.onClick = { [weak self] in self?.onToggleEQ?() }
        plButton.onClick = { [weak self] in self?.onTogglePL?() }

        // Click hit-zones for close/minimize/menu when skinned (titleBar is hidden
        // then, so we need invisible NSViews at the locations where main.bmp paints
        // these buttons so the user can still interact with them).
        addSubview(closeHitZone)
        addSubview(minimizeHitZone)
        addSubview(menuHitZone)
        addSubview(githubHitZone)
        let closeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedClose))
        closeHitZone.addGestureRecognizer(closeClick)
        let minimizeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedMinimize))
        minimizeHitZone.addGestureRecognizer(minimizeClick)
        let menuClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedMenu))
        menuHitZone.addGestureRecognizer(menuClick)
        let githubClick = NSClickGestureRecognizer(target: self, action: #selector(handleOpenGitHub))
        githubHitZone.addGestureRecognizer(githubClick)
    }

    @objc private func handleSkinnedClose() { NSApp.terminate(nil) }
    @objc private func handleSkinnedMinimize() { window?.miniaturize(nil) }
    @objc private func handleSkinnedMenu() { showWindowMenu() }
    @objc private func handleOpenGitHub() {
        if let url = URL(string: "https://github.com/wishval/wamp") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Hides NSTextField labels and helper NSViews whose visual content is baked
    /// into main.bmp / monoster.bmp / text.bmp when a skin is loaded. See spec §8.
    private func applySkinVisibility() {
        let active = WinampTheme.skinIsActive
        titleBar.isHidden = active
        titleBar.showMenuIcon = !active
        leftPanel.isHidden = active
        rightPanel.isHidden = active
        bitrateLabel.isHidden = active
        sampleRateLabel.isHidden = active
        bitrateUnitLabel.isHidden = active
        sampleRateUnitLabel.isHidden = active
        monoLabel.isHidden = active
        stereoLabel.isHidden = active
        playIndicator.isHidden = active
        closeHitZone.isHidden = !active
        minimizeHitZone.isHidden = !active
        menuHitZone.isHidden = !active
        githubHitZone.isHidden = !active
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard WinampTheme.skinIsActive else { return }
        drawSkinned()
    }

    private func drawSkinned() {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        // View is resized to 116 px (native main.bmp height) when skinned,
        // so the sprite fills bounds exactly and sub-sprite coordinates are
        // in the same space as Webamp's main-window.css.
        let mainHeight: CGFloat = bounds.height
        if let bg = WinampTheme.sprite(.mainBackground) {
            bg.draw(in: bounds)
        }

        // Title bar overlay (main.bmp leaves the top 14px empty for this).
        // Webamp y=0..14 (top-down) → AppKit y = mainHeight - 14.
        let isActive = window?.isKeyWindow ?? true
        if let tb = WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive) {
            tb.draw(in: NSRect(x: 0, y: mainHeight - 14, width: bounds.width, height: 14))
        }

        // Mono / stereo sprites at fixed Webamp coordinates.
        // Webamp positions (top-down): mono at (212, 41) 27w, stereo at (239, 41) 29w, 12 px tall.
        // Convert to AppKit (bottom-up): y_appkit = mainHeight - 41 - 12
        let isStereo = playlistManager?.currentTrack?.isStereo ?? false
        let monoY: CGFloat = mainHeight - 41 - 12
        if let monoSprite = WinampTheme.sprite(.mono(active: !isStereo)) {
            monoSprite.draw(in: NSRect(x: 212, y: monoY, width: 27, height: 12))
        }
        if let stereoSprite = WinampTheme.sprite(.stereo(active: isStereo)) {
            stereoSprite.draw(in: NSRect(x: 239, y: monoY, width: 29, height: 12))
        }

        // Bitrate / sample rate digits via text.bmp.
        // The "kbps" and "khz" *labels* are baked into main.bmp, so only draw the numbers.
        // Webamp positions (top-down): bitrate at (111, 43), sample rate at (156, 43).
        // y_appkit = mainHeight - 43 - 6 (glyphs are 6 px tall) = 67
        if let textSheet = WinampTheme.provider.textSheet,
           let track = playlistManager?.currentTrack {
            let textY: CGFloat = mainHeight - 43 - 6
            let bitrateStr = track.bitrate > 0 ? String(format: "%3d", track.bitrate) : "   "
            let sampleStr = track.sampleRate > 0 ? String(format: "%2d", track.sampleRate / 1000) : "  "
            TextSpriteRenderer.draw(bitrateStr, at: NSPoint(x: 111, y: textY), sheet: textSheet)
            TextSpriteRenderer.draw(sampleStr,  at: NSPoint(x: 156, y: textY), sheet: textSheet)
        }
    }

    override func layout() {
        super.layout()
        if WinampTheme.skinIsActive {
            layoutSkinned()
        } else {
            layoutUnskinned()
        }
    }

    /// Exact Winamp 2.x pixel coordinates, ported from Webamp's main-window.css.
    /// View bounds are 275×116 in this mode; Y is converted from Webamp (top-down)
    /// to AppKit (bottom-up) as: y_appkit = 116 - y_webamp - height.
    private func layoutSkinned() {
        let h: CGFloat = bounds.height  // 116

        // Title bar (hidden, but keep frame valid)
        titleBar.frame = NSRect(x: 0, y: h - 16, width: bounds.width, height: 16)

        // Close / minimize hit-zones — webamp close(264,3,9×9), min(244,3,9×9)
        let hitSize: CGFloat = 11
        let hitY = h - 3 - hitSize
        closeHitZone.frame = NSRect(x: 263, y: hitY, width: hitSize, height: hitSize)
        minimizeHitZone.frame = NSRect(x: 243, y: hitY, width: hitSize, height: hitSize)

        // Menu icon hit-zone — webamp top-left icon at (6, 3, 9×9)
        menuHitZone.frame = NSRect(x: 6, y: hitY, width: hitSize, height: hitSize)

        // Hidden panels — collapse
        leftPanel.frame = .zero
        rightPanel.frame = .zero
        for label in [bitrateLabel, sampleRateLabel, bitrateUnitLabel, sampleRateUnitLabel, monoLabel, stereoLabel] {
            label.frame = .zero
        }

        // 7-segment time (webamp #time at 39,26,59,13 → y=77; widened 1px to fit last digit)
        timeDisplay.frame = NSRect(x: 39, y: 77, width: 60, height: 13)
        // Spectrum / visualizer (webamp 24,43,76,16 → y=57)
        spectrumView.frame = NSRect(x: 24, y: 57, width: 76, height: 16)
        // Scrolling track-title marquee (webamp 111,27,154,6 → y=83)
        lcdDisplay.frame = NSRect(x: 111, y: 83, width: 154, height: 6)

        // Seek/posbar (webamp 16,72,248,10 → y=34)
        seekSlider.frame = NSRect(x: 16, y: 34, width: 248, height: 10)

        // Volume / balance (webamp 107/177,57,68/38,13 → y=46)
        volumeSlider.frame = NSRect(x: 107, y: 46, width: 68, height: 13)
        balanceSlider.frame = NSRect(x: 177, y: 46, width: 38, height: 13)

        // EQ / PL toggle buttons (webamp 219/242,58,23,12 → y=46)
        eqButton.frame = NSRect(x: 219, y: 46, width: 23, height: 12)
        plButton.frame = NSRect(x: 242, y: 46, width: 23, height: 12)

        // Transport (cbuttons, webamp 16,88,*,18 → y=10). Width = sum of 5 buttons + eject.
        transportBar.frame = NSRect(x: 16, y: 10, width: transportBar.intrinsicContentSize.width, height: 18)

        // Shuffle / repeat (webamp 164,89,47,15 and 210,89,28,15 → y=12)
        shuffleButton.frame = NSRect(x: 164, y: 12, width: 47, height: 15)
        repeatButton.frame = NSRect(x: 210, y: 12, width: 28, height: 15)

        // Nullsoft logo (baked into main.bmp at ~249,89,18,15) — repurposed as a link to the repo.
        githubHitZone.frame = NSRect(x: 249, y: 12, width: 18, height: 15)
    }

    private func layoutUnskinned() {
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
        let timeH: CGFloat = 23
        let timeSpecGap: CGFloat = 6
        let specH = displayH - timeH - timeSpecGap - 2

        let indicatorW: CGFloat = 11
        let indicatorGap: CGFloat = 3
        let indicatorLeftInset: CGFloat = 8
        playIndicator.frame = NSRect(x: pad + indicatorLeftInset, y: contentTop - timeH + (timeH - indicatorW) / 2 - 2, width: indicatorW, height: indicatorW)
        let timeX = pad + indicatorLeftInset + indicatorW + indicatorGap
        timeDisplay.frame = NSRect(x: timeX, y: contentTop - timeH - 2, width: leftPanelW - (timeX - pad) - 2, height: timeH)
        spectrumView.frame = NSRect(x: pad + 2, y: contentTop - displayH + 2, width: leftPanelW - 4, height: specH)


        // Right panel (black bg)
        rightPanel.frame = NSRect(x: rightPanelX, y: contentTop - displayH, width: rightPanelW, height: displayH)

        // LCD display
        lcdDisplay.frame = NSRect(x: rightPanelX + 4, y: contentTop - 22, width: rightPanelW - 8, height: 16)

        // Bitrate info
        bitrateLabel.frame = NSRect(x: rightPanelX + 4, y: contentTop - 42, width: 22, height: 12)
        bitrateUnitLabel.frame = NSRect(x: rightPanelX + 22, y: contentTop - 42, width: 22, height: 12)
        sampleRateLabel.frame = NSRect(x: rightPanelX + 48, y: contentTop - 42, width: 18, height: 12)
        sampleRateUnitLabel.frame = NSRect(x: rightPanelX + 63, y: contentTop - 42, width: 20, height: 12)
        monoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 50, y: contentTop - 42, width: 22, height: 12)
        stereoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 28, y: contentTop - 42, width: 28, height: 12)

        let controlsTop = contentTop - displayH - 3

        // Seek bar
        seekSlider.frame = NSRect(x: pad, y: controlsTop - 10, width: w - 2 * pad, height: 10)

        // Volume + Balance (balance ~half the width of volume) with a right-side EQ/PL strip
        let sliderTop = controlsTop - 14
        let eqPlBtnW: CGFloat = 22
        let eqPlBtnH: CGFloat = 12
        let eqPlGap: CGFloat = 2
        let eqPlStripW = eqPlBtnW * 2 + eqPlGap
        let slidersRightEdge = w - pad - eqPlStripW - 4
        let slidersAvailW = slidersRightEdge - pad
        let sliderGap: CGFloat = 4
        let volumeW = floor((slidersAvailW - sliderGap) * 2 / 3)
        let balanceW = slidersAvailW - sliderGap - volumeW
        volumeSlider.frame = NSRect(x: pad, y: sliderTop - 8, width: volumeW, height: 8)
        balanceSlider.frame = NSRect(x: pad + volumeW + sliderGap, y: sliderTop - 8, width: balanceW, height: 8)

        // EQ / PL right-aligned on the slider row, vertically centered on the 8px slider strip
        let eqPlY = sliderTop - 8 + (8 - eqPlBtnH) / 2
        eqButton.frame = NSRect(x: w - pad - eqPlStripW, y: eqPlY, width: eqPlBtnW, height: eqPlBtnH)
        plButton.frame = NSRect(x: w - pad - eqPlBtnW,   y: eqPlY, width: eqPlBtnW, height: eqPlBtnH)

        // Transport row
        let transportTop = sliderTop - 12
        transportBar.frame = NSRect(x: pad, y: transportTop - 18, width: transportBar.intrinsicContentSize.width, height: 18)

        // Right side of transport row: shuffle, repeat only (EQ/PL moved up to the slider row)
        let btnH: CGFloat = 16
        let btnW: CGFloat = 20
        let toggleX = w - pad - (btnW * 2 + 1)
        let toggleY = transportTop - btnH - 1

        shuffleButton.frame = NSRect(x: toggleX, y: toggleY, width: btnW, height: btnH)
        repeatButton.frame = NSRect(x: toggleX + btnW + 1, y: toggleY, width: btnW, height: btnH)

        // Click hit-zones at the locations where main.bmp paints close/minimize.
        // Webamp positions (top-down): close at (264, 3), minimize at (244, 3), 9×9.
        // y_appkit = 116 - 3 - 9 = 104. Made slightly larger for easier clicking.
        let hitSize: CGFloat = 11
        let hitY: CGFloat = 116 - 3 - hitSize
        closeHitZone.frame = NSRect(x: 263, y: hitY, width: hitSize, height: hitSize)
        minimizeHitZone.frame = NSRect(x: 243, y: hitY, width: hitSize, height: hitSize)
        menuHitZone.frame = .zero
        githubHitZone.frame = .zero
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
            .sink { [weak self] _ in
                self?.updateTrackInfo()
                // Skinned overlay reads track.bitrate / .sampleRate in drawSkinned —
                // force a redraw so kbps/khz update on track change.
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        // Seek slider
        audioEngine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in self?.seekSlider.maxValue = Float(dur) }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, self.seekSlider.window != nil else { return }
                guard !self.seekSlider.isUserInteracting else { return }
                self.seekSlider.value = Float(time)
            }
            .store(in: &cancellables)

        seekSlider.onChange = { [weak audioEngine] value in
            audioEngine?.seek(to: TimeInterval(value))
        }

        // Volume
        volumeSlider.value = audioEngine.volume
        volumeSlider.onChange = { [weak self, weak audioEngine] value in
            audioEngine?.volume = value
            self?.lcdDisplay.showOverlay("Volume: \(Int(round(value * 100)))%")
        }

        // Balance
        balanceSlider.value = (audioEngine.balance + 1) / 2 // convert -1..1 to 0..1
        balanceSlider.onChange = { [weak audioEngine] value in
            audioEngine?.balance = value * 2 - 1 // convert 0..1 to -1..1
        }

        // Transport
        transportBar.onPrevious = { [weak playlistManager] in playlistManager?.playPrevious() }
        transportBar.onPlay = { [weak self] in
            guard let self, let engine = self.audioEngine else { return }
            if engine.playState == .stopped,
               let track = self.playlistManager?.currentTrack {
                engine.loadAndPlay(url: track.url)
            } else {
                engine.play()
            }
        }
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

        audioEngine.$playState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playIndicator.state = state
            }
            .store(in: &cancellables)

        // Repeat state
        audioEngine.$repeatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.repeatButton.isActive = mode != .off
                self?.repeatButton.needsDisplay = true
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

    private func showWindowMenu() {
        let menu = NSMenu()

        // Helper: build an item dispatched through the responder chain.
        func item(_ title: String, _ selectorName: String, state: NSControl.StateValue = .off) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: Selector((selectorName)), keyEquivalent: "")
            mi.target = nil
            mi.state = state
            return mi
        }

        menu.addItem(item("About Wamp", "showAboutPanel"))
        menu.addItem(.separator())

        // File
        menu.addItem(item("Open File…", "openFileAction"))
        menu.addItem(item("Open Folder…", "openFolderAction"))
        menu.addItem(.separator())

        // Controls
        menu.addItem(item("Play / Pause", "togglePlayPause"))
        menu.addItem(item("Stop", "stopAction"))
        menu.addItem(item("Next", "nextAction"))
        menu.addItem(item("Previous", "prevAction"))
        menu.addItem(.separator())
        menu.addItem(item("Shuffle", "toggleShuffle"))
        menu.addItem(item("Repeat", "toggleRepeat"))
        menu.addItem(.separator())

        // View
        menu.addItem(item("Show Equalizer", "toggleEQ",
                          state: isEQActive ? .on : .off))
        menu.addItem(item("Show Playlist", "togglePL",
                          state: isPLActive ? .on : .off))
        menu.addItem(item("Always on Top", "toggleAlwaysOnTop",
                          state: (window?.level == .floating) ? .on : .off))
        menu.addItem(item("Double Size", "toggleDoubleSize",
                          state: WinampTheme.scale > WinampTheme.baseScale + 0.01 ? .on : .off))
        menu.addItem(.separator())

        // Skin
        menu.addItem(item("Load Skin…", "loadSkinAction"))
        menu.addItem(item("Unload Skin", "unloadSkinAction"))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Wamp",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))

        let anchor = NSPoint(x: titleBar.frame.minX, y: titleBar.frame.minY)
        menu.popUp(positioning: nil, at: anchor, in: self)
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

    // MARK: - Window dragging (skinned mode)
    // When skinned, TitleBarView is hidden so we handle dragging from the title
    // bar area (top 14px of the 116px skin) directly in MainPlayerView.

    override func mouseDown(with event: NSEvent) {
        guard WinampTheme.skinIsActive else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let titleBarMinY = bounds.height - 14
        guard point.y >= titleBarMinY else { super.mouseDown(with: event); return }
        // Don't drag from close/minimize/menu hit-zones
        if closeHitZone.frame.contains(point) || minimizeHitZone.frame.contains(point)
            || menuHitZone.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else { return }
        let current = event.locationInWindow
        var frame = win.frame
        frame.origin.x += current.x - origin.x
        frame.origin.y += current.y - origin.y
        win.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        super.mouseUp(with: event)
    }
}
