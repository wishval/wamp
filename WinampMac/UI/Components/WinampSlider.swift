import Cocoa

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

    override init(frame: NSRect) {
        super.init(frame: frame)
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
        let b = bounds

        if isVertical {
            drawVerticalSlider(in: b)
        } else {
            drawHorizontalSlider(in: b)
        }
    }

    private func drawHorizontalSlider(in rect: NSRect) {
        let trackY = rect.midY - 3
        let trackRect = NSRect(x: 1, y: trackY, width: rect.width - 2, height: 6)

        // Track background
        switch style {
        case .volume:
            let gradient = NSGradient(starting: WinampTheme.volumeBgStart, ending: WinampTheme.volumeBgEnd)
            gradient?.draw(in: trackRect, angle: 0)
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
            let gradient = NSGradient(starting: WinampTheme.volumeFillStart, ending: WinampTheme.volumeFillEnd)
            gradient?.draw(in: fillRect, angle: 0)
        default:
            let gradient = NSGradient(starting: WinampTheme.seekFillTop, ending: WinampTheme.seekFillBottom)
            gradient?.draw(in: fillRect, angle: 90)
        }

        // Thumb
        let thumbW: CGFloat = 14
        let thumbH: CGFloat = rect.height
        let thumbX = trackRect.minX + fillWidth - thumbW / 2
        let thumbRect = NSRect(x: max(0, thumbX), y: 0, width: thumbW, height: thumbH)
        drawThumb(thumbRect, isVolumeStyle: style == .volume)
    }

    private func drawVerticalSlider(in rect: NSRect) {
        let trackX = rect.midX - 5
        let trackRect = NSRect(x: trackX, y: 0, width: 10, height: rect.height)

        // Yellow-tinted EQ background
        let bgGradient = NSGradient(starting: WinampTheme.eqSliderBgTop, ending: WinampTheme.eqSliderBgBottom)
        bgGradient?.draw(in: trackRect, angle: 90)
        drawInsetBorder(trackRect)

        // Center line
        let centerY = rect.midY
        WinampTheme.eqSliderCenter.setStroke()
        let centerLine = NSBezierPath()
        centerLine.move(to: NSPoint(x: trackRect.minX + 2, y: centerY))
        centerLine.line(to: NSPoint(x: trackRect.maxX - 2, y: centerY))
        centerLine.lineWidth = 1
        centerLine.stroke()

        // Tick marks
        WinampTheme.eqSliderTick.setStroke()
        let tickPath = NSBezierPath()
        for i in stride(from: trackRect.minY + 2, to: trackRect.maxY, by: 3) {
            tickPath.move(to: NSPoint(x: rect.midX - 1, y: i))
            tickPath.line(to: NSPoint(x: rect.midX + 1, y: i))
        }
        tickPath.lineWidth = 0.5
        tickPath.stroke()

        // Fill from center
        let thumbY = rect.height * normalizedValue
        if value > 0 {
            let fillGradient = NSGradient(starting: WinampTheme.eqFillStart, ending: WinampTheme.eqFillEnd)
            fillGradient?.draw(in: NSRect(x: trackRect.minX + 3, y: centerY, width: 4, height: thumbY - centerY), angle: 90)
        } else if value < 0 {
            let fillGradient = NSGradient(starting: WinampTheme.eqFillStart, ending: WinampTheme.eqFillEnd)
            fillGradient?.draw(in: NSRect(x: trackRect.minX + 3, y: thumbY, width: 4, height: centerY - thumbY), angle: 270)
        }

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
        isDragging = true
        isUserInteracting = true
        updateValueFromMouse(event)
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
