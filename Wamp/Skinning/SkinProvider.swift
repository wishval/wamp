// Wamp/Skinning/SkinProvider.swift
// Provider protocol + BuiltInSkin (no skin loaded). See spec §6.

import AppKit

protocol SkinProvider: AnyObject {
    /// Returns the requested sprite as an NSImage, or nil if the underlying sheet is missing.
    func sprite(_ key: SpriteKey) -> NSImage?

    /// The full text.bmp sheet, for TextSpriteRenderer to slice glyphs from.
    var textSheet: NSImage? { get }

    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var eqGraphLineColors: [NSColor] { get }
    var eqPreampLineColor: NSColor { get }
    var mainWindowRegion: NSBezierPath? { get }
}

/// The "no skin loaded" provider. All sprite() calls return nil and views fall through
/// to their built-in (programmatic) rendering paths. This is the default state.
final class BuiltInSkin: SkinProvider {
    func sprite(_ key: SpriteKey) -> NSImage? { nil }
    var textSheet: NSImage? { nil }
    var viscolors: [NSColor] { BuiltInSkin.builtInViscolors }
    var playlistStyle: PlaylistStyle { .default }
    var eqGraphLineColors: [NSColor] { [] }
    var eqPreampLineColor: NSColor { .green }
    var mainWindowRegion: NSBezierPath? { nil }

    /// 24-entry visualization palette for the built-in (no-skin) look.
    /// Indices 2..17 interpolate from spectrumBarBottom to spectrumBarTop in 16 steps,
    /// preserving the app's green→yellow identity. Index 0 is background, 1 is the
    /// scale-line tint, 18..23 are peak/oscilloscope highlights (white → gray).
    private static let builtInViscolors: [NSColor] = {
        let bottom = WinampTheme.spectrumBarBottom
        let top = WinampTheme.spectrumBarTop
        var colors: [NSColor] = []
        colors.append(.black)                                          // 0: bg
        colors.append(NSColor(srgbRed: 0.1, green: 0.13, blue: 0.16, alpha: 1)) // 1: scale line
        for i in 0..<16 {                                              // 2..17: bars
            let t = CGFloat(i) / 15.0
            colors.append(NSColor.interpolate(bottom, top, t: t))
        }
        // 18..23: peak/oscilloscope highlights, white → mid gray
        let highlights: [CGFloat] = [1.0, 0.85, 0.72, 0.62, 0.56, 0.50]
        for v in highlights {
            colors.append(NSColor(srgbRed: v, green: v, blue: v, alpha: 1))
        }
        return colors
    }()
}

private extension NSColor {
    /// Linear interpolation in sRGB between two colors at t ∈ [0,1].
    static func interpolate(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let aS = a.usingColorSpace(.sRGB) ?? a
        let bS = b.usingColorSpace(.sRGB) ?? b
        return NSColor(
            srgbRed: aS.redComponent   + (bS.redComponent   - aS.redComponent)   * t,
            green:   aS.greenComponent + (bS.greenComponent - aS.greenComponent) * t,
            blue:    aS.blueComponent  + (bS.blueComponent  - aS.blueComponent)  * t,
            alpha:   aS.alphaComponent + (bS.alphaComponent - aS.alphaComponent) * t
        )
    }
}
