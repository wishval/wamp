// Wamp/Skinning/RegionParser.swift
// Parses region.txt [Normal] section into a Y-flipped CGPoint polygon. See spec §3.

import CoreGraphics
import Foundation

enum RegionParser {
    /// Parses region.txt [Normal] into one or more Y-flipped polygons — the union of
    /// which forms the main window mask. `numpoints` is a comma-separated list of
    /// vertex counts, one per polygon, and `pointlist` concatenates the polygons'
    /// points in order. All other sections (WindowShade, Equalizer, etc.) are ignored.
    /// Returns nil when [Normal] is absent or contains no valid polygon.
    static func parseMainWindowRegion(_ text: String, windowHeight: CGFloat = 116) -> [[CGPoint]]? {
        let ini = IniParser.parse(text)
        guard let section = ini["normal"],
              let numpointsStr = section["numpoints"],
              let pointlistStr = section["pointlist"] else { return nil }

        let counts = numpointsStr
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !counts.isEmpty else { return nil }

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

        var polygons: [[CGPoint]] = []
        var cursor = 0
        for count in counts {
            guard count >= 3, cursor + count <= coords.count else { break }
            polygons.append(Array(coords[cursor..<(cursor + count)]))
            cursor += count
        }
        return polygons.isEmpty ? nil : polygons
    }
}
