// Wamp/UI/Components/PlaylistSkinScroller.swift
// Custom scroll thumb that draws .playlistScrollHandle from pledit.bmp.
// Replaces the native NSScroller when a Winamp skin is active.

import AppKit

final class PlaylistSkinScroller: NSView {
    private static let handleW: CGFloat = 8
    private static let handleH: CGFloat = 18

    weak var scrollView: NSScrollView?
    private var pressed = false
    private var dragOffsetWithinHandle: CGFloat = 0
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func attach(to scrollView: NSScrollView) {
        self.scrollView = scrollView
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    /// Returns (handleY in our bounds, fraction 0..1 of scroll progress) or nil
    /// when content fits within the visible area (no scrolling needed).
    private func currentHandleY() -> CGFloat? {
        guard let scrollView = scrollView, let doc = scrollView.documentView else { return nil }
        let contentH = doc.bounds.height
        let visibleH = scrollView.contentView.bounds.height
        guard contentH > visibleH + 0.5 else { return nil }
        let scrollY = scrollView.contentView.bounds.origin.y
        let maxScroll = contentH - visibleH
        let frac = max(0, min(1, scrollY / maxScroll))
        // Document view is flipped (NSTableView), so larger scrollY == farther down.
        // In our (non-flipped) bounds the handle should sit lower as frac grows.
        let trackH = max(0, bounds.height - Self.handleH)
        let handleY = trackH - frac * trackH
        return handleY
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let handleY = currentHandleY() else { return }
        guard let sprite = WinampTheme.sprite(.playlistScrollHandle(pressed: pressed)) else { return }
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        sprite.draw(in: NSRect(x: 0, y: handleY, width: Self.handleW, height: Self.handleH))
        if let prev = prev { ctx?.imageInterpolation = prev }
    }

    // MARK: - Mouse interaction

    override func mouseDown(with event: NSEvent) {
        guard let _ = scrollView, let handleY = currentHandleY() else { return }
        let p = convert(event.locationInWindow, from: nil)
        let handleRect = NSRect(x: 0, y: handleY, width: Self.handleW, height: Self.handleH)
        if handleRect.contains(p) {
            dragOffsetWithinHandle = p.y - handleY
        } else {
            // Click on track — center the handle on the click and start dragging.
            dragOffsetWithinHandle = Self.handleH / 2
            scrollHandleTo(viewY: p.y - dragOffsetWithinHandle)
        }
        pressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        scrollHandleTo(viewY: p.y - dragOffsetWithinHandle)
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        needsDisplay = true
    }

    private func scrollHandleTo(viewY: CGFloat) {
        guard let scrollView = scrollView, let doc = scrollView.documentView else { return }
        let contentH = doc.bounds.height
        let visibleH = scrollView.contentView.bounds.height
        let maxScroll = contentH - visibleH
        guard maxScroll > 0 else { return }
        let trackH = max(1, bounds.height - Self.handleH)
        let clampedY = max(0, min(trackH, viewY))
        let frac = 1 - (clampedY / trackH)
        let newScrollY = frac * maxScroll
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: newScrollY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
