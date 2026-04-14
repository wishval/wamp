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

        // Graph background from eqmain.bmp
        if let bg = WinampTheme.sprite(.eqGraphBackground) {
            bg.draw(in: b)
        }

        // Horizontal center line (0 dB)
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: round(b.midY), width: b.width, height: 1).fill()

        // Response curve — Catmull-Rom spline, colored by gain (green→red hue),
        // matching the unskinned drawBuiltIn() style.
        guard bands.count >= 10 else { return }
        let lineWidth: CGFloat = 1.6

        var points: [NSPoint] = []
        for (i, gain) in bands.enumerated() {
            let x = b.width * CGFloat(i) / CGFloat(bands.count - 1)
            let normalized = CGFloat(gain / 12) // -1 to 1
            let y = b.midY + normalized * (b.height / 2 - 1)
            points.append(NSPoint(x: x, y: y))
        }

        for i in 0..<(points.count - 1) {
            let avgGain = (bands[i] + bands[i + 1]) / 2.0
            let t = CGFloat((avgGain + 12) / 24.0) // 0..1
            let hue = (1 - t) * 120.0 / 360.0
            let color = NSColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
            color.setStroke()

            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

            let segment = NSBezierPath()
            segment.lineWidth = lineWidth
            segment.move(to: p1)
            segment.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
            segment.stroke()
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

        // Response curve — gradient colored per band (green=cut, yellow=flat, red=boost)
        guard bands.count >= 10 else { return }
        let lineWidth: CGFloat = 1.6

        var points: [NSPoint] = []
        for (i, gain) in bands.enumerated() {
            let x = b.width * CGFloat(i) / CGFloat(bands.count - 1)
            let normalized = CGFloat(gain / 12) // -1 to 1
            let y = b.midY + normalized * (b.height / 2 - 1)
            points.append(NSPoint(x: x, y: y))
        }

        // Draw Catmull-Rom spline segments for smooth curves, colored by average gain
        for i in 0..<(points.count - 1) {
            let avgGain = (bands[i] + bands[i + 1]) / 2.0
            let t = CGFloat((avgGain - (-12)) / 24.0) // 0..1
            let hue = (1 - t) * 120.0 / 360.0
            let color = NSColor(hue: hue, saturation: 0.90, brightness: 0.95, alpha: 1.0)
            color.setStroke()

            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

            let segment = NSBezierPath()
            segment.lineWidth = lineWidth
            segment.move(to: p1)
            segment.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
            segment.stroke()
        }
    }
}
