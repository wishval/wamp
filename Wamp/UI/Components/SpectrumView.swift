import Cocoa
import Combine

class SpectrumView: NSView {
    var spectrumData: [Float] = [] {
        didSet {
            updatePeaks()
            needsDisplay = true
        }
    }
    var barCount: Int = 26

    /// Winamp convention: 16 vertical rows, each painted with viscolors[2..17] bottom→top.
    private static let rowCount = 16

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

        let barWidth: CGFloat = 3
        let gap: CGFloat = 1
        let totalBars = min(barCount, Int(bounds.width / (barWidth + gap)))
        let rows = Self.rowCount
        let rowHeight = bounds.height / CGFloat(rows)

        let viscolors = WinampTheme.provider.viscolors
        guard viscolors.count >= 24 else { return }

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
}
