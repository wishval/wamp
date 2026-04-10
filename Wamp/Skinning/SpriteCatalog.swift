// Wamp/Skinning/SpriteCatalog.swift
// Sprite coordinates ported from packages/webamp/js/skinSprites.ts @ webamp/master.
// Only the subset used by Wamp's UI. See spec §4.2 for the complete enum.

import CoreGraphics
import Foundation

enum SpriteKey: Hashable {
    // main
    case mainBackground

    // cbuttons
    case previous(pressed: Bool)
    case play(pressed: Bool)
    case pause(pressed: Bool)
    case stop(pressed: Bool)
    case next(pressed: Bool)
    case eject(pressed: Bool)

    // numbers
    case digit(Int)            // 0–9

    // monoster
    case mono(active: Bool)
    case stereo(active: Bool)

    // titlebar (used by EQ + Playlist windows)
    case titleBarActive
    case titleBarInactive
    case titleBarCloseButton(pressed: Bool)
    case titleBarShadeButton(pressed: Bool)

    // posbar
    case seekBackground
    case seekThumb(pressed: Bool)

    // volume
    case volumeBackground(position: Int)   // 0–27
    case volumeThumb(pressed: Bool)

    // balance
    case balanceBackground(position: Int)  // 0–27
    case balanceThumb(pressed: Bool)

    // shufrep
    case shuffleButton(active: Bool, pressed: Bool)
    case repeatButton(active: Bool, pressed: Bool)
    case eqToggleButton(active: Bool, pressed: Bool)
    case plToggleButton(active: Bool, pressed: Bool)

    // eqmain
    case eqBackground
    case eqSliderBackground
    case eqSliderThumb(position: Int, pressed: Bool)  // position 0–13
    case eqOnButton(active: Bool, pressed: Bool)
    case eqAutoButton(active: Bool, pressed: Bool)
    case eqPresetsButton(pressed: Bool)
    case eqGraphBackground

    // pledit
    case playlistTopLeftCorner(active: Bool)
    case playlistTopTitleBar(active: Bool)
    case playlistTopRightCorner(active: Bool)
    case playlistTopTile(active: Bool)
    case playlistLeftTile
    case playlistRightTile
    case playlistBottomLeftCorner
    case playlistBottomTile
    case playlistBottomRightCorner
    case playlistScrollHandle(pressed: Bool)
    case playlistAddFile(pressed: Bool)
    case playlistRemoveSelected(pressed: Bool)
    case playlistRemoveAll(pressed: Bool)
}

struct SpriteInfo {
    let sheet: String       // basename, e.g. "main", "cbuttons"
    let rect: CGRect        // position in sheet (Winamp Y-down — sliced as-is from CGImage)
}

enum SpriteCoordinates {
    static func resolve(_ key: SpriteKey) -> SpriteInfo {
        switch key {

        // MARK: main
        case .mainBackground:
            return SpriteInfo(sheet: "main", rect: CGRect(x: 0, y: 0, width: 275, height: 116))

        // MARK: cbuttons
        case .previous(let pressed):
            return SpriteInfo(sheet: "cbuttons", rect: CGRect(x:   0, y: pressed ? 18 : 0, width: 23, height: 18))
        case .play(let pressed):
            return SpriteInfo(sheet: "cbuttons", rect: CGRect(x:  23, y: pressed ? 18 : 0, width: 23, height: 18))
        case .pause(let pressed):
            return SpriteInfo(sheet: "cbuttons", rect: CGRect(x:  46, y: pressed ? 18 : 0, width: 23, height: 18))
        case .stop(let pressed):
            return SpriteInfo(sheet: "cbuttons", rect: CGRect(x:  69, y: pressed ? 18 : 0, width: 23, height: 18))
        case .next(let pressed):
            return SpriteInfo(sheet: "cbuttons", rect: CGRect(x:  92, y: pressed ? 18 : 0, width: pressed ? 22 : 23, height: 18))
        case .eject(let pressed):
            return SpriteInfo(sheet: "cbuttons", rect: CGRect(x: 114, y: pressed ? 16 : 0, width: 22, height: 16))

        // MARK: numbers — 9×13 each, 0–9 at x = n*9, y = 0
        case .digit(let n):
            let d = max(0, min(9, n))
            return SpriteInfo(sheet: "numbers", rect: CGRect(x: d * 9, y: 0, width: 9, height: 13))

        // MARK: monoster — stereo 29×12 at x=0, mono 27×12 at x=29; active row y=0, inactive y=12
        case .mono(let active):
            return SpriteInfo(sheet: "monoster", rect: CGRect(x: 29, y: active ? 0 : 12, width: 27, height: 12))
        case .stereo(let active):
            return SpriteInfo(sheet: "monoster", rect: CGRect(x:  0, y: active ? 0 : 12, width: 29, height: 12))

        // MARK: titlebar
        case .titleBarActive:
            return SpriteInfo(sheet: "titlebar", rect: CGRect(x: 27, y:  0, width: 275, height: 14))
        case .titleBarInactive:
            return SpriteInfo(sheet: "titlebar", rect: CGRect(x: 27, y: 15, width: 275, height: 14))
        case .titleBarCloseButton(let pressed):
            return SpriteInfo(sheet: "titlebar", rect: CGRect(x: 18, y: pressed ? 9 : 0, width: 9, height: 9))
        case .titleBarShadeButton(let pressed):
            return SpriteInfo(sheet: "titlebar", rect: CGRect(x:  0, y: pressed ? 27 : 18, width: 9, height: 9))

        // MARK: posbar
        case .seekBackground:
            return SpriteInfo(sheet: "posbar", rect: CGRect(x: 0, y: 0, width: 248, height: 10))
        case .seekThumb(let pressed):
            return SpriteInfo(sheet: "posbar", rect: CGRect(x: pressed ? 278 : 248, y: 0, width: 29, height: 10))

        // MARK: volume — 28 background variants stacked vertically (each 68×13 at y = p*15)
        case .volumeBackground(let p):
            let pos = max(0, min(27, p))
            return SpriteInfo(sheet: "volume", rect: CGRect(x: 0, y: pos * 15, width: 68, height: 13))
        case .volumeThumb(let pressed):
            return SpriteInfo(sheet: "volume", rect: CGRect(x: pressed ? 0 : 15, y: 422, width: 14, height: 11))

        // MARK: balance — 28 background variants (each 38×13 at y = p*15, x=9)
        case .balanceBackground(let p):
            let pos = max(0, min(27, p))
            return SpriteInfo(sheet: "balance", rect: CGRect(x: 9, y: pos * 15, width: 38, height: 13))
        case .balanceThumb(let pressed):
            return SpriteInfo(sheet: "balance", rect: CGRect(x: pressed ? 0 : 15, y: 422, width: 14, height: 11))

        // MARK: shufrep
        case .repeatButton(let active, let pressed):
            let y = (active ? 30 : 0) + (pressed ? 15 : 0)
            return SpriteInfo(sheet: "shufrep", rect: CGRect(x: 0, y: y, width: 28, height: 15))
        case .shuffleButton(let active, let pressed):
            let y = (active ? 30 : 0) + (pressed ? 15 : 0)
            return SpriteInfo(sheet: "shufrep", rect: CGRect(x: 28, y: y, width: 47, height: 15))
        case .eqToggleButton(let active, let pressed):
            let x = pressed ? 46 : 0
            let y = active ? 73 : 61
            return SpriteInfo(sheet: "shufrep", rect: CGRect(x: x, y: y, width: 23, height: 12))
        case .plToggleButton(let active, let pressed):
            let x = (pressed ? 46 : 0) + 23
            let y = active ? 73 : 61
            return SpriteInfo(sheet: "shufrep", rect: CGRect(x: x, y: y, width: 23, height: 12))

        // MARK: eqmain
        case .eqBackground:
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: 0, y: 0, width: 275, height: 116))
        case .eqSliderBackground:
            // The slider strip area used as background for individual band sliders.
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: 13, y: 164, width: 14, height: 63))
        case .eqSliderThumb(let position, let pressed):
            // 14 thumb variants stacked horizontally; each 11×11 at y = pressed ? 176 : 164.
            let p = max(0, min(13, position))
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: p * 15, y: pressed ? 176 : 164, width: 11, height: 11))
        case .eqOnButton(let active, let pressed):
            // Active+pressed=187, active+!pressed=69, !active+pressed=128, !active+!pressed=10. y=119, 26×12.
            let x: Int
            switch (active, pressed) {
            case (true, true):   x = 187
            case (true, false):  x = 69
            case (false, true):  x = 128
            case (false, false): x = 10
            }
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: x, y: 119, width: 26, height: 12))
        case .eqAutoButton(let active, let pressed):
            let x: Int
            switch (active, pressed) {
            case (true, true):   x = 213
            case (true, false):  x = 95
            case (false, true):  x = 154
            case (false, false): x = 36
            }
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: x, y: 119, width: 32, height: 12))
        case .eqPresetsButton(let pressed):
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: 224, y: pressed ? 176 : 164, width: 44, height: 12))
        case .eqGraphBackground:
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: 0, y: 294, width: 113, height: 19))

        // MARK: pledit
        case .playlistTopLeftCorner(let active):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x:   0, y: active ?  0 : 21, width:  25, height: 20))
        case .playlistTopTitleBar(let active):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x:  26, y: active ?  0 : 21, width: 100, height: 20))
        case .playlistTopRightCorner(let active):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: 153, y: active ?  0 : 21, width:  25, height: 20))
        case .playlistTopTile(let active):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: 127, y: active ?  0 : 21, width:  25, height: 20))
        case .playlistLeftTile:
            return SpriteInfo(sheet: "pledit", rect: CGRect(x:   0, y: 42, width: 12, height: 29))
        case .playlistRightTile:
            return SpriteInfo(sheet: "pledit", rect: CGRect(x:  31, y: 42, width: 20, height: 29))
        case .playlistBottomLeftCorner:
            return SpriteInfo(sheet: "pledit", rect: CGRect(x:   0, y: 72, width: 125, height: 38))
        case .playlistBottomTile:
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: 179, y:  0, width:  25, height: 38))
        case .playlistBottomRightCorner:
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: 126, y: 72, width: 150, height: 38))
        case .playlistScrollHandle(let pressed):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: pressed ? 61 : 52, y: 53, width: 8, height: 18))
        case .playlistAddFile(let p):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: p ? 23 : 0, y: 149, width: 22, height: 18))
        case .playlistRemoveSelected(let p):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: p ? 77 : 54, y: 149, width: 22, height: 18))
        case .playlistRemoveAll(let p):
            return SpriteInfo(sheet: "pledit", rect: CGRect(x: p ? 77 : 54, y: 111, width: 22, height: 18))
        }
    }
}
