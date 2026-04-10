// Wamp/Skinning/EqGraphColorsParser.swift
// Samples 19 line colors and 1 preamp color from eqmain.bmp. See spec §4.4.

import AppKit

enum EqGraphColorsParser {
    /// Samples 19 pixels at y=313 (graph line colors, top→bottom = +12dB→-12dB)
    /// and 1 pixel at y=314 (preamp line color) from eqmain.bmp.
    /// Returns ([], .green) if the image is too small.
    static func parse(from cg: CGImage) -> (lines: [NSColor], preamp: NSColor) {
        guard cg.height > 314 else { return ([], .green) }

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
        func color(x: Int, y_winamp: Int) -> NSColor {
            let y_ctx = cg.height - 1 - y_winamp
            let offset = (y_ctx * cg.width + x) * 4
            return NSColor(
                srgbRed: CGFloat(buffer[offset]) / 255.0,
                green:   CGFloat(buffer[offset + 1]) / 255.0,
                blue:    CGFloat(buffer[offset + 2]) / 255.0,
                alpha: 1
            )
        }

        // 19 line colors at y=313, x=0..18
        var lines: [NSColor] = []
        for x in 0..<19 {
            lines.append(color(x: x, y_winamp: 313))
        }
        let preamp = color(x: 0, y_winamp: 314)
        return (lines, preamp)
    }
}
