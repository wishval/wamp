// Wamp/Skinning/ViscolorsParser.swift
// Parses viscolor.txt into 24 NSColors. See spec §3.

import AppKit

enum ViscolorsParser {
    private static let colorRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s*,?\s*(\d+)\s*,?\s*(\d+)"#
    )

    /// Parses viscolor.txt into 24 NSColors. Missing/invalid lines fall back to defaults.
    static func parse(_ text: String) -> [NSColor] {
        var colors = PlaylistStyle.defaultViscolors
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() where i < 24 {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = colorRegex.firstMatch(in: s, range: range),
                  let rR = Range(m.range(at: 1), in: s),
                  let gR = Range(m.range(at: 2), in: s),
                  let bR = Range(m.range(at: 3), in: s),
                  let r = Int(s[rR]),
                  let g = Int(s[gR]),
                  let b = Int(s[bR]) else { continue }
            colors[i] = NSColor(srgbRed: CGFloat(r) / 255.0,
                                green:   CGFloat(g) / 255.0,
                                blue:    CGFloat(b) / 255.0,
                                alpha: 1)
        }
        return colors
    }
}
