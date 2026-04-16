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

        // Skin-sourced palette: 19 colors from the vertical strip at x=115,
        // y=294..312 in eqmain.bmp (index 0 = +12 dB / top, 18 = −12 dB / bottom).
        // See EqGraphColorsParser.
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

    /// Draws the EQ response curve using natural cubic spline interpolation,
    /// matching Webamp's EqGraph algorithm (adapted from morganherlocker/cubic-spline).
    /// For each x column we compute the spline-interpolated row and fill the vertical
    /// segment from the previous column's row to the current one (height = 1 + |Δrow|).
    /// `colorForRow` returns the palette color for a given row (0 = top / +12 dB).
    private func drawPixelCurve(in rect: NSRect, colorForRow: (_ row: Int, _ rowCount: Int) -> NSColor) {
        guard bands.count >= 10 else { return }

        let rowCount = max(1, Int(rect.height.rounded()))
        let colCount = max(1, Int(rect.width.rounded()))
        guard colCount > 1 else { return }
        let lastBand = Double(bands.count - 1)

        // Control-point x positions: evenly spaced across the graph width.
        let xs = (0..<bands.count).map { Double($0) / lastBand * Double(colCount - 1) }

        // Control-point y positions: band gain → row (0 = +12 dB top, rowCount-1 = −12 dB bottom).
        let ys = bands.map { band -> Double in
            let normalized = Double(band) / 12.0
            return (1.0 - normalized) / 2.0 * Double(rowCount - 1)
        }

        let ks = Self.naturalSplineSlopes(xs: xs, ys: ys)

        func splineRow(_ col: Int) -> Int {
            let y = Self.evaluateSpline(xs: xs, ys: ys, ks: ks, at: Double(col))
            return min(rowCount - 1, max(0, Int(y.rounded())))
        }

        var lastRow = splineRow(0)
        for col in 0..<colCount {
            let curRow = splineRow(col)
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

    // MARK: - Natural cubic spline (Webamp-compatible)

    /// Compute tangent slopes for a natural cubic spline through (xs, ys).
    /// Uses Gaussian elimination with partial pivoting on the tridiagonal system.
    private static func naturalSplineSlopes(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count - 1
        guard n > 0 else { return Array(repeating: 0, count: xs.count) }

        let size = n + 1
        var m = [[Double]](repeating: [Double](repeating: 0, count: size + 1), count: size)

        // Interior rows
        for i in 1..<n {
            let dx0 = xs[i] - xs[i - 1]
            let dx1 = xs[i + 1] - xs[i]
            m[i][i - 1] = 1 / dx0
            m[i][i]     = 2 * (1 / dx0 + 1 / dx1)
            m[i][i + 1] = 1 / dx1
            m[i][size]  = 3 * ((ys[i] - ys[i - 1]) / (dx0 * dx0) + (ys[i + 1] - ys[i]) / (dx1 * dx1))
        }

        // Natural boundary conditions (second derivative = 0 at endpoints)
        let dxFirst = xs[1] - xs[0]
        m[0][0] = 2 / dxFirst
        m[0][1] = 1 / dxFirst
        m[0][size] = 3 * (ys[1] - ys[0]) / (dxFirst * dxFirst)

        let dxLast = xs[n] - xs[n - 1]
        m[n][n - 1] = 1 / dxLast
        m[n][n]     = 2 / dxLast
        m[n][size]  = 3 * (ys[n] - ys[n - 1]) / (dxLast * dxLast)

        // Gaussian elimination with partial pivoting
        for col in 0..<size {
            var maxRow = col
            var maxVal = abs(m[col][col])
            for row in (col + 1)..<size {
                let v = abs(m[row][col])
                if v > maxVal { maxVal = v; maxRow = row }
            }
            if maxRow != col { m.swapAt(col, maxRow) }
            for row in (col + 1)..<size {
                let factor = m[row][col] / m[col][col]
                for j in col...size { m[row][j] -= factor * m[col][j] }
            }
        }

        // Back substitution
        var ks = [Double](repeating: 0, count: size)
        for i in stride(from: n, through: 0, by: -1) {
            var sum = m[i][size]
            for j in (i + 1)..<(n + 1) { sum -= m[i][j] * ks[j] }
            ks[i] = sum / m[i][i]
        }
        return ks
    }

    /// Evaluate the cubic spline at a given x using pre-computed slopes.
    private static func evaluateSpline(xs: [Double], ys: [Double], ks: [Double], at x: Double) -> Double {
        var i = 1
        while i < xs.count - 1 && xs[i] < x { i += 1 }

        let dx = xs[i] - xs[i - 1]
        let t = (x - xs[i - 1]) / dx
        let a = ks[i - 1] * dx - (ys[i] - ys[i - 1])
        let b = -ks[i] * dx + (ys[i] - ys[i - 1])
        return (1 - t) * ys[i - 1] + t * ys[i] + t * (1 - t) * (a * (1 - t) + b * t)
    }
}
