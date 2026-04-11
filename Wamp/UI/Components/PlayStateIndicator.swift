import Cocoa

class PlayStateIndicator: NSView {
    var state: PlayState = .stopped {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds.insetBy(dx: 1, dy: 1)
        WinampTheme.greenBright.setFill()
        WinampTheme.greenBright.setStroke()

        switch state {
        case .playing:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: b.minX, y: b.minY))
            path.line(to: NSPoint(x: b.minX, y: b.maxY))
            path.line(to: NSPoint(x: b.maxX, y: b.midY))
            path.close()
            path.fill()
        case .paused:
            let barW = b.width * 0.35
            NSRect(x: b.minX, y: b.minY, width: barW, height: b.height).fill()
            NSRect(x: b.maxX - barW, y: b.minY, width: barW, height: b.height).fill()
        case .stopped:
            NSRect(x: b.minX, y: b.minY, width: b.width, height: b.height).fill()
        }
    }
}
