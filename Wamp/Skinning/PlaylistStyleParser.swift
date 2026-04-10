// Wamp/Skinning/PlaylistStyleParser.swift
// Parses pledit.txt [Text] section. See spec §3.

import AppKit

enum PlaylistStyleParser {
    static func parse(_ text: String) -> PlaylistStyle {
        let ini = IniParser.parse(text)
        guard let section = ini["text"] else { return .default }
        return PlaylistStyle(
            normal: parseColor(section["normal"]) ?? PlaylistStyle.default.normal,
            current: parseColor(section["current"]) ?? PlaylistStyle.default.current,
            normalBG: parseColor(section["normalbg"]) ?? PlaylistStyle.default.normalBG,
            selectedBG: parseColor(section["selectedbg"]) ?? PlaylistStyle.default.selectedBG,
            font: section["font"] ?? PlaylistStyle.default.font
        )
    }

    /// Normalizes "00FF00", "#00FF00", or "#00FF00FF" → NSColor.
    private static func parseColor(_ value: String?) -> NSColor? {
        guard var hex = value?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if !hex.hasPrefix("#") { hex = "#" + hex }
        if hex.count > 7 { hex = String(hex.prefix(7)) }
        guard hex.count == 7 else { return nil }
        var rgb: UInt64 = 0
        let scanner = Scanner(string: String(hex.dropFirst()))
        guard scanner.scanHexInt64(&rgb) else { return nil }
        return NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green:   CGFloat((rgb >>  8) & 0xFF) / 255.0,
            blue:    CGFloat( rgb        & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
