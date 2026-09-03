import Cocoa
import Combine

/// Main-window visualizer modes, cycled by clicking the vis area exactly
/// like Winamp 2.x. Raw values are persisted in `AppState.visualizerMode`.
enum VisualizerMode: Int, CaseIterable {
    case analyzer = 0
    case oscilloscope = 1
    case off = 2

    var next: VisualizerMode {
        VisualizerMode(rawValue: (rawValue + 1) % VisualizerMode.allCases.count) ?? .analyzer
    }
}

class SpectrumView: NSView {
    var spectrumData: [Float] = [] {
        didSet {
            guard mode == .analyzer else { return }
            updatePeaks()
            needsDisplay = true
        }
    }
    /// Samples in -1...1, left to right. See `AudioEngine.waveformData`.
    var waveformData: [Float] = [] {
        didSet { if mode == .oscilloscope { needsDisplay = true } }
    }
    var mode: VisualizerMode = .analyzer {
        didSet {
            if mode == .analyzer { peaks = [] }
            needsDisplay = true
        }
    }
    /// Fired after a click cycles the mode, so the owner can persist it.
    var onModeChange: ((VisualizerMode) -> Void)?
    var barCount: Int = 26

    /// Winamp convention: 16 vertical rows, each painted with viscolors[2..17] bottom→top.
    private static let rowCount = 16
    /// Oscilloscope gain: line-in music rarely exceeds ±0.5, and the classic
    /// scope filled its 16px happily, so boost before clamping.
    private static let scopeGain: CGFloat = 1.6

    /// Per-bar peak position (0...rowCount), decays 1 row per spectrumData update.
    private var peaks: [CGFloat] = []

    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        mode = mode.next
        onModeChange?(mode)
    }

    private func updatePeaks() {
        if peaks.count != barCount { peaks = Array(repeating: 0, count: barCount) }
        let rows = CGFloat(Self.rowCount)
        for i in 0..<barCount {
            let dataIndex = i < spectrumData.count ? i : 0
            let amplitude = spectrumData.isEmpty ? Float(0) : min(1, spectrumData[dataIndex] * 10)
            let barRows = CGFloat(amplitude) * rows
            if barRows >= peaks[i] {
                peaks[i] = barRows
            } else {
                peaks[i] = max(0, peaks[i] - 0.35) // falloff rate
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let viscolors = WinampTheme.provider.viscolors
        guard viscolors.count >= 24 else { return }
        switch mode {
        case .off:
            return
        case .analyzer:
            drawAnalyzer(viscolors)
        case .oscilloscope:
            drawOscilloscope(viscolors)
        }
    }

    private func drawAnalyzer(_ viscolors: [NSColor]) {
        let barWidth: CGFloat = 3
        let gap: CGFloat = 1
        let totalBars = min(barCount, Int(bounds.width / (barWidth + gap)))
        let rows = Self.rowCount
        let rowHeight = bounds.height / CGFloat(rows)

        // Row colors: viscolors[2..17], bottom → top.
        // Peak cap: viscolors[23] per Winamp convention.
        let peakColor = viscolors[23]

        for i in 0..<totalBars {
            let dataIndex = i < spectrumData.count ? i : 0
            let amplitude = spectrumData.isEmpty ? Float(0) : min(1, spectrumData[dataIndex] * 10)
            let litRows = Int(CGFloat(amplitude) * CGFloat(rows))
            let x = CGFloat(i) * (barWidth + gap)

            // Discrete 16-step bar
            for r in 0..<litRows {
                viscolors[2 + r].setFill()
                NSRect(x: x,
                       y: CGFloat(r) * rowHeight,
                       width: barWidth,
                       height: rowHeight).fill()
            }

            // Peak cap
            if i < peaks.count {
                let peakRow = Int(peaks[i])
                if peakRow > litRows && peakRow < rows {
                    peakColor.setFill()
                    NSRect(x: x,
                           y: CGFloat(peakRow) * rowHeight,
                           width: barWidth,
                           height: rowHeight).fill()
                }
            }
        }
    }

    /// Winamp's "lines" oscilloscope: one column per pixel, each column a
    /// vertical 1px segment joining the previous sample to this one, coloured
    /// from viscolors[18..22] by distance from the centre line.
    private func drawOscilloscope(_ viscolors: [NSColor]) {
        let width = Int(bounds.width)
        guard width > 1, !waveformData.isEmpty else { return }
        let rowHeight = bounds.height / CGFloat(Self.rowCount)
        let mid = bounds.height / 2
        let half = bounds.height / 2 - rowHeight / 2

        func sampleY(at column: Int) -> CGFloat {
            let idx = min(waveformData.count - 1, column * waveformData.count / width)
            let v = max(-1, min(1, CGFloat(waveformData[idx]) * Self.scopeGain))
            // Snap to the 16-row grid so it reads as the classic chunky scope.
            let row = (v * half / rowHeight).rounded()
            return mid + row * rowHeight
        }

        var prevY = sampleY(at: 0)
        for column in 0..<width {
            let y = sampleY(at: column)
            let top = max(y, prevY)
            let bottom = min(y, prevY)
            let distance = abs(y - mid) / max(half, 1)
            let colorIndex = 18 + min(4, Int(distance * 5))
            viscolors[colorIndex].setFill()
            NSRect(x: CGFloat(column),
                   y: bottom - rowHeight / 2,
                   width: 1,
                   height: max(rowHeight, top - bottom + rowHeight)).fill()
            prevY = y
        }
    }
}
