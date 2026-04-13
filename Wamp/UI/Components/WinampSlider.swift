import Cocoa
import Combine

enum WinampSliderStyle {
    case seek       // olive-green, horizontal
    case volume     // orange gradient, horizontal
    case balance    // olive-green, horizontal
    case eqBand     // vertical, yellow-tinted background
}

class WinampSlider: NSView {
    var value: Float = 0 {
        didSet {
            needsDisplay = true
            if isUserInteracting { onChange?(value) }
        }
    }
    var minValue: Float = 0
    var maxValue: Float = 1
    var onChange: ((Float) -> Void)?
    var style: WinampSliderStyle = .seek
    var isVertical: Bool = false

    private var isDragging = false
    private(set) var isUserInteracting = false
    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(style: WinampSliderStyle, isVertical: Bool = false) {
        self.init(frame: .zero)
        self.style = style
        self.isVertical = isVertical
        if style == .eqBand {
            self.isVertical = true
            self.minValue = -12
            self.maxValue = 12
        }
    }

    private var normalizedValue: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((value - minValue) / (maxValue - minValue))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if WinampTheme.skinIsActive {
            drawSkinned()
            return
        }
        let b = bounds
        if isVertical {
            drawVerticalSlider(in: b)
        } else {
            drawHorizontalSlider(in: b)
        }
    }

    private func drawSkinned() {
        let n = normalizedValue
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        switch style {
        case .seek:
            if let bg = WinampTheme.sprite(.seekBackground) {
                bg.draw(in: bounds)
            }
            let thumbW: CGFloat = 29
            let thumbX = n * (bounds.width - thumbW)
            if let thumb = WinampTheme.sprite(.seekThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 10) / 2, width: thumbW, height: 10))
            }

        case .volume:
            let position = Int((n * 27).rounded())
            if let bg = WinampTheme.sprite(.volumeBackground(position: position)) {
                bg.draw(in: bounds)
            }
            let thumbW: CGFloat = 14
            let thumbX = n * (bounds.width - thumbW)
            if let thumb = WinampTheme.sprite(.volumeThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: thumbW, height: 11))
            }

        case .balance:
            let position = Int((n * 27).rounded())
            if let bg = WinampTheme.sprite(.balanceBackground(position: position)) {
                bg.draw(in: bounds)
            }
            let thumbW: CGFloat = 14
            let thumbX = n * (bounds.width - thumbW)
            if let thumb = WinampTheme.sprite(.balanceThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: thumbW, height: 11))
            }

        case .eqBand:
            if let bg = WinampTheme.sprite(.eqSliderBackground) {
                bg.draw(in: bounds)
            }
            // 14 thumb positions: 0 = bottom (-12 dB), 13 = top (+12 dB)
            let thumbPos = Int((n * 13).rounded())
            let thumbY = n * (bounds.height - 11)
            if let thumb = WinampTheme.sprite(.eqSliderThumb(position: thumbPos, pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: (bounds.width - 11) / 2, y: thumbY, width: 11, height: 11))
            }
        }
    }

    private func drawHorizontalSlider(in rect: NSRect) {
        let trackY = rect.midY - 3
        let trackRect = NSRect(x: 1, y: trackY, width: rect.width - 2, height: 6)

        // Track background
        switch style {
        case .volume:
            WinampTheme.lcdBackground.setFill()
            trackRect.fill()
        default:
            WinampTheme.lcdBackground.setFill()
            trackRect.fill()
        }

        // Inset border
        drawInsetBorder(trackRect)

        // Fill
        let fillWidth = trackRect.width * normalizedValue
        let fillRect = NSRect(x: trackRect.minX + 1, y: trackY + 1, width: fillWidth, height: 4)
        switch style {
        case .volume:
            Self.skinColor(at: normalizedValue).setFill()
            fillRect.fill()
        default:
            let gradient = NSGradient(starting: WinampTheme.seekFillTop, ending: WinampTheme.seekFillBottom)
            gradient?.draw(in: fillRect, angle: 90)
        }

        // Thumb — clamped so it doesn't overflow into adjacent sliders
        let thumbW: CGFloat = 14
        let thumbH: CGFloat = rect.height
        let thumbX = min(rect.width - thumbW, max(0, trackRect.minX + fillWidth - thumbW / 2))
        let thumbRect = NSRect(x: thumbX, y: 0, width: thumbW, height: thumbH)
        drawThumb(thumbRect, isVolumeStyle: style == .volume)
    }

    private func drawVerticalSlider(in rect: NSRect) {
        let trackX = rect.midX - 4
        let trackRect = NSRect(x: trackX, y: 0, width: 8, height: rect.height)

        // Dark solid track background
        WinampTheme.eqTrackBackground.setFill()
        NSBezierPath(rect: trackRect).fill()
        drawInsetBorder(trackRect)

        // Single flat color based on slider position, from Winamp 2.x skin palette.
        let thumbY = rect.height * normalizedValue
        let fillRect = NSRect(x: trackRect.minX + 1, y: trackRect.minY + 1, width: trackRect.width - 2, height: max(0, trackRect.height - 2))
        Self.skinColor(at: normalizedValue).setFill()
        fillRect.fill()

        // Thumb
        let eqThumbH: CGFloat = 4
        let eqThumbW: CGFloat = 12
        let eqThumbRect = NSRect(x: rect.midX - eqThumbW / 2, y: thumbY - eqThumbH / 2, width: eqThumbW, height: eqThumbH)
        drawEQThumb(eqThumbRect)
    }

    private func drawThumb(_ rect: NSRect, isVolumeStyle: Bool) {
        if isVolumeStyle {
            let gradient = NSGradient(colors: [WinampTheme.volumeThumbTop, WinampTheme.volumeThumbMid, WinampTheme.volumeThumbBottom])
            gradient?.draw(in: rect, angle: 90)
            WinampTheme.volumeThumbBorderLight.setStroke()
            NSBezierPath(rect: rect).stroke()
        } else {
            let gradient = NSGradient(colors: [WinampTheme.seekThumbTop, WinampTheme.seekThumbMid, WinampTheme.seekThumbBottom])
            gradient?.draw(in: rect, angle: 90)
            WinampTheme.seekThumbBorderLight.setStroke()
            NSBezierPath(rect: rect).stroke()
        }
    }

    private func drawEQThumb(_ rect: NSRect) {
        let gradient = NSGradient(colors: [WinampTheme.eqThumbTop, WinampTheme.eqThumbMid, WinampTheme.eqThumbBottom])
        gradient?.draw(in: rect, angle: 90)
        WinampTheme.eqThumbBorderLight.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
        path.lineWidth = 0.5
        path.stroke()
    }

    /// Interpolates between Winamp 2.x volume.bmp skin colors for a given 0..1 position.
    private static func skinColor(at t: CGFloat) -> NSColor {
        let stops: [(CGFloat, UInt32)] = [
            (0.0,  0x18920B),  // dark green
            (0.19, 0x81E230),  // bright green
            (0.44, 0xC6DA30),  // yellow
            (0.67, 0xE0B228),  // orange
            (1.0,  0xE00E15),  // red
        ]
        // Find the two stops that bracket t
        var lo = 0
        for i in 1..<stops.count {
            if stops[i].0 >= t { lo = i - 1; break }
            lo = i - 1
        }
        let hi = min(lo + 1, stops.count - 1)
        let range = stops[hi].0 - stops[lo].0
        let frac = range > 0 ? (t - stops[lo].0) / range : 0
        let c1 = stops[lo].1
        let c2 = stops[hi].1
        let r = CGFloat((c1 >> 16) & 0xFF) + frac * (CGFloat((c2 >> 16) & 0xFF) - CGFloat((c1 >> 16) & 0xFF))
        let g = CGFloat((c1 >> 8) & 0xFF) + frac * (CGFloat((c2 >> 8) & 0xFF) - CGFloat((c1 >> 8) & 0xFF))
        let b = CGFloat(c1 & 0xFF) + frac * (CGFloat(c2 & 0xFF) - CGFloat(c1 & 0xFF))
        return NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private func drawInsetBorder(_ rect: NSRect) {
        let path = NSBezierPath()
        WinampTheme.insetBorderDark.setStroke()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.lineWidth = 1
        path.stroke()

        let path2 = NSBezierPath()
        WinampTheme.insetBorderLight.setStroke()
        path2.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        path2.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path2.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path2.lineWidth = 1
        path2.stroke()
    }

    // MARK: - Mouse Handling
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            resetToCenter()
            return
        }
        isDragging = true
        isUserInteracting = true
        updateValueFromMouse(event)
    }

    private func resetToCenter() {
        isUserInteracting = true
        value = (minValue + maxValue) / 2
        isUserInteracting = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValueFromMouse(event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isUserInteracting = false
    }

    private func updateValueFromMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let normalized: CGFloat

        if isVertical {
            normalized = max(0, min(1, point.y / bounds.height))
        } else {
            normalized = max(0, min(1, point.x / bounds.width))
        }

        value = minValue + Float(normalized) * (maxValue - minValue)
    }
}
