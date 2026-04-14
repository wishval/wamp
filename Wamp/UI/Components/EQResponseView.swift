import Cocoa
import Combine

class EQResponseView: NSView {
    var bands: [Float] = Array(repeating: 0, count: 10) { didSet { needsDisplay = true } }
    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if WinampTheme.skinIsActive {
            drawSkinned()
        } else {
            drawBuiltIn()
        }
    }

    private func drawSkinned() {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        let b = bounds

        if let bg = WinampTheme.sprite(.eqGraphBackground) {
            bg.draw(in: b)
        }

        drawPixelCurve(in: b) { row, rowCount in
            let t = CGFloat(rowCount - 1 - row) / CGFloat(max(rowCount - 1, 1))
            let hue = t * 120.0 / 360.0
            return NSColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
        }
    }

    private func drawBuiltIn() {
        let b = bounds

        let bgGradient = NSGradient(starting: WinampTheme.eqSliderBgTop, ending: WinampTheme.eqSliderBgBottom)
        bgGradient?.draw(in: b, angle: 90)

        // Grid: 10 pale vertical guides (one per EQ band)
        let bandCount = 10
        NSColor.white.withAlphaComponent(0.18).setFill()
        for i in 0..<bandCount {
            let x = round(b.width * (CGFloat(i) + 0.5) / CGFloat(bandCount))
            NSRect(x: x, y: 0, width: 1, height: b.height).fill()
        }

        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: round(b.midY), width: b.width, height: 1).fill()

        drawPixelCurve(in: b) { row, rowCount in
            let t = CGFloat(rowCount - 1 - row) / CGFloat(max(rowCount - 1, 1))
            let hue = t * 120.0 / 360.0
            return NSColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
        }
    }

    /// Classic Winamp draws the EQ curve as a 1px-wide per-column sweep across
    /// the graph area, not as a smooth bezier. For each integer x column we
    /// linearly interpolate between the two surrounding band gains, round the
    /// result to a pixel row, and fill a 1×1 rect. `colorForRow` returns the
    /// palette color for a given row index (0 = top, rowCount-1 = bottom).
    private func drawPixelCurve(in rect: NSRect, colorForRow: (_ row: Int, _ rowCount: Int) -> NSColor) {
        guard bands.count >= 10 else { return }

        let rowCount = max(1, Int(rect.height.rounded()))
        let colCount = max(1, Int(rect.width.rounded()))
        let lastBand = CGFloat(bands.count - 1)

        for col in 0..<colCount {
            let x = rect.minX + CGFloat(col)
            // Fractional band index for this column, linearly mapped across width.
            let f = CGFloat(col) / CGFloat(max(colCount - 1, 1)) * lastBand
            let lo = Int(f.rounded(.down))
            let hi = min(bands.count - 1, lo + 1)
            let frac = f - CGFloat(lo)
            let gain = (1 - frac) * CGFloat(bands[lo]) + frac * CGFloat(bands[hi])
            let normalized = gain / 12.0 // -1..1 for ±12 dB

            // Row 0 = top (+12 dB); rowCount-1 = bottom (-12 dB). Classic Winamp
            // maps gain linearly onto the 19-row graph.
            let rowF = (1 - normalized) / 2 * CGFloat(rowCount - 1)
            let row = min(rowCount - 1, max(0, Int(rowF.rounded())))
            let y = rect.minY + CGFloat(rowCount - 1 - row)

            colorForRow(row, rowCount).setFill()
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
    }
}
