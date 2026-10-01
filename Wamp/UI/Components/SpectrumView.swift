import Cocoa
import Combine

class SpectrumView: NSView {
    var spectrumData: [Float] = [] {
        didSet {
            updatePeaks()
            needsDisplay = true
        }
    }
    /// Bars that fit the view at 3px + 1px gap (19 skinned, 26 built-in).
    /// AudioEngine computes exactly this many log-spaced bands.
    var barCount: Int { Int(bounds.width / (Self.barWidth + Self.gap)) }

    /// Winamp convention: 16 vertical rows, painted with viscolors[17...2]
    /// bottom→top (viscolors[2] is the top/red row).
    private static let rowCount = 16
    private static let barWidth: CGFloat = 3
    private static let gap: CGFloat = 1

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
        if peaks.count != spectrumData.count { peaks = Array(repeating: 0, count: spectrumData.count) }
        let rows = CGFloat(Self.rowCount)
        for (i, amplitude) in spectrumData.enumerated() {
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

        let totalBars = min(barCount, spectrumData.count)
        let rows = Self.rowCount
        let rowHeight = bounds.height / CGFloat(rows)

        let viscolors = WinampTheme.provider.viscolors
        guard viscolors.count >= 24 else { return }

        // Peak cap: viscolors[23] per Winamp convention.
        let peakColor = viscolors[23]

        for i in 0..<totalBars {
            let litRows = Int(CGFloat(spectrumData[i]) * CGFloat(rows))
            let x = CGFloat(i) * (Self.barWidth + Self.gap)

            // Discrete 16-step bar
            for r in 0..<litRows {
                viscolors[17 - r].setFill()
                NSRect(x: x,
                       y: CGFloat(r) * rowHeight,
                       width: Self.barWidth,
                       height: rowHeight).fill()
            }

            // Peak cap
            if i < peaks.count {
                let peakRow = Int(peaks[i])
                if peakRow > litRows && peakRow < rows {
                    peakColor.setFill()
                    NSRect(x: x,
                           y: CGFloat(peakRow) * rowHeight,
                           width: Self.barWidth,
                           height: rowHeight).fill()
                }
            }
        }
    }
}
