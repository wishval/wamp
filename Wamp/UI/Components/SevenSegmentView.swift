import Cocoa
import Combine

class SevenSegmentView: NSView {
    var timeInSeconds: TimeInterval = 0 { didSet { needsDisplay = true } }
    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    // Segment layout: 7 segments per digit (a-g), standard arrangement
    // a=top, b=topRight, c=bottomRight, d=bottom, e=bottomLeft, f=topLeft, g=middle
    private let digitSegments: [[Bool]] = [
        [true,  true,  true,  true,  true,  true,  false], // 0
        [false, true,  true,  false, false, false, false], // 1
        [true,  true,  false, true,  true,  false, true],  // 2
        [true,  true,  true,  true,  false, false, true],  // 3
        [false, true,  true,  false, false, true,  true],  // 4
        [true,  false, true,  true,  false, true,  true],  // 5
        [true,  false, true,  true,  true,  true,  true],  // 6
        [true,  true,  true,  false, false, false, false], // 7
        [true,  true,  true,  true,  true,  true,  true],  // 8
        [true,  true,  true,  true,  false, true,  true],  // 9
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalSeconds = Int(max(0, timeInSeconds))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if WinampTheme.skinIsActive {
            drawSkinned(minutes: minutes, seconds: seconds)
            return
        }

        let digitWidth: CGFloat = 14
        let colonWidth: CGFloat = 6
        let digitHeight = bounds.height

        // Layout: M : S S (or MM : SS if >= 10 min)
        var digits: [Int] = []
        if minutes >= 10 {
            digits.append(minutes / 10)
        }
        digits.append(minutes % 10)

        let totalWidth = CGFloat(digits.count + 2) * digitWidth + colonWidth
        var x = (bounds.width - totalWidth) / 2

        // Minutes digits
        for d in digits {
            drawDigit(d, at: NSRect(x: x, y: 0, width: digitWidth, height: digitHeight))
            x += digitWidth
        }

        // Colon
        drawColon(at: NSRect(x: x, y: 0, width: colonWidth, height: digitHeight))
        x += colonWidth

        // Seconds
        drawDigit(seconds / 10, at: NSRect(x: x, y: 0, width: digitWidth, height: digitHeight))
        x += digitWidth
        drawDigit(seconds % 10, at: NSRect(x: x, y: 0, width: digitWidth, height: digitHeight))
    }

    /// Skinned path: always MM:SS, native 9×13 digit sprites at the exact
    /// Webamp positions inside the #time container. The colon is baked into
    /// main.bmp at the gap between the minute and second digits.
    private func drawSkinned(minutes: Int, seconds: Int) {
        let mm = min(99, minutes)
        let digits = [mm / 10, mm % 10, seconds / 10, seconds % 10]
        // Local x offsets inside a 59-wide #time container (Webamp CSS).
        let xs: [CGFloat] = [9, 21, 39, 51]
        let size = NSSize(width: 9, height: 13)
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }
        for (i, d) in digits.enumerated() {
            guard let sprite = WinampTheme.sprite(.digit(d)) else { continue }
            sprite.draw(in: NSRect(x: xs[i], y: 0, width: size.width, height: size.height))
        }
    }

    private func drawDigit(_ digit: Int, at rect: NSRect) {
        guard digit >= 0, digit <= 9 else { return }
        // Sprite path: blit numbers.bmp glyph if a skin is loaded.
        if WinampTheme.skinIsActive, let sprite = WinampTheme.sprite(.digit(digit)) {
            let ctx = NSGraphicsContext.current
            let prev = ctx?.imageInterpolation
            ctx?.imageInterpolation = .none
            sprite.draw(in: rect)
            if let prev = prev { ctx?.imageInterpolation = prev }
            return
        }
        let segs = digitSegments[digit]
        let w = rect.width - 2
        let h = rect.height - 2
        let x = rect.minX + 1
        let y = rect.minY + 1
        let t: CGFloat = 2 // segment thickness
        let mid = y + h / 2

        let segRects: [NSRect] = [
            NSRect(x: x + t, y: y + h - t, width: w - 2 * t, height: t),       // a top
            NSRect(x: x + w - t, y: mid, width: t, height: h / 2 - t),          // b topRight
            NSRect(x: x + w - t, y: y + t, width: t, height: h / 2 - t),        // c bottomRight
            NSRect(x: x + t, y: y, width: w - 2 * t, height: t),                // d bottom
            NSRect(x: x, y: y + t, width: t, height: h / 2 - t),                // e bottomLeft
            NSRect(x: x, y: mid, width: t, height: h / 2 - t),                  // f topLeft
            NSRect(x: x + t, y: mid - t / 2, width: w - 2 * t, height: t),      // g middle
        ]

        for (i, segRect) in segRects.enumerated() {
            let color = segs[i] ? WinampTheme.greenBright : WinampTheme.greenDim
            color.setFill()
            segRect.fill()
        }
    }

    private func drawColon(at rect: NSRect) {
        let dotSize: CGFloat = 2
        let cx = rect.midX - dotSize / 2

        WinampTheme.greenBright.setFill()
        NSRect(x: cx, y: rect.midY + 3, width: dotSize, height: dotSize).fill()
        NSRect(x: cx, y: rect.midY - 3 - dotSize, width: dotSize, height: dotSize).fill()
    }
}
