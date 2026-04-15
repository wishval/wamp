// Wamp/Skinning/EqGraphColorsParser.swift
// Samples 19 line colors and 1 preamp color from eqmain.bmp. See spec §4.4.

import AppKit

enum EqGraphColorsParser {
    /// Samples the EQ response-curve palette from eqmain.bmp, matching Webamp's
    /// sprite definitions:
    ///
    ///   EQ_GRAPH_LINE_COLORS — x=115, y=294, width=1, height=19 (vertical strip
    ///     to the right of the graph. Top row = +12 dB, bottom row = -12 dB.)
    ///   EQ_PREAMP_LINE       — x=0,   y=314, width=113, height=1
    ///
    /// An earlier revision sampled a horizontal strip at y=313, which matched
    /// neither the classic Winamp layout nor most real-world skins and produced
    /// near-uniform "curve disappears into the background" palettes.
    ///
    /// Returns `([], .green)` when the image is too short for y=312. Preamp
    /// falls back to `.green` when y=314 is not present (e.g. 314-tall sheets).
    /// If every sampled line pixel is Winamp's transparency key `#FF00FF`,
    /// `lines` is returned as `[]` so the view falls back to its built-in
    /// hue gradient instead of rendering a bright-magenta curve.
    static func parse(from cg: CGImage) -> (lines: [NSColor], preamp: NSColor) {
        guard cg.height > 312, cg.width > 115 else { return ([], .green) }

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

        // 19 line colors read top→bottom from the vertical strip at x=115.
        let rawLines = (0..<19).map { rgb(x: 115, y_winamp: 294 + $0) }
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
