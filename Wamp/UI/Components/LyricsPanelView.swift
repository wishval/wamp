import Cocoa
import Combine

/// One rendered row of the lyrics panel.
enum LyricsDisplayLine: Equatable {
    /// Track title, drawn in the "current" colour.
    case header(String)
    /// Secondary note ("Synced lyrics", "No lyrics…"), drawn dimmed.
    case status(String)
    /// A lyric line; `index` is its position in the lyrics block.
    case lyric(index: Int, text: String)
    case blank
}

/// Winamp-styled lyrics window chrome. Mirrors `PlaylistView`: when a skin
/// is active it tiles pledit.bmp (corners, top/side tiles, a slice of the
/// bottom tile) and spells the title with text.bmp; otherwise it uses the
/// built-in `TitleBarView` + angular inset frame. The text itself is drawn
/// by `LyricsContentView` in the playlist palette and font, so it reads as
/// part of the player rather than a native Mac text view.
final class LyricsPanelView: NSView {
    var onClose: (() -> Void)?

    private let titleBar = TitleBarView()
    private let scrollView = AlwaysVisibleScrollView()
    private let content = LyricsContentView()
    private let skinScroller = PlaylistSkinScroller()
    private var skinObserver: AnyCancellable?
    private var dragOrigin: NSPoint?

    // pledit frame metrics (see PlaylistView.layoutSkinned).
    private static let skinTopH: CGFloat = 20
    private static let skinBottomH: CGFloat = 14   // bottom slice of the 38px tile
    private static let skinLeftW: CGFloat = 12
    private static let skinRightW: CGFloat = 20

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor

        titleBar.titleText = "WAMP LYRICS"
        titleBar.showButtons = true
        titleBar.onClose = { [weak self] in self?.onClose?() }
        titleBar.onMinimize = { [weak self] in self?.window?.miniaturize(nil) }
        addSubview(titleBar)

        scrollView.documentView = content
        scrollView.drawsBackground = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        skinScroller.attach(to: scrollView)
        addSubview(skinScroller)

        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySkinVisibility()
                self?.needsDisplay = true
            }
        applySkinVisibility()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Content API

    var lines: [LyricsDisplayLine] {
        get { content.lines }
        set { content.lines = newValue; needsLayout = true }
    }

    var currentLine: Int? {
        get { content.currentLine }
        set { content.currentLine = newValue }
    }

    /// Scroll so the current lyric line sits in the middle of the view.
    func scrollToCurrentLine(animated: Bool = true) {
        guard let rect = content.rectOfCurrentLine() else { return }
        let visible = scrollView.contentView.bounds
        let maxY = max(0, content.bounds.height - visible.height)
        let target = NSPoint(x: 0, y: min(maxY, max(0, rect.midY - visible.height / 2)))
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                scrollView.contentView.animator().setBoundsOrigin(target)
            }
        } else {
            scrollView.contentView.setBoundsOrigin(target)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func scrollToTop() {
        scrollView.contentView.setBoundsOrigin(.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Skin / layout

    private func applySkinVisibility() {
        let active = WinampTheme.skinIsActive
        titleBar.isHidden = active
        scrollView.hasVerticalScroller = !active
        skinScroller.isHidden = !active
        let bg = active ? WinampTheme.provider.playlistStyle.normalBG : NSColor.black
        scrollView.backgroundColor = bg
        content.needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        if WinampTheme.skinIsActive {
            titleBar.frame = .zero
            scrollView.frame = NSRect(
                x: Self.skinLeftW,
                y: Self.skinBottomH,
                width: w - Self.skinLeftW - Self.skinRightW,
                height: h - Self.skinTopH - Self.skinBottomH
            )
            skinScroller.frame = NSRect(x: w - Self.skinRightW + 6, y: Self.skinBottomH,
                                        width: 8, height: h - Self.skinTopH - Self.skinBottomH)
        } else {
            let pad: CGFloat = 3
            titleBar.frame = NSRect(x: 0, y: h - WinampTheme.titleBarHeight,
                                    width: w, height: WinampTheme.titleBarHeight)
            scrollView.frame = NSRect(x: pad + 1, y: pad + 1,
                                      width: w - 2 * pad - 2,
                                      height: h - WinampTheme.titleBarHeight - 2 * pad - 2)
        }
        content.reflow(width: scrollView.contentSize.width)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if WinampTheme.skinIsActive {
            drawSkinned()
        } else {
            drawBuiltIn()
        }
    }

    private func drawBuiltIn() {
        // Inset LCD-style bezel around the text area, like the player's panels.
        let r = scrollView.frame.insetBy(dx: -1, dy: -1)
        WinampTheme.insetBorderDark.setStroke()
        let dark = NSBezierPath()
        dark.move(to: NSPoint(x: r.minX + 0.5, y: r.minY + 0.5))
        dark.line(to: NSPoint(x: r.minX + 0.5, y: r.maxY - 0.5))
        dark.line(to: NSPoint(x: r.maxX - 0.5, y: r.maxY - 0.5))
        dark.stroke()
        WinampTheme.insetBorderLight.setStroke()
        let light = NSBezierPath()
        light.move(to: NSPoint(x: r.maxX - 0.5, y: r.maxY - 0.5))
        light.line(to: NSPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
        light.line(to: NSPoint(x: r.minX + 0.5, y: r.minY + 0.5))
        light.stroke()
    }

    private func drawSkinned() {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev { ctx?.imageInterpolation = prev } }

        let isActive = window?.isKeyWindow ?? true
        let w = bounds.width
        let h = bounds.height
        let topH = Self.skinTopH

        // Top row: corners + tiles all the way across (no baked "PLAYLIST"
        // centrepiece), then the title spelled with the skin's bitmap font.
        if let topTile = WinampTheme.sprite(.playlistTopTile(active: isActive)) {
            var x: CGFloat = 25
            while x < w - 25 {
                topTile.draw(in: NSRect(x: x, y: h - topH, width: min(25, w - 25 - x), height: topH))
                x += 25
            }
        }
        if let tl = WinampTheme.sprite(.playlistTopLeftCorner(active: isActive)) {
            tl.draw(in: NSRect(x: 0, y: h - topH, width: 25, height: topH))
        }
        if let tr = WinampTheme.sprite(.playlistTopRightCorner(active: isActive)) {
            tr.draw(in: NSRect(x: w - 25, y: h - topH, width: 25, height: topH))
        }
        if let textSheet = WinampTheme.provider.textSheet {
            let title = "LYRICS"
            let tw = TextSpriteRenderer.width(of: title)
            let ty = h - topH + (topH - TextSpriteRenderer.glyphHeight) / 2 - 1
            TextSpriteRenderer.draw(title, at: NSPoint(x: ((w - tw) / 2).rounded(), y: ty.rounded()), sheet: textSheet)
        }

        // Sides
        let bottomH = Self.skinBottomH
        if let lt = WinampTheme.sprite(.playlistLeftTile) {
            var y = bottomH
            while y < h - topH {
                lt.draw(in: NSRect(x: 0, y: y, width: 12, height: min(29, h - topH - y)))
                y += 29
            }
        }
        if let rt = WinampTheme.sprite(.playlistRightTile) {
            var y = bottomH
            while y < h - topH {
                rt.draw(in: NSRect(x: w - 20, y: y, width: 20, height: min(29, h - topH - y)))
                y += 29
            }
        }

        // Bottom: the lower slice of the plain 25×38 bottom tile carries the
        // frame's bottom edge without the playlist's baked-in button strips.
        if let bt = WinampTheme.sprite(.playlistBottomTile) {
            let src = NSRect(x: 0, y: 0, width: 25, height: bottomH)
            var x: CGFloat = 0
            while x < w {
                let width = min(25, w - x)
                bt.draw(in: NSRect(x: x, y: 0, width: width, height: bottomH),
                        from: NSRect(x: 0, y: 0, width: width, height: src.height),
                        operation: .sourceOver, fraction: 1)
                x += 25
            }
        }
    }

    // MARK: - Mouse (skinned: drag from title, close button in TR corner)

    /// pledit's close box sits 3px from the top-right, 9×9 (webamp metrics).
    private var skinnedCloseRect: NSRect {
        NSRect(x: bounds.width - 12, y: bounds.height - 12, width: 9, height: 9)
    }

    override func mouseDown(with event: NSEvent) {
        guard WinampTheme.skinIsActive else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if skinnedCloseRect.contains(point) { return }
        if point.y >= bounds.height - Self.skinTopH {
            dragOrigin = event.locationInWindow
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else { super.mouseDragged(with: event); return }
        let current = event.locationInWindow
        var frame = win.frame
        frame.origin.x += current.x - origin.x
        frame.origin.y += current.y - origin.y
        win.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = dragOrigin != nil
        dragOrigin = nil
        if WinampTheme.skinIsActive, !wasDragging {
            let point = convert(event.locationInWindow, from: nil)
            if skinnedCloseRect.contains(point) { onClose?(); return }
        }
        super.mouseUp(with: event)
    }
}

/// Document view that paints the lyric lines. Top-down (flipped) so the
/// first line is at the top like the playlist. Colours and font come from
/// the active skin's pledit palette (or Wamp's built-in green-on-black).
final class LyricsContentView: NSView {
    var lines: [LyricsDisplayLine] = [] {
        didSet { reflow(width: layoutWidth); needsDisplay = true }
    }
    var currentLine: Int? {
        didSet { if oldValue != currentLine { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    private var layoutWidth: CGFloat = 0
    private var rowRects: [NSRect] = []
    private static let inset = NSEdgeInsets(top: 6, left: 6, bottom: 8, right: 6)
    private static let lineGap: CGFloat = 3

    private var font: NSFont {
        if WinampTheme.skinIsActive {
            return NSFont(name: WinampTheme.provider.playlistStyle.font, size: 8) ?? NSFont.systemFont(ofSize: 8)
        }
        return WinampTheme.playlistFont
    }

    private func attributes(for line: LyricsDisplayLine, isCurrent: Bool) -> [NSAttributedString.Key: Any] {
        let skinned = WinampTheme.skinIsActive
        let style = WinampTheme.provider.playlistStyle
        let normal = skinned ? style.normal : WinampTheme.greenBright
        let current = skinned ? style.current : WinampTheme.white
        let secondary = skinned ? style.normal.withAlphaComponent(0.6) : WinampTheme.greenSecondary
        let color: NSColor
        switch line {
        case .header: color = current
        case .status: color = secondary
        case .lyric: color = isCurrent ? current : normal
        case .blank: color = normal
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func text(of line: LyricsDisplayLine) -> String {
        switch line {
        case .header(let s), .status(let s): return s
        case .lyric(_, let s): return s.isEmpty ? " " : s
        case .blank: return " "
        }
    }

    /// Recompute wrapped row rects for `width` and resize the document.
    func reflow(width: CGFloat) {
        layoutWidth = width
        let textWidth = max(10, width - Self.inset.left - Self.inset.right)
        var y = Self.inset.top
        var rects: [NSRect] = []
        for line in lines {
            let attrs = attributes(for: line, isCurrent: false)
            let bounding = (text(of: line) as NSString).boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            let h = ceil(bounding.height) + Self.lineGap
            rects.append(NSRect(x: Self.inset.left, y: y, width: textWidth, height: h))
            y += h
        }
        rowRects = rects
        let height = y + Self.inset.bottom
        if abs(frame.height - height) > 0.5 || abs(frame.width - width) > 0.5 {
            setFrameSize(NSSize(width: width, height: max(height, superview?.bounds.height ?? 0)))
        }
        needsDisplay = true
    }

    func rectOfCurrentLine() -> NSRect? {
        guard let current = currentLine else { return nil }
        for (i, line) in lines.enumerated() {
            if case .lyric(let idx, _) = line, idx == current, i < rowRects.count {
                return rowRects[i]
            }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let skinned = WinampTheme.skinIsActive
        let style = WinampTheme.provider.playlistStyle
        (skinned ? style.normalBG : NSColor.black).setFill()
        bounds.fill()

        for (i, line) in lines.enumerated() where i < rowRects.count {
            let rect = rowRects[i]
            guard rect.intersects(dirtyRect) else { continue }
            var isCurrent = false
            if case .lyric(let idx, _) = line, idx == currentLine {
                isCurrent = true
                // Highlight bar in the skin's selection colour, full width.
                (skinned ? style.selectedBG : WinampTheme.selectionBlue).setFill()
                NSRect(x: 0, y: rect.minY - 1, width: bounds.width, height: rect.height).fill()
            }
            let attrs = attributes(for: line, isCurrent: isCurrent)
            (text(of: line) as NSString).draw(
                with: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.lineGap),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
        }
    }
}
