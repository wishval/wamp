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

        // Graph background from eqmain.bmp at the graph rect
        if let bg = WinampTheme.sprite(.eqGraphBackground) {
            bg.draw(in: bounds)
        }

        // Draw response curve using the 19 line colors sampled from eqmain.bmp.
        // The colors are top→bottom = +12dB→-12dB. We render at 1px thickness per dB row.
        let lines = WinampTheme.provider.eqGraphLineColors
        guard lines.count == 19, !bands.isEmpty else { return }

        // Interpolate band values across the bounds width and pick the corresponding color row.
        let cols = max(1, Int(bounds.width))
        let rowHeight = bounds.height / 19
        for col in 0..<cols {
            let bandIndex = min(bands.count - 1, Int(Double(col) / Double(cols) * Double(bands.count)))
            let band = bands[bandIndex]
            // band is in -12...+12; row 0 = +12dB (top), row 18 = -12dB (bottom)
            let row = Int(round(9 - Double(band) * 9 / 12))
            let clampedRow = max(0, min(18, row))
            lines[clampedRow].setFill()
            let y = bounds.height - CGFloat(clampedRow + 1) * rowHeight
            NSRect(x: CGFloat(col), y: y, width: 1, height: max(1, rowHeight)).fill()
        }
    }

    private func drawBuiltIn() {
        let b = bounds

        // Background
        let bgGradient = NSGradient(starting: WinampTheme.eqSliderBgTop, ending: WinampTheme.eqSliderBgBottom)
        bgGradient?.draw(in: b, angle: 90)

        // Grid: 10 pale vertical guides (one per EQ band)
        let bandCount = 10
        NSColor.white.withAlphaComponent(0.18).setFill()
        for i in 0..<bandCount {
            let x = round(b.width * (CGFloat(i) + 0.5) / CGFloat(bandCount))
            NSRect(x: x, y: 0, width: 1, height: b.height).fill()
        }

        // Horizontal mid-line — pale white, matching the verticals
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: round(b.midY), width: b.width, height: 1).fill()

        // Response curve
        guard bands.count >= 10 else { return }
        let path = NSBezierPath()
        WinampTheme.greenBright.setStroke()
        path.lineWidth = 1.4

        for (i, gain) in bands.enumerated() {
            let x = b.width * CGFloat(i) / CGFloat(bands.count - 1)
            let normalized = CGFloat(gain / 12) // -1 to 1
            let y = b.midY + normalized * (b.height / 2 - 1)

            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.stroke()
    }
}
