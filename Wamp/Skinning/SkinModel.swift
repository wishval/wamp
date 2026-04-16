// Wamp/Skinning/SkinModel.swift
// Ported from packages/webamp/js/types.ts (subset).
// Spec: docs/superpowers/specs/2026-04-10-skin-support-design.md §3

import AppKit

struct SkinModel {
    /// Sprite sheets keyed by lowercase basename (e.g. "main", "cbuttons", "numbers").
    /// `numbers.bmp` and `nums_ex.bmp` both populate the "numbers" key (last write wins).
    let images: [String: CGImage]

    /// 24 visualization colors. Defaults if viscolor.txt absent.
    let viscolors: [NSColor]

    /// Playlist colors and font. Defaults if pledit.txt absent.
    let playlistStyle: PlaylistStyle

    /// Main window region — one or more Y-flipped polygons whose union forms the mask.
    /// nil if region.txt or its [Normal] section is absent.
    let mainWindowRegion: [[CGPoint]]?

    /// 19 colors sampled from eqmain.bmp vertical strip at x=115, y=294..312 —
    /// one per pixel row of the 19px-tall EQ response curve (top = +12 dB, bottom = −12 dB).
    /// Empty if eqmain.bmp absent. See EqGraphColorsParser.
    let eqGraphLineColors: [NSColor]

    /// 1 color sampled from eqmain.bmp at (x=0, y=314) — preamp line color.
    let eqPreampLineColor: NSColor
}

struct PlaylistStyle {
    let normal: NSColor
    let current: NSColor
    let normalBG: NSColor
    let selectedBG: NSColor
    let font: String

    static let `default` = PlaylistStyle(
        normal: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
        current: .white,
        normalBG: .black,
        selectedBG: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
        font: "Arial"
    )

    /// Default Winamp visualization colors (24 entries from Webamp baseSkin.json).
    static let defaultViscolors: [NSColor] = [
        NSColor(srgbRed:   0/255, green:   0/255, blue:   0/255, alpha: 1),
        NSColor(srgbRed:  24/255, green:  33/255, blue:  41/255, alpha: 1),
        NSColor(srgbRed: 239/255, green:  49/255, blue:  16/255, alpha: 1),
        NSColor(srgbRed: 206/255, green:  41/255, blue:  16/255, alpha: 1),
        NSColor(srgbRed: 214/255, green:  90/255, blue:   0/255, alpha: 1),
        NSColor(srgbRed: 214/255, green: 102/255, blue:   0/255, alpha: 1),
        NSColor(srgbRed: 214/255, green: 115/255, blue:   0/255, alpha: 1),
        NSColor(srgbRed: 198/255, green: 123/255, blue:   8/255, alpha: 1),
        NSColor(srgbRed: 222/255, green: 165/255, blue:  24/255, alpha: 1),
        NSColor(srgbRed: 214/255, green: 181/255, blue:  33/255, alpha: 1),
        NSColor(srgbRed: 189/255, green: 222/255, blue:  41/255, alpha: 1),
        NSColor(srgbRed: 148/255, green: 222/255, blue:  33/255, alpha: 1),
        NSColor(srgbRed:  41/255, green: 206/255, blue:  16/255, alpha: 1),
        NSColor(srgbRed:  50/255, green: 190/255, blue:  16/255, alpha: 1),
        NSColor(srgbRed:  57/255, green: 181/255, blue:  16/255, alpha: 1),
        NSColor(srgbRed:  49/255, green: 156/255, blue:   8/255, alpha: 1),
        NSColor(srgbRed:  41/255, green: 148/255, blue:   0/255, alpha: 1),
        NSColor(srgbRed:  24/255, green: 132/255, blue:   8/255, alpha: 1),
        NSColor(srgbRed: 255/255, green: 255/255, blue: 255/255, alpha: 1),
        NSColor(srgbRed: 214/255, green: 214/255, blue: 222/255, alpha: 1),
        NSColor(srgbRed: 181/255, green: 189/255, blue: 189/255, alpha: 1),
        NSColor(srgbRed: 160/255, green: 170/255, blue: 175/255, alpha: 1),
        NSColor(srgbRed: 148/255, green: 156/255, blue: 165/255, alpha: 1),
        NSColor(srgbRed: 150/255, green: 150/255, blue: 150/255, alpha: 1),
    ]
}

enum SkinParserError: LocalizedError {
    case invalidArchive
    case missingRequiredFile(String)
    case corruptedImage(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "Skin file is not a valid ZIP archive"
        case .missingRequiredFile(let name): return "Required skin file missing: \(name)"
        case .corruptedImage(let name): return "Could not decode image: \(name)"
        }
    }
}
