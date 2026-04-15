// Wamp/Skinning/EqGraphColorsParser.swift
// Samples 19 line colors and 1 preamp color from eqmain.bmp. See spec §4.4.

import AppKit

enum EqGraphColorsParser {
    /// Samples 19 pixels at y=313 (graph line colors, top→bottom = +12dB→-12dB)
    /// and 1 pixel at y=314 (preamp line color) from eqmain.bmp.
    ///
    /// Returns `([], .green)` when the image is shorter than 314 pixels. The
    /// preamp row is optional: when the image is exactly 314 tall (no y=314),
    /// the line colors are still returned and preamp falls back to `.green`.
    ///
    /// If every sampled line pixel is Winamp's transparency key `#FF00FF`,
    /// the row was never populated by the skin author — returned as `[]` so
    /// the view falls back to its built-in hue gradient instead of rendering
    /// a bright-magenta curve.
    static func parse(from cg: CGImage) -> (lines: [NSColor], preamp: NSColor) {
        guard cg.height > 313 else { return ([], .green) }

        guard let context = CGContext(
            data: nil,
            width: cg.width,
            height: cg.height,
            bitsPerComponent: 8,
            bytesPerRow: cg.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return ([], .green) }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let data = context.data else { return ([], .green) }
        let buffer = data.bindMemory(to: UInt8.self, capacity: cg.width * cg.height * 4)

        // CGContext stores pixels bottom-up. y_top = (cg.height - 1 - y_winamp).
        func rgb(x: Int, y_winamp: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let y_ctx = cg.height - 1 - y_winamp
            let offset = (y_ctx * cg.width + x) * 4
            return (buffer[offset], buffer[offset + 1], buffer[offset + 2])
        }
        func toColor(_ px: (r: UInt8, g: UInt8, b: UInt8)) -> NSColor {
            NSColor(
                srgbRed: CGFloat(px.r) / 255,
                green:   CGFloat(px.g) / 255,
                blue:    CGFloat(px.b) / 255,
                alpha: 1
            )
        }
        func isTransparencyKey(_ px: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
            px.r == 255 && px.g == 0 && px.b == 255
        }

        let rawLines = (0..<19).map { rgb(x: $0, y_winamp: 313) }
        let lines: [NSColor] = rawLines.allSatisfy(isTransparencyKey)
            ? []
            : rawLines.map(toColor)

        let preamp: NSColor
        if cg.height > 314 {
            let raw = rgb(x: 0, y_winamp: 314)
            preamp = isTransparencyKey(raw) ? .green : toColor(raw)
        } else {
            preamp = .green
        }

        return (lines, preamp)
    }
}
