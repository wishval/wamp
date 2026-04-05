import Cocoa

enum WinampButtonStyle {
    case transport
    case toggle
    case action
}

class WinampButton: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    var isPressed = false { didSet { needsDisplay = true } }
    var style: WinampButtonStyle = .transport
    var onClick: (() -> Void)?
    var drawIcon: ((NSRect, Bool) -> Void)? // custom icon drawer (rect, isActive)

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(title: String, style: WinampButtonStyle = .action) {
        self.init(frame: .zero)
        self.title = title
        self.style = style
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        // Button face gradient
        let faceTop = isPressed ? WinampTheme.buttonFaceBottom : WinampTheme.buttonFaceTop
        let faceBot = isPressed ? WinampTheme.buttonFaceTop : WinampTheme.buttonFaceBottom
        let gradient = NSGradient(starting: faceTop, ending: faceBot)
        gradient?.draw(in: b, angle: 90)

        // 3D beveled border
        let borderLight = isPressed ? WinampTheme.buttonBorderDark : WinampTheme.buttonBorderLight
        let borderDark = isPressed ? WinampTheme.buttonBorderLight : WinampTheme.buttonBorderDark

        borderLight.setStroke()
        var path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: 0, y: b.height))
        path.line(to: NSPoint(x: b.width, y: b.height))
        path.lineWidth = 1
        path.stroke()

        borderDark.setStroke()
        path = NSBezierPath()
        path.move(to: NSPoint(x: b.width, y: b.height))
        path.line(to: NSPoint(x: b.width, y: 0))
        path.line(to: NSPoint(x: 0, y: 0))
        path.lineWidth = 1
        path.stroke()

        // Content
        if let drawIcon = drawIcon {
            drawIcon(b.insetBy(dx: 4, dy: 3), isActive)
        } else if !title.isEmpty {
            let color = isActive ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WinampTheme.buttonFont,
                .foregroundColor: color
            ]
            let size = title.size(withAttributes: attrs)
            let point = NSPoint(
                x: (b.width - size.width) / 2,
                y: (b.height - size.height) / 2
            )
            title.draw(at: point, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
}
