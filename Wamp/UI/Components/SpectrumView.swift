import Cocoa

class SpectrumView: NSView {
    var spectrumData: [Float] = [] { didSet { needsDisplay = true } }
    var barCount: Int = 26

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barWidth: CGFloat = 3
        let gap: CGFloat = 1
        let totalBars = min(barCount, Int(bounds.width / (barWidth + gap)))

        for i in 0..<totalBars {
            let dataIndex = i < spectrumData.count ? i : 0
            let amplitude = spectrumData.isEmpty ? Float(0) : min(1, spectrumData[dataIndex] * 10)
            let barHeight = CGFloat(amplitude) * bounds.height
            let x = CGFloat(i) * (barWidth + gap)
            let barRect = NSRect(x: x, y: 0, width: barWidth, height: max(1, barHeight))

            let gradient = NSGradient(starting: WinampTheme.spectrumBarBottom, ending: WinampTheme.spectrumBarTop)
            gradient?.draw(in: barRect, angle: 90)
        }
    }
}
