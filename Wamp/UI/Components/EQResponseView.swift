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

        // Skin-sourced palette: 19 colors sampled from eqmain.bmp at y=313
        // (x=0 = +12dB / top, x=18 = -12dB / bottom). Each color covers one
        // pixel row of the 19-pixel-tall graph. See EqGraphColorsParser.
        let palette = WinampTheme.provider.eqGraphLineColors
        if palette.count == 19 {
            drawPixelCurve(in: b) { row, rowCount in
                let idx = min(palette.count - 1, row * palette.count / max(rowCount, 1))
                return palette[idx]
            }
        } else {
            // Skin somehow lacks the palette — fall back to the built-in hue gradient.
            drawPixelCurve(in: b) { row, rowCount in hueGradient(row: row, rowCount: rowCount) }
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

        drawPixelCurve(in: b) { row, rowCount in hueGradient(row: row, rowCount: rowCount) }
    }

    /// Green→red hue by row position (top = red/boost, bottom = green/cut).
    private func hueGradient(row: Int, rowCount: Int) -> NSColor {
        let t = CGFloat(rowCount - 1 - row) / CGFloat(max(rowCount - 1, 1))
        let hue = t * 120.0 / 360.0
        return NSColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
    }

    /// Classic Winamp / Webamp draws the EQ curve as a connected 1px-wide line:
    /// for each x column we compute the curve row and fill the vertical segment
    /// from the previous column's row to the current one (height = 1 + |Δrow|).
    /// This matches Webamp's `fillRect(x, yTop, 1, 1 + |lastY - y|)` loop and
    /// keeps the line visible even when adjacent bands swing sharply.
    /// `colorForRow` returns the palette color for a given row (0 = top).
    private func drawPixelCurve(in rect: NSRect, colorForRow: (_ row: Int, _ rowCount: Int) -> NSColor) {
        guard bands.count >= 10 else { return }

        let rowCount = max(1, Int(rect.height.rounded()))
        let colCount = max(1, Int(rect.width.rounded()))
        let lastBand = CGFloat(bands.count - 1)

        func row(for col: Int) -> Int {
            let f = CGFloat(col) / CGFloat(max(colCount - 1, 1)) * lastBand
            let lo = Int(f.rounded(.down))
            let hi = min(bands.count - 1, lo + 1)
            let frac = f - CGFloat(lo)
            let gain = (1 - frac) * CGFloat(bands[lo]) + frac * CGFloat(bands[hi])
            let normalized = gain / 12.0 // -1..1 for ±12 dB
            let rowF = (1 - normalized) / 2 * CGFloat(rowCount - 1)
            return min(rowCount - 1, max(0, Int(rowF.rounded())))
        }

        var lastRow = row(for: 0)
        for col in 0..<colCount {
            let curRow = row(for: col)
            // Fill the vertical segment [min(lastRow, curRow) … max(lastRow, curRow)]
            // column by column. Each pixel gets its per-row palette color so the
            // line carries the skin's gradient from +12 dB (top) to -12 dB (bottom).
            let topRow = min(lastRow, curRow)
            let botRow = max(lastRow, curRow)
            let x = rect.minX + CGFloat(col)
            for r in topRow...botRow {
                let y = rect.minY + CGFloat(rowCount - 1 - r)
                colorForRow(r, rowCount).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
            lastRow = curRow
        }
    }
}
