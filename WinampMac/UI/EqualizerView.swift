import Cocoa
import Combine

struct EQPreset {
    let name: String
    let bands: [Float]

    nonisolated static let presets: [EQPreset] = [
        EQPreset(name: "Flat", bands: [0,0,0,0,0,0,0,0,0,0]),
        EQPreset(name: "Rock", bands: [5,4,3,1,-1,-1,0,2,3,4]),
        EQPreset(name: "Pop", bands: [-1,2,4,5,3,0,-1,-2,-1,0]),
        EQPreset(name: "Jazz", bands: [4,3,1,2,-2,-2,0,1,3,4]),
        EQPreset(name: "Classical", bands: [5,4,3,2,-1,-1,0,2,3,4]),
        EQPreset(name: "Bass Boost", bands: [8,6,4,2,0,0,0,0,0,0]),
        EQPreset(name: "Treble Boost", bands: [0,0,0,0,0,1,3,5,7,8]),
        EQPreset(name: "Vocal", bands: [-2,-1,0,3,5,5,3,1,0,-2]),
        EQPreset(name: "Electronic", bands: [6,4,1,0,-2,2,1,2,5,6]),
        EQPreset(name: "Loudness", bands: [6,4,0,-2,-1,0,-1,-2,5,2]),
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
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    private let bandNames = ["70", "180", "320", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
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
        }

        // Preamp label
        let preLabel = NSTextField(labelWithString: "PRE")
        preLabel.font = WinampTheme.eqLabelFont
        preLabel.textColor = WinampTheme.eqBandLabelColor
        preLabel.isBezeled = false
        preLabel.drawsBackground = false
        preLabel.alignment = .center
        preLabel.tag = 210
        addSubview(preLabel)

        // dB label under response
        let dbLabel = NSTextField(labelWithString: "dB")
        dbLabel.font = WinampTheme.eqLabelFont
        dbLabel.textColor = WinampTheme.eqBandLabelColor
        dbLabel.isBezeled = false
        dbLabel.drawsBackground = false
        dbLabel.alignment = .center
        dbLabel.tag = 211
        addSubview(dbLabel)
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
            "rock": "Rock", "pop": "Pop", "jazz": "Jazz",
            "classical": "Classical", "electronic": "Electronic",
            "dance": "Electronic", "hip-hop": "Bass Boost", "r&b": "Vocal"
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
        menu.popUp(positioning: nil, at: NSPoint(x: presetsButton.frame.minX, y: presetsButton.frame.minY), in: self)
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
