import Cocoa
import Combine

struct EQPreset {
    let name: String
    let bands: [Float]

    nonisolated static let presets: [EQPreset] = [
        EQPreset(name: "Flat",                       bands: [ 0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0]),
        EQPreset(name: "Classical",                  bands: [ 0.0,  0.0,  0.0,  0.0,  0.0,  0.0, -8.1, -8.1, -8.1,-10.6]),
        EQPreset(name: "Club",                       bands: [ 0.0,  0.0,  3.1,  5.6,  5.6,  5.6,  3.1,  0.0,  0.0,  0.0]),
        EQPreset(name: "Dance",                      bands: [ 9.4,  6.9,  1.9, -0.6, -0.6, -6.9, -8.1, -8.1, -0.6, -0.6]),
        EQPreset(name: "Laptop speakers/headphones", bands: [ 4.4, 10.6,  5.0, -4.4, -3.1,  1.3,  4.4,  9.4, 12.5, 14.4]),
        EQPreset(name: "Large hall",                 bands: [10.0, 10.0,  5.6,  5.6,  0.0, -5.6, -5.6, -5.6,  0.0,  0.0]),
        EQPreset(name: "Party",                      bands: [ 6.9,  6.9,  0.0,  0.0,  0.0,  0.0,  0.0,  0.0,  6.9,  6.9]),
        EQPreset(name: "Pop",                        bands: [-2.5,  4.4,  6.9,  7.5,  5.0, -1.9, -3.1, -3.1, -2.5, -2.5]),
        EQPreset(name: "Reggae",                     bands: [ 0.0,  0.0, -1.3, -6.9,  0.0,  6.3,  6.3,  0.0,  0.0,  0.0]),
        EQPreset(name: "Rock",                       bands: [ 7.5,  4.4, -6.3, -8.8, -4.4,  3.8,  8.8, 10.6, 10.6, 10.6]),
        EQPreset(name: "Soft",                       bands: [ 4.4,  1.3, -1.9, -3.1, -1.9,  3.8,  8.1,  9.4, 10.6, 11.9]),
        EQPreset(name: "Ska",                        bands: [-3.1, -5.6, -5.0, -1.3,  3.8,  5.6,  8.8,  9.4, 10.6,  9.4]),
        EQPreset(name: "Full Bass",                  bands: [ 9.4,  9.4,  9.4,  5.6,  1.3, -5.0, -9.4,-11.3,-11.9,-11.9]),
        EQPreset(name: "Soft Rock",                  bands: [ 3.8,  3.8,  1.9, -1.3, -5.0, -6.3, -4.4, -1.3,  2.5,  8.8]),
        EQPreset(name: "Full Treble",                bands: [-10.6,-10.6,-10.6, -5.0,  2.5, 10.6, 15.6, 15.6, 15.6, 16.9]),
        EQPreset(name: "Full Bass & Treble",         bands: [ 6.9,  5.6,  0.0, -8.1, -5.6,  1.3,  8.1, 10.6, 11.9, 11.9]),
        EQPreset(name: "Live",                       bands: [-5.6,  0.0,  3.8,  5.0,  5.6,  5.6,  3.8,  2.5,  2.5,  1.9]),
        EQPreset(name: "Techno",                     bands: [ 7.5,  5.6,  0.0, -6.3, -5.6,  0.0,  7.5,  9.4,  9.4,  8.8]),
    ]
}

class EqualizerView: NSView {
    private let titleBar = TitleBarView()
    private let onButton = WinampButton(title: "ON", style: .toggle)
    private let autoButton = WinampButton(title: "AUTO", style: .toggle)
    private let presetsButton = WinampButton(title: "PRESETS", style: .action)
    private let preampSlider = WinampSlider(style: .eqBand, isVertical: true)
    private let responseView = EQResponseView()
    private var bandSliders: [WinampSlider] = []
    private var bandLabels: [NSTextField] = []
    private var dbLabels: [NSTextField] = []
    private var preLabel: NSTextField?
    private var dbUnitLabel: NSTextField?
    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var audioEngine: AudioEngine?

    private let bandNames = ["70", "180", "320", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    /// View height in logical points. eqmain.bmp is 116 px tall, so when a skin
    /// is active we shrink the view to match and draw the sprite 1:1. Without a
    /// skin we use Wamp's original 112 px layout.
    var desiredHeight: CGFloat {
        WinampTheme.skinIsActive ? 116 : WinampTheme.equalizerHeight
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
            }
        applySkinVisibility()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        titleBar.titleText = "WAMP EQUALIZER"
        titleBar.showButtons = false
        addSubview(titleBar)

        onButton.isActive = true
        onButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            engine.eqEnabled.toggle()
            self?.onButton.isActive = engine.eqEnabled
        }
        addSubview(onButton)

        autoButton.isActive = false
        autoButton.onClick = { [weak self] in
            self?.autoButton.isActive.toggle()
        }
        addSubview(autoButton)

        presetsButton.onClick = { [weak self] in self?.showPresetsMenu() }
        addSubview(presetsButton)

        // Preamp
        preampSlider.value = 0
        preampSlider.onChange = { [weak self] value in
            self?.audioEngine?.setPreamp(gain: value)
        }
        addSubview(preampSlider)

        // Response curve
        addSubview(responseView)

        // 10 band sliders
        for i in 0..<10 {
            let slider = WinampSlider(style: .eqBand, isVertical: true)
            slider.value = 0
            let bandIndex = i
            slider.onChange = { [weak self] value in
                self?.audioEngine?.setEQ(band: bandIndex, gain: value)
                self?.responseView.bands = self?.audioEngine?.eqBands ?? []
            }
            bandSliders.append(slider)
            addSubview(slider)

            let label = NSTextField(labelWithString: bandNames[i])
            label.font = WinampTheme.eqLabelFont
            label.textColor = WinampTheme.eqBandLabelColor
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .center
            bandLabels.append(label)
            addSubview(label)
        }

        // dB labels
        for (text, tag) in [("+12", 200), ("0", 201), ("-12", 202)] {
            let label = NSTextField(labelWithString: text)
            label.font = WinampTheme.eqLabelFont
            label.textColor = WinampTheme.eqDbLabelColor
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .right
            label.tag = tag
            addSubview(label)
            dbLabels.append(label)
        }

        // Preamp label
        let pre = NSTextField(labelWithString: "PRE")
        pre.font = WinampTheme.eqLabelFont
        pre.textColor = WinampTheme.eqBandLabelColor
        pre.isBezeled = false
        pre.drawsBackground = false
        pre.alignment = .center
        pre.tag = 210
        addSubview(pre)
        preLabel = pre

        // dB label under response
        let dbU = NSTextField(labelWithString: "dB")
        dbU.font = WinampTheme.eqLabelFont
        dbU.textColor = WinampTheme.eqBandLabelColor
        dbU.isBezeled = false
        dbU.drawsBackground = false
        dbU.alignment = .center
        dbU.tag = 211
        addSubview(dbU)
        dbUnitLabel = dbU

        // Wire EQ button sprite providers (sprites from eqmain.bmp)
        onButton.spriteKeyProvider = { active, pressed in .eqOnButton(active: active, pressed: pressed) }
        autoButton.spriteKeyProvider = { active, pressed in .eqAutoButton(active: active, pressed: pressed) }
        presetsButton.spriteKeyProvider = { _, pressed in .eqPresetsButton(pressed: pressed) }
    }

    /// Hides freq/dB/PRE/dB-unit labels and the title bar when a skin is loaded.
    /// All these labels are baked into eqmain.bmp; the title bar is replaced by
    /// the eqmain title strip.
    private func applySkinVisibility() {
        let active = WinampTheme.skinIsActive
        titleBar.isHidden = active
        for label in bandLabels { label.isHidden = active }
        for label in dbLabels { label.isHidden = active }
        preLabel?.isHidden = active
        dbUnitLabel?.isHidden = active
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard WinampTheme.skinIsActive else { return }
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        if let bg = WinampTheme.sprite(.eqBackground) {
            // eqmain.bmp is 275×116; view is resized to 116 when skinned so the
            // sprite fills bounds exactly and sub-sprite coords match Webamp.
            bg.draw(in: bounds)
        }

        // Title bar overlay (y=0..14 of the EQ body is left empty for this).
        let isActive = window?.isKeyWindow ?? true
        if let tb = WinampTheme.sprite(.eqTitleBar(active: isActive)) {
            tb.draw(in: NSRect(x: 0, y: bounds.height - 14, width: bounds.width, height: 14))
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 4

        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let controlsY = bounds.height - WinampTheme.titleBarHeight - 16
        onButton.frame = NSRect(x: pad, y: controlsY, width: 26, height: 14)
        autoButton.frame = NSRect(x: pad + 28, y: controlsY, width: 30, height: 14)
        presetsButton.frame = NSRect(x: w - pad - 50, y: controlsY, width: 50, height: 14)

        let sliderH: CGFloat = 62
        let sliderAreaTop = controlsY - 4

        // dB labels
        let dbLabelX: CGFloat = pad
        let dbLabelW: CGFloat = 16
        viewWithTag(200)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - 10, width: dbLabelW, height: 10)
        viewWithTag(201)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - sliderH / 2 - 5, width: dbLabelW, height: 10)
        viewWithTag(202)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - sliderH, width: dbLabelW, height: 10)

        // Preamp
        let preampX = dbLabelX + dbLabelW + 2
        preampSlider.frame = NSRect(x: preampX, y: sliderAreaTop - sliderH, width: 12, height: sliderH)
        viewWithTag(210)?.frame = NSRect(x: preampX - 2, y: sliderAreaTop - sliderH - 10, width: 16, height: 10)

        // Response view
        let respX = preampX + 16
        responseView.frame = NSRect(x: respX, y: sliderAreaTop - sliderH, width: 30, height: sliderH)
        viewWithTag(211)?.frame = NSRect(x: respX + 8, y: sliderAreaTop - sliderH - 10, width: 16, height: 10)

        // Band sliders
        let bandsStart = respX + 36
        let bandsWidth = w - bandsStart - pad
        let bandSpacing = bandsWidth / CGFloat(10)

        for i in 0..<10 {
            let x = bandsStart + CGFloat(i) * bandSpacing + (bandSpacing - 12) / 2
            bandSliders[i].frame = NSRect(x: x, y: sliderAreaTop - sliderH, width: 12, height: sliderH)
            bandLabels[i].frame = NSRect(x: x - 4, y: sliderAreaTop - sliderH - 10, width: 20, height: 10)
        }
    }

    func bindToModel(audioEngine: AudioEngine, playlistManager: PlaylistManager? = nil) {
        self.audioEngine = audioEngine

        audioEngine.$eqEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.onButton.isActive = enabled }
            .store(in: &cancellables)

        // AUTO mode: match genre to preset when track changes
        if let pm = playlistManager {
            pm.$currentIndex
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.autoApplyPreset(for: pm.currentTrack) }
                .store(in: &cancellables)
        }
    }

    private func autoApplyPreset(for track: Track?) {
        guard autoButton.isActive, let genre = track?.genre.lowercased(), !genre.isEmpty else { return }
        let genrePresetMap: [String: String] = [
            "rock": "Rock", "pop": "Pop", "classical": "Classical",
            "electronic": "Techno", "techno": "Techno", "dance": "Dance",
            "hip-hop": "Dance", "reggae": "Reggae", "ska": "Ska",
            "club": "Club", "party": "Party", "live": "Live",
            "jazz": "Live", "orchestral": "Classical"
        ]
        let presetName = genrePresetMap.first { genre.contains($0.key) }?.value ?? "Flat"
        if let preset = EQPreset.presets.first(where: { $0.name == presetName }) {
            audioEngine?.setAllEQBands(preset.bands)
            for (i, slider) in bandSliders.enumerated() {
                slider.value = preset.bands[i]
            }
            responseView.bands = preset.bands
        }
    }

    private func showPresetsMenu() {
        let menu = NSMenu()
        for preset in EQPreset.presets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(title: "Reset to Default", action: #selector(resetToDefault), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.popUp(positioning: nil, at: NSPoint(x: presetsButton.frame.minX, y: presetsButton.frame.minY), in: self)
    }

    @objc private func resetToDefault() {
        guard let flat = EQPreset.presets.first(where: { $0.name == "Flat" }) else { return }
        audioEngine?.setAllEQBands(flat.bands)
        for (i, slider) in bandSliders.enumerated() {
            slider.value = flat.bands[i]
        }
        responseView.bands = flat.bands
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        audioEngine?.setAllEQBands(preset.bands)
        for (i, slider) in bandSliders.enumerated() {
            slider.value = preset.bands[i]
        }
        responseView.bands = preset.bands
    }
}
