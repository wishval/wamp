import Cocoa

class LCDDisplay: NSView {
    var text: String = "" { didSet { scrollOffset = 0; needsDisplay = true } }
    var isScrolling = true

    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private let scrollSpeed: CGFloat = 0.5

    override init(frame: NSRect) {
        super.init(frame: frame)
        startScrolling()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startScrolling() {
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isScrolling, !self.text.isEmpty else { return }
            self.scrollOffset += self.scrollSpeed
            let textWidth = self.textSize().width + 30
            if self.scrollOffset > textWidth {
                self.scrollOffset = -self.bounds.width
            }
            self.needsDisplay = true
        }
    }

    private func textSize() -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]
        return text.size(withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]

        let size = text.size(withAttributes: attrs)
        let y = (bounds.height - size.height) / 2

        if size.width <= bounds.width || !isScrolling {
            text.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
        } else {
            // Scroll: draw text offset
            let displayText = text + "   ★   " + text
            displayText.draw(at: NSPoint(x: -scrollOffset, y: y), withAttributes: attrs)
        }
    }

    deinit {
        scrollTimer?.invalidate()
    }
}
