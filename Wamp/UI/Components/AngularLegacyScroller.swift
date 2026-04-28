import Cocoa

/// Native NSScroller for the playlist's unskinned mode. Draws flat,
/// rectangular knob and groove using WinampTheme colors so the scrollbar
/// matches the rest of the angular pixel-perfect chrome instead of macOS's
/// rounded `.legacy` default. Skinned mode uses `PlaylistSkinScroller` and
/// bypasses this class entirely.
final class AngularLegacyScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollerStyle = .legacy
        controlSize = .small
    }

    required init?(coder: NSCoder) { fatalError() }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let path = NSBezierPath(rect: slotRect)
        WinampTheme.frameBackground.shadow(withLevel: 0.4)?.setFill()
        path.fill()

        WinampTheme.insetBorderDark.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func drawKnob() {
        let r = rect(for: .knob)
        let face = NSBezierPath(rect: r)
        WinampTheme.buttonFaceTop.setFill()
        face.fill()

        // 1px chiseled border: light top/left, dark bottom/right.
        let light = NSBezierPath()
        light.move(to: NSPoint(x: r.minX, y: r.maxY - 0.5))
        light.line(to: NSPoint(x: r.maxX, y: r.maxY - 0.5))
        light.move(to: NSPoint(x: r.minX + 0.5, y: r.maxY))
        light.line(to: NSPoint(x: r.minX + 0.5, y: r.minY))
        WinampTheme.buttonBorderLight.setStroke()
        light.lineWidth = 1
        light.stroke()

        let dark = NSBezierPath()
        dark.move(to: NSPoint(x: r.minX, y: r.minY + 0.5))
        dark.line(to: NSPoint(x: r.maxX, y: r.minY + 0.5))
        dark.move(to: NSPoint(x: r.maxX - 0.5, y: r.maxY))
        dark.line(to: NSPoint(x: r.maxX - 0.5, y: r.minY))
        WinampTheme.buttonBorderDark.setStroke()
        dark.lineWidth = 1
        dark.stroke()
    }
}
