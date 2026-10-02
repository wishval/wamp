import Cocoa
import Combine

class LCDDisplay: NSView {
    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            prepareScrolling()
            needsDisplay = true
        }
    }
    var isScrolling = true

    private var textSheet: NSImage?
    private var renderedTitle: NSImage?
    private var renderedCycle: NSImage?
    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private let framesPerSecond: TimeInterval = 30
    private let scrollSpeed: CGFloat = 0.5
    private let separator = "   ***   "
    private var titleWidth: CGFloat = 0
    private var cycleText: String = ""
    private var cycleWidth: CGFloat = 0
    private var pauseTicksRemaining: Int = 0
    private let initialPauseSeconds: CGFloat = 1.5
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
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.prepareScrolling()
                self.needsDisplay = true
            }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var builtInAttributes: [NSAttributedString.Key: Any] {
        [.font: WinampTheme.trackTitleFont, .foregroundColor: WinampTheme.greenBright]
    }

    private func textWidth(_ str: String) -> CGFloat {
        WinampTheme.skinIsActive
            ? TextSpriteRenderer.width(of: str)
            : str.size(withAttributes: builtInAttributes).width
    }

    private func renderSkinnedText(_ string: String, width: CGFloat, sheet: NSImage) -> NSImage {
        let imageSize = NSSize(width: ceil(width), height: TextSpriteRenderer.glyphHeight)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .none
        TextSpriteRenderer.draw(string, at: .zero, sheet: sheet)
        return image
    }
    
    /// Measures the title once and, for skins, pre-renders it (and one
    /// title+separator cycle) to bitmaps so each scroll tick is a blit
    /// instead of a per-glyph sprite crop.
    private func prepareScrolling() {
        scrollOffset = 0
        pauseTicksRemaining = Int(framesPerSecond * initialPauseSeconds)
        textSheet = WinampTheme.provider.textSheet
        
        titleWidth = textWidth(text)
        cycleText = text + separator
        cycleWidth = textWidth(cycleText)

        renderedTitle = nil
        renderedCycle = nil
        
        if WinampTheme.skinIsActive, let sheet = textSheet, !text.isEmpty {
            renderedTitle = renderSkinnedText(text, width: titleWidth, sheet: sheet)
            renderedCycle = renderSkinnedText(cycleText, width: cycleWidth, sheet: sheet)
        }
        needsDisplay = true
    }
    
    private func startScrolling() {
        let timer = Timer(timeInterval: 1.0 / framesPerSecond, repeats: true) { [weak self] _ in
            guard let self = self, self.isScrolling, !self.text.isEmpty,
                  self.overlayText == nil, self.titleWidth > self.bounds.width
            else { return }

            if self.pauseTicksRemaining > 0 {
                self.pauseTicksRemaining -= 1
                return
            }

            self.scrollOffset += self.scrollSpeed
            if self.scrollOffset >= self.cycleWidth {
                self.scrollOffset -= self.cycleWidth
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
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
        guard textSheet != nil else { return }
        let y = (bounds.height - TextSpriteRenderer.glyphHeight) / 2
        if let overlay = overlayText, let sheet = textSheet {
            TextSpriteRenderer.draw(overlay, at: NSPoint(x: 2, y: y), sheet: sheet)
            return
        }

        guard !text.isEmpty else { return }
        NSGraphicsContext.current?.imageInterpolation = .none

        if titleWidth <= bounds.width || !isScrolling {
            renderedTitle?.draw(at: NSPoint(x: 2, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            var startX = 2.0 - scrollOffset
            while startX < bounds.width {
                renderedCycle?.draw(at: NSPoint(x: startX, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
                startX += cycleWidth
            }
        }
    }

    private func drawBuiltIn() {
        let attrs = builtInAttributes

        if let overlay = overlayText {
            let size = overlay.size(withAttributes: attrs)
            let y = (bounds.height - size.height) / 2
            overlay.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
            return
        }
        guard !text.isEmpty else { return }
        let y = (bounds.height - text.size(withAttributes: attrs).height) / 2

        if titleWidth <= bounds.width || !isScrolling {
            text.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
        } else {
            var startX = 2.0 - scrollOffset
            while startX < bounds.width {
                cycleText.draw(at: NSPoint(x: startX, y: y), withAttributes: attrs)
                startX += cycleWidth
            }
        }
    }

    deinit {
        scrollTimer?.invalidate()
        overlayClearTimer?.invalidate()
    }
}
