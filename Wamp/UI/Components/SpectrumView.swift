import Cocoa
import Combine

class SpectrumView: NSView {
    var spectrumData: [Float] = [] { didSet { needsDisplay = true } }
    var barCount: Int = 26
    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barWidth: CGFloat = 3
        let gap: CGFloat = 1
        let totalBars = min(barCount, Int(bounds.width / (barWidth + gap)))

        // Pick gradient endpoints from the active skin's viscolors when skinned;
        // otherwise use the built-in defaults. viscolors[2..17] is the spectrum range,
        // viscolors[18..23] are peak/highlight colors per Winamp convention.
        let viscolors = WinampTheme.provider.viscolors
        let bottom: NSColor
        let top: NSColor
        if WinampTheme.skinIsActive, viscolors.count >= 18 {
            bottom = viscolors[2]
            top = viscolors[17]
        } else {
            bottom = WinampTheme.spectrumBarBottom
            top = WinampTheme.spectrumBarTop
        }
        let gradient = NSGradient(starting: bottom, ending: top)

        for i in 0..<totalBars {
            let dataIndex = i < spectrumData.count ? i : 0
            let amplitude = spectrumData.isEmpty ? Float(0) : min(1, spectrumData[dataIndex] * 10)
            let barHeight = CGFloat(amplitude) * bounds.height
            let x = CGFloat(i) * (barWidth + gap)
            let barRect = NSRect(x: x, y: 0, width: barWidth, height: max(1, barHeight))
            gradient?.draw(in: barRect, angle: 90)
        }
    }
}
