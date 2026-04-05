import Cocoa

class TransportBar: NSView {
    var onPrevious: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onNext: (() -> Void)?
    var onEject: (() -> Void)?

    private(set) var prevButton: WinampButton!
    private(set) var playButton: WinampButton!
    private(set) var pauseButton: WinampButton!
    private(set) var stopButton: WinampButton!
    private(set) var nextButton: WinampButton!
    private(set) var ejectButton: WinampButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        let buttons = makeButtons()
        prevButton = buttons[0]
        playButton = buttons[1]
        pauseButton = buttons[2]
        stopButton = buttons[3]
        nextButton = buttons[4]
        ejectButton = buttons[5]

        prevButton.drawIcon = { rect, _ in self.drawPrevIcon(in: rect) }
        playButton.drawIcon = { rect, active in self.drawPlayIcon(in: rect, active: active) }
        pauseButton.drawIcon = { rect, _ in self.drawPauseIcon(in: rect) }
        stopButton.drawIcon = { rect, _ in self.drawStopIcon(in: rect) }
        nextButton.drawIcon = { rect, _ in self.drawNextIcon(in: rect) }
        ejectButton.drawIcon = { rect, _ in self.drawEjectIcon(in: rect) }

        prevButton.onClick = { [weak self] in self?.onPrevious?() }
        playButton.onClick = { [weak self] in self?.onPlay?() }
        pauseButton.onClick = { [weak self] in self?.onPause?() }
        stopButton.onClick = { [weak self] in self?.onStop?() }
        nextButton.onClick = { [weak self] in self?.onNext?() }
        ejectButton.onClick = { [weak self] in self?.onEject?() }

        for btn in buttons {
            btn.style = .transport
            addSubview(btn)
        }
    }

    private func makeButtons() -> [WinampButton] {
        (0..<6).map { _ in WinampButton(title: "", style: .transport) }
    }

    override func layout() {
        super.layout()
        let btnW: CGFloat = 22
        let btnH: CGFloat = 18
        let gap: CGFloat = 1
        let buttons = [prevButton!, playButton!, pauseButton!, stopButton!, nextButton!, ejectButton!]
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: CGFloat(i) * (btnW + gap), y: 0, width: btnW, height: btnH)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 6 * 22 + 5, height: 18)
    }

    // MARK: - Icon Drawing
    private func drawPrevIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        let cx = rect.midX
        let cy = rect.midY
        NSRect(x: cx - 5, y: cy - 4, width: 2, height: 8).fill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx + 3, y: cy - 4))
        tri.line(to: NSPoint(x: cx - 2, y: cy))
        tri.line(to: NSPoint(x: cx + 3, y: cy + 4))
        tri.close()
        tri.fill()
    }

    private func drawPlayIcon(in rect: NSRect, active: Bool) {
        let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonIconDefault
        color.setFill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: rect.midX - 3, y: rect.midY - 4))
        tri.line(to: NSPoint(x: rect.midX + 4, y: rect.midY))
        tri.line(to: NSPoint(x: rect.midX - 3, y: rect.midY + 4))
        tri.close()
        tri.fill()
    }

    private func drawPauseIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 3, height: 8).fill()
        NSRect(x: rect.midX + 1, y: rect.midY - 4, width: 3, height: 8).fill()
    }

    private func drawStopIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8).fill()
    }

    private func drawNextIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        let cx = rect.midX
        let cy = rect.midY
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx - 3, y: cy - 4))
        tri.line(to: NSPoint(x: cx + 2, y: cy))
        tri.line(to: NSPoint(x: cx - 3, y: cy + 4))
        tri.close()
        tri.fill()
        NSRect(x: cx + 3, y: cy - 4, width: 2, height: 8).fill()
    }

    private func drawEjectIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        let cx = rect.midX
        let cy = rect.midY
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx - 4, y: cy - 1))
        tri.line(to: NSPoint(x: cx, y: cy + 4))
        tri.line(to: NSPoint(x: cx + 4, y: cy - 1))
        tri.close()
        tri.fill()
        NSRect(x: cx - 4, y: cy - 4, width: 8, height: 2).fill()
    }
}
