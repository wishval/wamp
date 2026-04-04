import Cocoa

class TitleBarView: NSView {
    var titleText: String = "WAMP" { didSet { needsDisplay = true } }
    var showButtons: Bool = true
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        // Gradient background
        let gradient = NSGradient(colors: [
            WinampTheme.titleBarTop,
            WinampTheme.titleBarBottom,
            NSColor(hex: 0x3A4460),
            WinampTheme.titleBarBottom
        ])
        gradient?.draw(in: b, angle: 90)

        // Calculate text width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.titleBarFont,
            .foregroundColor: WinampTheme.titleBarText
        ]
        let textSize = titleText.size(withAttributes: attrs)
        let textX = (b.width - textSize.width) / 2
        let textY = (b.height - textSize.height) / 2

        // Draw stripes on both sides
        let stripeMargin: CGFloat = 4
        let stripeGap: CGFloat = 4

        // Left stripes
        drawStripes(in: NSRect(
            x: stripeMargin,
            y: (b.height - 8) / 2,
            width: textX - stripeGap - stripeMargin,
            height: 8
        ))

        // Right stripes
        let rightStart = textX + textSize.width + stripeGap
        let rightEnd = showButtons ? b.width - 30 : b.width - stripeMargin
        if rightEnd > rightStart {
            drawStripes(in: NSRect(
                x: rightStart,
                y: (b.height - 8) / 2,
                width: rightEnd - rightStart,
                height: 8
            ))
        }

        // Title text
        titleText.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

        // Window buttons
        if showButtons {
            let btnSize: CGFloat = 9
            let btnY = (b.height - btnSize) / 2

            drawWindowButton(
                NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize),
                symbol: "−"
            )
            drawWindowButton(
                NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize),
                symbol: "×"
            )
        }

        // Bottom border
        WinampTheme.insetBorderDark.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: 0, y: 0))
        borderPath.line(to: NSPoint(x: b.width, y: 0))
        borderPath.lineWidth = 1
        borderPath.stroke()
    }

    private func drawStripes(in rect: NSRect) {
        guard rect.width > 2 else { return }
        var y = rect.minY
        while y < rect.maxY - 1 {
            WinampTheme.titleBarStripe1.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += 1
            WinampTheme.titleBarStripe2.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += 2
        }
    }

    private func drawWindowButton(_ rect: NSRect, symbol: String) {
        NSColor(hex: 0x3A4060).setFill()
        rect.fill()

        // 3D border
        WinampTheme.buttonBorderLight.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.lineWidth = 1
        path.stroke()

        WinampTheme.buttonBorderDark.setStroke()
        let path2 = NSBezierPath()
        path2.move(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path2.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path2.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path2.lineWidth = 1
        path2.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6),
            .foregroundColor: NSColor(hex: 0xA0A8C0)
        ]
        let size = symbol.size(withAttributes: attrs)
        symbol.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    // MARK: - Click handling for window buttons
    override func mouseUp(with event: NSEvent) {
        guard showButtons else { return }
        let point = convert(event.locationInWindow, from: nil)
        let b = bounds
        let btnSize: CGFloat = 9
        let btnY = (b.height - btnSize) / 2

        let minimizeRect = NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize)
        let closeRect = NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize)

        if closeRect.contains(point) {
            onClose?()
        } else if minimizeRect.contains(point) {
            onMinimize?()
        }
    }
}
