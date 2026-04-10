import Cocoa
import Combine

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

    /// Closure that maps (active, pressed) → SpriteKey. Set by parent views.
    /// When non-nil and the sprite resolves, the button renders the sprite
    /// instead of the programmatic path.
    var spriteKeyProvider: ((Bool, Bool) -> SpriteKey)?

    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(title: String, style: WinampButtonStyle = .action) {
        self.init(frame: .zero)
        self.title = title
        self.style = style
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Sprite path: if a sprite key provider is set and the sprite resolves,
        // blit it as the entire button face and skip the programmatic path.
        if WinampTheme.skinIsActive,
           let provide = spriteKeyProvider,
           let sprite = WinampTheme.sprite(provide(isActive, isPressed)) {
            let ctx = NSGraphicsContext.current
            let prev = ctx?.imageInterpolation
            ctx?.imageInterpolation = .none
            sprite.draw(in: bounds)
            if let prev = prev { ctx?.imageInterpolation = prev }
            return
        }

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
