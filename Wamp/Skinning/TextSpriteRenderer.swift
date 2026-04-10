// Wamp/Skinning/TextSpriteRenderer.swift
// Glyph map ported verbatim from FONT_LOOKUP in
// packages/webamp/js/skinSprites.ts @ webamp/master.
// See spec §4 (text rendering subsection).

import AppKit

enum TextSpriteRenderer {
    static let glyphWidth: CGFloat = 5
    static let glyphHeight: CGFloat = 6

    /// Maps each character to its (row, column) in text.bmp.
    /// Lowercase is canonical — uppercase input is lowercased before lookup.
    /// Layout: 3 rows of 31 columns each. Row 0 = a-z + " @  ", row 1 = digits + punctuation,
    /// row 2 = Å Ö Ä ? *. Ported verbatim from Webamp's FONT_LOOKUP.
    private static let lookup: [Character: (row: Int, col: Int)] = [
        "a": (0, 0),  "b": (0, 1),  "c": (0, 2),  "d": (0, 3),  "e": (0, 4),  "f": (0, 5),
        "g": (0, 6),  "h": (0, 7),  "i": (0, 8),  "j": (0, 9),  "k": (0, 10), "l": (0, 11),
        "m": (0, 12), "n": (0, 13), "o": (0, 14), "p": (0, 15), "q": (0, 16), "r": (0, 17),
        "s": (0, 18), "t": (0, 19), "u": (0, 20), "v": (0, 21), "w": (0, 22), "x": (0, 23),
        "y": (0, 24), "z": (0, 25),
        "\"": (0, 26), "@": (0, 27), " ": (0, 30),

        "0": (1, 0),  "1": (1, 1),  "2": (1, 2),  "3": (1, 3),  "4": (1, 4),
        "5": (1, 5),  "6": (1, 6),  "7": (1, 7),  "8": (1, 8),  "9": (1, 9),
        "\u{2026}": (1, 10),  // ellipsis
        ".": (1, 11), ":": (1, 12), "(": (1, 13), ")": (1, 14), "-": (1, 15),
        "'": (1, 16), "!": (1, 17), "_": (1, 18), "+": (1, 19), "\\": (1, 20),
        "/": (1, 21), "[": (1, 22), "]": (1, 23), "^": (1, 24), "&": (1, 25),
        "%": (1, 26), ",": (1, 27), "=": (1, 28), "$": (1, 29), "#": (1, 30),

        "Å": (2, 0), "Ö": (2, 1), "Ä": (2, 2), "?": (2, 3), "*": (2, 4),
    ]

    /// Returns the rect inside text.bmp for `char`, or nil if unsupported.
    /// (Coordinates are in Winamp Y-down — y measured from top of the sheet.)
    static func glyphRect(for char: Character) -> CGRect? {
        // Try as-is, then lowercased
        if let pos = lookup[char] {
            return rect(row: pos.row, col: pos.col)
        }
        if let lc = char.lowercased().first, let pos = lookup[lc] {
            return rect(row: pos.row, col: pos.col)
        }
        return nil
    }

    private static func rect(row: Int, col: Int) -> CGRect {
        CGRect(
            x: CGFloat(col) * glyphWidth,
            y: CGFloat(row) * glyphHeight,
            width: glyphWidth,
            height: glyphHeight
        )
    }

    /// Draws `text` at `origin` (lower-left of the first glyph in current view coords).
    /// Uses the full text.bmp sheet provided by the active SkinProvider.
    /// Disables image interpolation to keep 5×6 glyphs sharp at integer pixel positions.
    static func draw(_ text: String, at origin: NSPoint, sheet: NSImage) {
        guard let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let ctx = NSGraphicsContext.current
        let prevInterpolation = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prevInterpolation { ctx?.imageInterpolation = prev } }

        var x = origin.x
        for char in text {
            guard let rect = glyphRect(for: char) else {
                x += glyphWidth
                continue
            }
            // CGImage.cropping(to:) uses a top-left pixel origin (same as the
            // Winamp sheet coordinates), so pass the rect through unchanged.
            if let cropped = cg.cropping(to: rect) {
                let dest = NSRect(x: x, y: origin.y, width: glyphWidth, height: glyphHeight)
                NSImage(cgImage: cropped, size: dest.size).draw(in: dest)
            }
            x += glyphWidth
        }
    }

    /// Width in points needed to draw `text`.
    static func width(of text: String) -> CGFloat {
        CGFloat(text.count) * glyphWidth
    }
}
