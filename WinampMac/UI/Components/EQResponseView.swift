import Cocoa

class EQResponseView: NSView {
    var bands: [Float] = Array(repeating: 0, count: 10) { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        // Background
        let bgGradient = NSGradient(starting: WinampTheme.eqSliderBgTop, ending: WinampTheme.eqSliderBgBottom)
        bgGradient?.draw(in: b, angle: 90)

        // Center line
        WinampTheme.eqSliderCenter.setStroke()
        let centerPath = NSBezierPath()
        centerPath.move(to: NSPoint(x: 0, y: b.midY))
        centerPath.line(to: NSPoint(x: b.width, y: b.midY))
        centerPath.lineWidth = 0.5
        centerPath.stroke()

        // Response curve
        guard bands.count >= 10 else { return }
        let path = NSBezierPath()
        WinampTheme.greenBright.setStroke()
        path.lineWidth = 1.2

        for (i, gain) in bands.enumerated() {
            let x = b.width * CGFloat(i) / CGFloat(bands.count - 1)
            let normalized = CGFloat(gain / 12) // -1 to 1
            let y = b.midY - normalized * (b.height / 2 - 2)

            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.stroke()
    }
}
