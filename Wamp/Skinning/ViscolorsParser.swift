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
        // Normalize line endings before splitting. Swift treats "\r\n" as a single
        // grapheme, so split(separator: "\n") silently returns one line on CRLF
        // files (produced by most Windows-era skin editors) and the entire palette
        // falls through to defaults. split(by: .newlines) would split on \r AND \n
        // independently, inserting empty lines that shift viscolor indices. We
        // collapse both CRLF and bare CR to \n first, then split normally.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
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
