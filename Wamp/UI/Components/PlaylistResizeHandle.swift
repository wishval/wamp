import Cocoa

final class PlaylistResizeHandle: NSView {
    var onResize: ((CGFloat) -> Void)?
    private var startingMouseY: CGFloat?
    private var startingHeight: CGFloat = 0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        startingMouseY = NSEvent.mouseLocation.y
        startingHeight = superview?.bounds.height ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startingMouseY else { return }
        let delta = (startingMouseY - NSEvent.mouseLocation.y) / WinampTheme.scale
        onResize?(startingHeight + delta)
    }

    override func mouseUp(with event: NSEvent) {
        startingMouseY = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !WinampTheme.skinIsActive else { return }
        WinampTheme.frameBorderLight.setStroke()
        let path = NSBezierPath()
        for offset in stride(from: CGFloat(3), through: 9, by: 3) {
            path.move(to: NSPoint(x: offset, y: 2))
            path.line(to: NSPoint(x: bounds.width - 2, y: bounds.height - offset))
        }
        path.lineWidth = 1
        path.stroke()
    }
}
