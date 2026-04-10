// Wamp/Skinning/RegionParser.swift
// Parses region.txt [Normal] section into a Y-flipped CGPoint polygon. See spec §3.

import CoreGraphics
import Foundation

enum RegionParser {
    /// Parses region.txt and returns the Y-flipped polygon for the [Normal] section
    /// (the main window region). All other sections (WindowShade, Equalizer, etc.) ignored.
    /// `windowHeight` is the height to flip Y around (Winamp main window = 116).
    static func parseMainWindowRegion(_ text: String, windowHeight: CGFloat = 116) -> [CGPoint]? {
        let ini = IniParser.parse(text)
        guard let section = ini["normal"],
              let numpointsStr = section["numpoints"],
              let pointlistStr = section["pointlist"] else { return nil }

        // First polygon's point count from numpoints (comma-separated). Take the first only.
        let firstCount = numpointsStr
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .first ?? 0
        guard firstCount >= 3 else { return nil }

        // Pointlist: "x1,y1 x2,y2 ..." — possibly newline or whitespace separated
        let coords = pointlistStr
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { (token: Substring) -> CGPoint? in
                let parts = token.split(separator: ",")
                guard parts.count == 2,
                      let x = Double(parts[0]),
                      let y = Double(parts[1]) else { return nil }
                // Y-flip: Winamp Y=0 is top, macOS Y=0 is bottom
                return CGPoint(x: x, y: windowHeight - y)
            }

        guard coords.count >= firstCount else { return nil }
        return Array(coords.prefix(firstCount))
    }
}
