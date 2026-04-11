import Cocoa
import Combine

class LCDDisplay: NSView {
    var text: String = "" { didSet { scrollOffset = 0; needsDisplay = true } }
    var isScrolling = true

    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private let scrollSpeed: CGFloat = 0.5
    private var skinObserver: AnyCancellable?
    private var overlayText: String?
    private var overlayClearTimer: Timer?

    func showOverlay(_ text: String, duration: TimeInterval = 1.0) {
        overlayText = text
        needsDisplay = true
        overlayClearTimer?.invalidate()
        overlayClearTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.overlayText = nil
            self?.needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        startScrolling()
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
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
        if WinampTheme.skinIsActive {
            drawSkinned()
        } else {
            drawBuiltIn()
        }
    }

    private func drawSkinned() {
        guard let textSheet = WinampTheme.provider.textSheet else { return }
        if let overlay = overlayText {
            let y = (bounds.height - TextSpriteRenderer.glyphHeight) / 2
            TextSpriteRenderer.draw(overlay, at: NSPoint(x: 2, y: y), sheet: textSheet)
            return
        }
        guard !text.isEmpty else { return }
        let textWidth = TextSpriteRenderer.width(of: text)
        let y = (bounds.height - TextSpriteRenderer.glyphHeight) / 2

        if textWidth <= bounds.width || !isScrolling {
            TextSpriteRenderer.draw(text, at: NSPoint(x: 2, y: y), sheet: textSheet)
        } else {
            let separator = "   *   "
            let combined = text + separator + text
            TextSpriteRenderer.draw(combined, at: NSPoint(x: -scrollOffset, y: y), sheet: textSheet)
        }
    }

    private func drawBuiltIn() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]

        if let overlay = overlayText {
            let size = overlay.size(withAttributes: attrs)
            let y = (bounds.height - size.height) / 2
            overlay.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
            return
        }

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
        overlayClearTimer?.invalidate()
    }
}
