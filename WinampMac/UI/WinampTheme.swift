import Cocoa

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

enum WinampTheme {
    // MARK: - Frame
    static let frameBackground = NSColor(hex: 0x3C4250)
    static let frameBorderLight = NSColor(hex: 0x5A6070)
    static let frameBorderDark = NSColor(hex: 0x20242C)

    // MARK: - Title Bar
    static let titleBarTop = NSColor(hex: 0x4A5268)
    static let titleBarBottom = NSColor(hex: 0x222840)
    static let titleBarStripe1 = NSColor(hex: 0xB8860B)
    static let titleBarStripe2 = NSColor(hex: 0xDAA520)
    static let titleBarText = NSColor(hex: 0xC0C8E0)

    // MARK: - LCD / Display
    static let lcdBackground = NSColor.black
    static let greenBright = NSColor(hex: 0x00E000)
    static let greenSecondary = NSColor(hex: 0x00A800)
    static let greenDim = NSColor(hex: 0x1A3A1A)
    static let greenDimText = NSColor(hex: 0x1A5A1A)

    // MARK: - Playlist
    static let white = NSColor.white
    static let selectionBlue = NSColor(hex: 0x0000C0)

    // MARK: - Buttons
    static let buttonFaceTop = NSColor(hex: 0x4A4E58)
    static let buttonFaceBottom = NSColor(hex: 0x3A3E48)
    static let buttonBorderLight = NSColor(hex: 0x5A5E68)
    static let buttonBorderDark = NSColor(hex: 0x2A2E38)
    static let buttonTextActive = NSColor(hex: 0x00E000)
    static let buttonTextInactive = NSColor(hex: 0x4A5A6A)
    static let buttonIconDefault = NSColor(hex: 0x8A9AAA)

    // MARK: - Seek / Balance Sliders
    static let seekFillTop = NSColor(hex: 0x6A8A40)
    static let seekFillBottom = NSColor(hex: 0x4A6A28)
    static let seekThumbTop = NSColor(hex: 0x9AA060)
    static let seekThumbMid = NSColor(hex: 0x6A7A40)
    static let seekThumbBottom = NSColor(hex: 0x4A5A28)
    static let seekThumbBorderLight = NSColor(hex: 0xB0BA70)
    static let seekThumbBorderDark = NSColor(hex: 0x3A4A20)

    // MARK: - Volume Slider
    static let volumeBgStart = NSColor(hex: 0x1A1200)
    static let volumeBgEnd = NSColor(hex: 0xAA7000)
    static let volumeFillStart = NSColor(hex: 0x8A6A20)
    static let volumeFillEnd = NSColor(hex: 0xFFAA00)
    static let volumeThumbTop = NSColor(hex: 0xDAA520)
    static let volumeThumbMid = NSColor(hex: 0xAA7A10)
    static let volumeThumbBottom = NSColor(hex: 0x8A6000)
    static let volumeThumbBorderLight = NSColor(hex: 0xEEBB40)
    static let volumeThumbBorderDark = NSColor(hex: 0x6A5000)

    // MARK: - EQ Sliders
    static let eqSliderBgTop = NSColor(hex: 0x2A2810)
    static let eqSliderBgBottom = NSColor(hex: 0x332E14)
    static let eqSliderTick = NSColor(hex: 0x3A3518)
    static let eqSliderCenter = NSColor(hex: 0x4A4520)
    static let eqThumbTop = NSColor(hex: 0xB0BA60)
    static let eqThumbMid = NSColor(hex: 0x8A9A40)
    static let eqThumbBottom = NSColor(hex: 0x6A7A28)
    static let eqThumbBorderLight = NSColor(hex: 0xD0DA80)
    static let eqThumbBorderDark = NSColor(hex: 0x4A5A18)
    static let eqFillStart = NSColor(hex: 0x2A6A10)
    static let eqFillEnd = NSColor(hex: 0x4A8A20)
    static let eqBandLabelColor = NSColor(hex: 0x6A8A6A)
    static let eqDbLabelColor = NSColor(hex: 0x6A7A6A)

    // MARK: - Spectrum
    static let spectrumBarBottom = NSColor(hex: 0x00C000)
    static let spectrumBarTop = NSColor(hex: 0xE0E000)

    // MARK: - Inset border (LCD panels)
    static let insetBorderDark = NSColor(hex: 0x1A1E28)
    static let insetBorderLight = NSColor(hex: 0x4A4E58)

    // MARK: - Fonts
    static let titleBarFont = NSFont(name: "Tahoma-Bold", size: 8) ?? NSFont.boldSystemFont(ofSize: 8)
    static let trackTitleFont = NSFont(name: "Tahoma", size: 9) ?? NSFont.systemFont(ofSize: 9)
    static let bitrateFont = NSFont(name: "Tahoma", size: 7) ?? NSFont.systemFont(ofSize: 7)
    static let smallLabelFont = NSFont(name: "Tahoma", size: 6) ?? NSFont.systemFont(ofSize: 6)
    static let buttonFont = NSFont(name: "Tahoma-Bold", size: 7) ?? NSFont.boldSystemFont(ofSize: 7)
    static let playlistFont = NSFont(name: "ArialMT", size: 8.5) ?? NSFont.systemFont(ofSize: 8.5)
    static let eqLabelFont = NSFont(name: "Tahoma", size: 6) ?? NSFont.systemFont(ofSize: 6)

    // MARK: - Dimensions
    static let windowWidth: CGFloat = 275
    static let mainPlayerHeight: CGFloat = 148
    static let equalizerHeight: CGFloat = 130
    static let playlistMinHeight: CGFloat = 232
    static let titleBarHeight: CGFloat = 16
    static let transportButtonSize = NSSize(width: 22, height: 18)
}
