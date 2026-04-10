# Skin Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Apply Winamp 2.x classic skins (`.wsz`) to Wamp such that every visible UI element is either rendered from a skin sprite or hidden. Zero programmatic fallback when a skin is loaded.

**Spec:** `docs/superpowers/specs/2026-04-10-skin-support-design.md`

**Architecture (read this before any task):**
- **Drawing model.** Skinnable views override `draw(_:)` and branch on `WinampTheme.skinIsActive`. NEVER set `layer.contents` for skin backgrounds — that path was tried in `feature/skin-support` and caused unload races. All sprite blitting happens inside `draw(_:)`.
- **Atomic transitions.** `SkinManager.transition(to:)` updates `WinampTheme.provider` BEFORE firing `@Published currentSkin`. Observers always see consistent state.
- **No layout changes.** This work touches `draw()` methods and adds `applySkinVisibility()` toggles. It does NOT change view sizes, frames, layout math, or add new UI controls (except: pin button removed, CLR button renamed).
- **Hide-when-skinned.** All NSTextField labels listed in spec §8 are hidden via `applySkinVisibility()` when a skin loads, restored when it unloads.
- **Four acceptance skins.** `skins/base-2.91.wsz`, `skins/OS8 AMP - Aquamarine.wsz`, `skins/Blue Plasma.wsz`, `skins/Radar_Amp.wsz`. The whole MVP exists to make all four render correctly without fallback rendering or label bleed-through. Each skin tests a different parser corner case — see spec §1 for details.

**Tech stack:** Swift, AppKit, ZIPFoundation (SPM), Combine, AVFoundation.

---

## Task 1: Add ZIPFoundation SPM dependency

**Files:** `Wamp.xcodeproj/project.pbxproj`

ZIPFoundation is the only external dep. Add via Xcode GUI (the project is `.xcodeproj`, not Package.swift).

- [ ] **Step 1:** Open `Wamp.xcodeproj` in Xcode → File → Add Package Dependencies → URL: `https://github.com/weichsel/ZIPFoundation.git` → Up to Next Major Version from `0.9.0` → Add to target `Wamp`.

- [ ] **Step 2:** Verify resolution and build:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug -resolvePackageDependencies
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3:** Commit:

```bash
git add Wamp.xcodeproj/project.pbxproj
git commit -m "chore: add ZIPFoundation SPM dependency"
```

---

## Task 2: Create SkinModel and supporting types

**Files:** `Wamp/Skinning/SkinModel.swift` (new)

This file defines the data shape produced by the parser. **Keep it minimal** — no `genTextSprites`, no `genExColors`, no `cursors`. The first attempt accumulated dead fields; we don't.

- [ ] **Step 1:** Create the directory and file:

```bash
mkdir -p Wamp/Skinning
```

Write `Wamp/Skinning/SkinModel.swift`:

```swift
// Wamp/Skinning/SkinModel.swift
// Ported from packages/webamp/js/types.ts (subset)

import AppKit

struct SkinModel {
    /// Sprite sheets keyed by lowercase basename (e.g. "main", "cbuttons", "numbers").
    /// `numbers.bmp` and `nums_ex.bmp` both populate the "numbers" key (last write wins).
    let images: [String: CGImage]

    /// 24 visualization colors. Defaults if viscolor.txt absent.
    let viscolors: [NSColor]

    /// Playlist colors and font. Defaults if pledit.txt absent.
    let playlistStyle: PlaylistStyle

    /// Main window region polygon (Y-flipped to macOS coordinates). nil if region.txt absent.
    let mainWindowRegion: [CGPoint]?

    /// 19 colors sampled from eqmain.bmp at y=313 — one per pixel row of the EQ response curve.
    /// Empty if eqmain.bmp absent.
    let eqGraphLineColors: [NSColor]

    /// 1 color sampled from eqmain.bmp at y=314 — preamp line color.
    let eqPreampLineColor: NSColor
}

struct PlaylistStyle {
    let normal: NSColor
    let current: NSColor
    let normalBG: NSColor
    let selectedBG: NSColor
    let font: String

    static let `default` = PlaylistStyle(
        normal: NSColor(hex: 0x00FF00),
        current: .white,
        normalBG: .black,
        selectedBG: NSColor(hex: 0x0000FF),
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
```

- [ ] **Step 2:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/SkinModel.swift
git commit -m "feat: add SkinModel data types"
```

---

## Task 3: Create SpriteCatalog (SpriteKey enum + coordinates)

**Files:** `Wamp/Skinning/SpriteCatalog.swift` (new)

This is the largest file. It defines `SpriteKey` (the enum every view uses to ask for a sprite) and `SpriteCoordinates.resolve(_:)` which returns the sheet name and rectangle. Coordinates are ported 1:1 from `packages/webamp/js/skinSprites.ts`. **Only the cases listed in spec §4.2 are included** — anything else is dead weight.

Coordinates reference (use WebFetch to read the source if needed):
`https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts`

- [ ] **Step 1:** Write the file. The full contents:

```swift
// Wamp/Skinning/SpriteCatalog.swift
// Sprite coordinates ported from packages/webamp/js/skinSprites.ts @ webamp/master.
// Only the subset used by Wamp's UI. See spec §4.2 for the complete list.

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

        // MARK: cbuttons (each button 23×18 except next.pressed which is 22×18 and eject which is 22×16)
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

        // MARK: numbers (9×13 each, 0–9 at x=0,9,18,...,81)
        case .digit(let n):
            let d = max(0, min(9, n))
            return SpriteInfo(sheet: "numbers", rect: CGRect(x: d * 9, y: 0, width: 9, height: 13))

        // MARK: monoster (mono is 27×12 at x=29; stereo is 29×12 at x=0; active=row 0, inactive=row 12)
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
        // shuffle: 47×15 at x=28; repeat: 28×15 at x=0; y depends on active(30)+pressed(15)
        case .repeatButton(let active, let pressed):
            let y = (active ? 30 : 0) + (pressed ? 15 : 0)
            return SpriteInfo(sheet: "shufrep", rect: CGRect(x: 0, y: y, width: 28, height: 15))
        case .shuffleButton(let active, let pressed):
            let y = (active ? 30 : 0) + (pressed ? 15 : 0)
            return SpriteInfo(sheet: "shufrep", rect: CGRect(x: 28, y: y, width: 47, height: 15))
        // eq/pl toggle: 23×12 each at y=61(inactive)/73(active), x=pressed?46:0 (eq) or x=pressed?69:23 (pl)
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
            // 14 thumb variants stacked horizontally at y = pressed ? 176 : 164, each 11×11
            let p = max(0, min(13, position))
            return SpriteInfo(sheet: "eqmain", rect: CGRect(x: p * 15, y: pressed ? 176 : 164, width: 11, height: 11))
        case .eqOnButton(let active, let pressed):
            // active+pressed=187, active+!pressed=69, !active+pressed=128, !active+!pressed=10; all at y=119, 26×12
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
```

- [ ] **Step 2:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/SpriteCatalog.swift
git commit -m "feat: add SpriteCatalog with all sprite coordinates from Webamp"
```

**Verification reminder:** if any sprite looks misaligned during smoke test (Task 17), open `https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts` and compare the offending case 1:1.

---

## Task 4: Create IniParser, ViscolorsParser, PlaylistStyleParser, RegionParser, EqGraphColorsParser

**Files:** Five new files in `Wamp/Skinning/`.

These are small focused parsers. Group them in one task to reduce overhead.

- [ ] **Step 1: `IniParser.swift`** — generic INI parser used by playlist style and region:

```swift
// Wamp/Skinning/IniParser.swift
import Foundation

enum IniParser {
    /// Parses INI text into [section: [key: value]]. All keys lowercased.
    /// Handles BOM, CRLF, ; comments, and quoted values.
    static func parse(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var section: String?

        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let sectionRegex = try! NSRegularExpression(pattern: #"^\s*\[(.+?)\]\s*$"#)
        let propertyRegex = try! NSRegularExpression(pattern: #"^\s*([^;][^=]*?)\s*=\s*(.*?)\s*$"#)

        for line in cleaned.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let m = sectionRegex.firstMatch(in: trimmed, range: range),
               let r = Range(m.range(at: 1), in: trimmed) {
                section = String(trimmed[r]).lowercased()
                if result[section!] == nil { result[section!] = [:] }
            } else if let s = section,
                      let m = propertyRegex.firstMatch(in: trimmed, range: range),
                      let kr = Range(m.range(at: 1), in: trimmed),
                      let vr = Range(m.range(at: 2), in: trimmed) {
                let key = String(trimmed[kr]).lowercased()
                var value = String(trimmed[vr])
                if value.count >= 2,
                   (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
                result[s]?[key] = value
            }
        }
        return result
    }
}
```

- [ ] **Step 2: `ViscolorsParser.swift`** — viscolor.txt → 24 NSColors:

```swift
// Wamp/Skinning/ViscolorsParser.swift
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
```

- [ ] **Step 3: `PlaylistStyleParser.swift`** — pledit.txt `[Text]` section → PlaylistStyle:

```swift
// Wamp/Skinning/PlaylistStyleParser.swift
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
```

- [ ] **Step 4: `RegionParser.swift`** — region.txt `[Normal]` section only:

```swift
// Wamp/Skinning/RegionParser.swift
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

        guard coords.count >= firstCount, firstCount >= 3 else { return nil }
        return Array(coords.prefix(firstCount))
    }
}
```

- [ ] **Step 5: `EqGraphColorsParser.swift`** — sample 19 + 1 pixels from eqmain.bmp:

```swift
// Wamp/Skinning/EqGraphColorsParser.swift
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

        func color(x: Int, y: Int) -> NSColor {
            // CGContext is bottom-left origin, but we drew the CGImage as-is.
            // The CGImage from NSImage(data:) is also bottom-left, so direct y indexing works.
            let row = (cg.height - 1 - y) * cg.width * 4
            let offset = row + x * 4
            return NSColor(
                srgbRed: CGFloat(buffer[offset]) / 255.0,
                green:   CGFloat(buffer[offset + 1]) / 255.0,
                blue:    CGFloat(buffer[offset + 2]) / 255.0,
                alpha: 1
            )
        }

        // 19 line colors at y=313, x=0..18 (one pixel per dB row)
        var lines: [NSColor] = []
        for x in 0..<19 {
            lines.append(color(x: x, y: 313))
        }
        let preamp = color(x: 0, y: 314)
        return (lines, preamp)
    }
}
```

- [ ] **Step 6:** Build and commit each file (or all at once):

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/IniParser.swift Wamp/Skinning/ViscolorsParser.swift Wamp/Skinning/PlaylistStyleParser.swift Wamp/Skinning/RegionParser.swift Wamp/Skinning/EqGraphColorsParser.swift
git commit -m "feat: add INI, viscolors, playlist style, region, and EQ graph color parsers"
```

---

## Task 5: Create SkinParserUtils (ZIP extraction + image loading + nums_ex unification)

**Files:** `Wamp/Skinning/SkinParserUtils.swift` (new)

- [ ] **Step 1:** Write the file:

```swift
// Wamp/Skinning/SkinParserUtils.swift
import AppKit
import ZIPFoundation

enum SkinParserUtils {

    // MARK: ZIP

    /// Extracts all entries from a ZIP into [lowercased basename: data]. Last write wins.
    static func extractZip(_ data: Data) throws -> [String: Data] {
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw SkinParserError.invalidArchive
        }
        var entries: [String: Data] = [:]
        for entry in archive where entry.type == .file {
            var bytes = Data()
            _ = try archive.extract(entry) { chunk in bytes.append(chunk) }
            let basename = entry.path
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .last
                .map { $0.lowercased() } ?? ""
            if !basename.isEmpty {
                entries[basename] = bytes
            }
        }
        return entries
    }

    // MARK: Image loading

    /// Decodes BMP/PNG data via NSImage and returns the underlying CGImage.
    static func decodeImage(_ data: Data) -> CGImage? {
        guard let nsImage = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Loads a named image (tries .bmp then .png) from extracted entries.
    static func loadImage(named name: String, from entries: [String: Data]) -> CGImage? {
        let base = (name as NSString).deletingPathExtension.lowercased()
        for ext in ["bmp", "png"] {
            if let data = entries["\(base).\(ext)"], let img = decodeImage(data) {
                return img
            }
        }
        return nil
    }

    /// Loads all sprite sheets from spec §4.1 into [basename: CGImage].
    /// Special case: numbers.bmp and nums_ex.bmp both populate "numbers" (last write wins).
    /// Mirrors Webamp's CSS-cascade behavior where DIGIT_N and DIGIT_N_EX both target .digit-N.
    static func loadAllSheets(from entries: [String: Data]) -> [String: CGImage] {
        let sheetBaseNames = [
            "main", "titlebar", "cbuttons", "numbers",
            "playpaus", "monoster", "posbar", "volume", "balance",
            "shufrep", "eqmain", "pledit", "text",
        ]
        var images: [String: CGImage] = [:]
        for name in sheetBaseNames {
            if let img = loadImage(named: name, from: entries) {
                images[name] = img
            }
        }
        // nums_ex.bmp overwrites "numbers" if present
        if let nums_ex = loadImage(named: "nums_ex", from: entries) {
            images["numbers"] = nums_ex
        }
        return images
    }
}
```

- [ ] **Step 2:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/SkinParserUtils.swift
git commit -m "feat: add SkinParserUtils with ZIP extraction and nums_ex unification"
```

---

## Task 6: Create SkinParser orchestrator

**Files:** `Wamp/Skinning/SkinParser.swift` (new)

- [ ] **Step 1:** Write the orchestrator:

```swift
// Wamp/Skinning/SkinParser.swift
import AppKit

final class SkinParser {

    /// Synchronous parse for app startup (avoids window flicker).
    func parseSync(contentsOf url: URL) throws -> SkinModel {
        let data = try Data(contentsOf: url)
        return try buildModel(from: data)
    }

    /// Async wrapper for runtime loads (keeps the call off the main thread).
    func parse(contentsOf url: URL) async throws -> SkinModel {
        try await Task.detached(priority: .userInitiated) { [self] in
            let data = try Data(contentsOf: url)
            return try buildModel(from: data)
        }.value
    }

    private func buildModel(from data: Data) throws -> SkinModel {
        let entries = try SkinParserUtils.extractZip(data)

        // main.bmp is the only required file
        guard SkinParserUtils.loadImage(named: "main", from: entries) != nil else {
            throw SkinParserError.missingRequiredFile("main.bmp")
        }

        // All sprite sheets (with nums_ex unification)
        let images = SkinParserUtils.loadAllSheets(from: entries)

        // viscolor.txt
        let viscolors: [NSColor]
        if let data = entries["viscolor.txt"],
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            viscolors = ViscolorsParser.parse(text)
        } else {
            viscolors = PlaylistStyle.defaultViscolors
        }

        // pledit.txt
        let playlistStyle: PlaylistStyle
        if let data = entries["pledit.txt"],
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            playlistStyle = PlaylistStyleParser.parse(text)
        } else {
            playlistStyle = .default
        }

        // region.txt — main window only
        let region: [CGPoint]?
        if let data = entries["region.txt"],
           let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            region = RegionParser.parseMainWindowRegion(text, windowHeight: 116)
        } else {
            region = nil
        }

        // eqmain.bmp graph line colors
        let eqGraphLines: [NSColor]
        let eqPreampLine: NSColor
        if let eqmain = images["eqmain"] {
            let parsed = EqGraphColorsParser.parse(from: eqmain)
            eqGraphLines = parsed.lines
            eqPreampLine = parsed.preamp
        } else {
            eqGraphLines = []
            eqPreampLine = .green
        }

        return SkinModel(
            images: images,
            viscolors: viscolors,
            playlistStyle: playlistStyle,
            mainWindowRegion: region,
            eqGraphLineColors: eqGraphLines,
            eqPreampLineColor: eqPreampLine
        )
    }
}
```

- [ ] **Step 2:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/SkinParser.swift
git commit -m "feat: add SkinParser orchestrator (sync + async)"
```

---

## Task 7: Create SkinProvider, BuiltInSkin, WinampClassicSkin

**Files:** `Wamp/Skinning/SkinProvider.swift` (new), `Wamp/Skinning/WinampClassicSkin.swift` (new)

- [ ] **Step 1:** Write `SkinProvider.swift`:

```swift
// Wamp/Skinning/SkinProvider.swift
import AppKit

protocol SkinProvider: AnyObject {
    /// Returns the requested sprite as an NSImage, or nil if the underlying sheet is missing.
    func sprite(_ key: SpriteKey) -> NSImage?

    /// The full text.bmp sheet, for TextSpriteRenderer to slice glyphs from.
    var textSheet: NSImage? { get }

    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var eqGraphLineColors: [NSColor] { get }
    var eqPreampLineColor: NSColor { get }
    var mainWindowRegion: NSBezierPath? { get }
}

/// The "no skin loaded" provider. All sprite() calls return nil and views fall through
/// to their built-in (programmatic) rendering paths. This is the default state.
final class BuiltInSkin: SkinProvider {
    func sprite(_ key: SpriteKey) -> NSImage? { nil }
    var textSheet: NSImage? { nil }
    var viscolors: [NSColor] { PlaylistStyle.defaultViscolors }
    var playlistStyle: PlaylistStyle { .default }
    var eqGraphLineColors: [NSColor] { [] }
    var eqPreampLineColor: NSColor { .green }
    var mainWindowRegion: NSBezierPath? { nil }
}
```

- [ ] **Step 2:** Write `WinampClassicSkin.swift`:

```swift
// Wamp/Skinning/WinampClassicSkin.swift
import AppKit

final class WinampClassicSkin: SkinProvider {
    private let model: SkinModel
    private let cache = NSCache<NSString, NSImage>()

    init(model: SkinModel) {
        self.model = model
    }

    func sprite(_ key: SpriteKey) -> NSImage? {
        let cacheKey = "\(key)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let info = SpriteCoordinates.resolve(key)
        guard let sheet = model.images[info.sheet] else { return nil }
        guard let cropped = sheet.cropping(to: info.rect) else { return nil }

        let image = NSImage(cgImage: cropped, size: info.rect.size)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    var textSheet: NSImage? {
        guard let cg = model.images["text"] else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    var viscolors: [NSColor] { model.viscolors }
    var playlistStyle: PlaylistStyle { model.playlistStyle }
    var eqGraphLineColors: [NSColor] { model.eqGraphLineColors }
    var eqPreampLineColor: NSColor { model.eqPreampLineColor }

    var mainWindowRegion: NSBezierPath? {
        guard let points = model.mainWindowRegion, points.count >= 3 else { return nil }
        let path = NSBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.close()
        return path
    }
}
```

- [ ] **Step 3:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/SkinProvider.swift Wamp/Skinning/WinampClassicSkin.swift
git commit -m "feat: add SkinProvider protocol, BuiltInSkin, and WinampClassicSkin"
```

---

## Task 8: Create SkinManager with atomic transitions

**Files:** `Wamp/Skinning/SkinManager.swift` (new)

This is where the prior attempt broke. Read spec §2.3 and §12 before writing — the order of `provider` vs `currentSkin` updates matters.

- [ ] **Step 1:** Write the file:

```swift
// Wamp/Skinning/SkinManager.swift
import AppKit
import Combine

final class SkinManager: ObservableObject {
    static let shared = SkinManager()

    /// Observers should subscribe to this. After the publisher fires, both
    /// `WinampTheme.provider` and `currentSkin` are guaranteed to be the new value.
    @Published private(set) var currentSkin: SkinProvider = BuiltInSkin()

    private init() {}

    /// Loads a skin off the main thread, then transitions on main.
    func loadSkin(from url: URL) async throws {
        let model = try await SkinParser().parse(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        await MainActor.run {
            self.transition(to: skin)
        }
    }

    /// Synchronous load for app startup. Run before window creation to avoid flicker.
    func loadSkinSync(from url: URL) throws {
        let model = try SkinParser().parseSync(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        transition(to: skin)
    }

    /// Restores BuiltInSkin.
    func unloadSkin() {
        transition(to: BuiltInSkin())
    }

    /// Atomic transition: WinampTheme.provider is updated FIRST so that any code path
    /// that checks `WinampTheme.skinIsActive` or calls `WinampTheme.sprite(...)` from
    /// inside an observer sink sees consistent state. The first attempt
    /// (feature/skin-support) had this in the wrong order and caused render races.
    private func transition(to newSkin: SkinProvider) {
        WinampTheme.provider = newSkin
        self.currentSkin = newSkin   // fires @Published — observers run AFTER provider is set
    }
}
```

- [ ] **Step 2:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/SkinManager.swift
git commit -m "feat: add SkinManager with atomic transition (provider before currentSkin)"
```

---

## Task 9: Create TextSpriteRenderer (text.bmp glyph rendering)

**Files:** `Wamp/Skinning/TextSpriteRenderer.swift` (new)

`text.bmp` is the small bitmap font Winamp uses for: LCD scrolling track text, bitrate digits, "kbps"/"khz" labels, playlist info label. Glyphs are **5×6 px**, organized in **3 rows**. The character map below is ported verbatim from Webamp's `FONT_LOOKUP` in `packages/webamp/js/skinSprites.ts`. **Do not edit** the lookup table without consulting the Webamp source.

- [ ] **Step 1:** Write the file:

```swift
// Wamp/Skinning/TextSpriteRenderer.swift
// Glyph map ported verbatim from FONT_LOOKUP in packages/webamp/js/skinSprites.ts.

import AppKit

enum TextSpriteRenderer {
    static let glyphWidth: CGFloat = 5
    static let glyphHeight: CGFloat = 6

    /// Maps each character to its (row, column) in text.bmp.
    /// Lowercase is canonical — uppercase input is lowercased before lookup.
    /// Webamp's deburring (Å → A etc.) is approximated by lowercased() + the row-2 fallbacks.
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
    static func glyphRect(for char: Character) -> CGRect? {
        // Try as-is, then lowercased
        let lookupKey: Character = lookup[char] != nil ? char : Character(char.lowercased())
        guard let pos = lookup[lookupKey] else { return nil }
        return CGRect(
            x: CGFloat(pos.col) * glyphWidth,
            y: CGFloat(pos.row) * glyphHeight,
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
            // text.bmp is bottom-up in CGImage coords; rect uses top-left origin so we need to flip
            let cgY = CGFloat(cg.height) - rect.origin.y - rect.height
            let sourceRect = CGRect(x: rect.origin.x, y: cgY, width: rect.width, height: rect.height)
            if let cropped = cg.cropping(to: sourceRect) {
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
```

- [ ] **Step 2:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Skinning/TextSpriteRenderer.swift
git commit -m "feat: add TextSpriteRenderer with Webamp FONT_LOOKUP"
```

---

## Task 10: Refactor WinampTheme into a class facade

**Files:** `Wamp/UI/WinampTheme.swift` (modify)

Currently `WinampTheme` is an `enum` with all-static members. We convert it to `final class` and add `provider` + `sprite()` + `skinIsActive`. **All existing static colors/fonts/dimensions stay unchanged** — they are used only by the `drawBuiltIn` paths in views (no skin loaded). No view file changes in this task.

- [ ] **Step 1:** Read the current file to confirm structure:

```bash
head -20 Wamp/UI/WinampTheme.swift
```

- [ ] **Step 2:** Change line 14 from `enum WinampTheme {` to `final class WinampTheme {` and add the new members at the top of the body:

```swift
final class WinampTheme {
    // MARK: - Skin facade
    static var provider: SkinProvider = BuiltInSkin()

    static func sprite(_ key: SpriteKey) -> NSImage? {
        provider.sprite(key)
    }

    /// True when a real skin is loaded. Views check this in `draw()` to branch
    /// between `drawSkinned` and `drawBuiltIn`. See spec §7.1.
    static var skinIsActive: Bool {
        !(provider is BuiltInSkin)
    }

    // ... existing static let frameBackground, titleBarTop, etc., unchanged below ...
```

**Do not** convert `frameBackground` or any other property to a computed property delegating to `provider`. They stay as static lets — they're consumed only by `drawBuiltIn` paths.

- [ ] **Step 3:** Build (must succeed without touching any view file):

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If anything else broke, that's a bug — only the type declaration changed.

- [ ] **Step 4:** Commit:

```bash
git add Wamp/UI/WinampTheme.swift
git commit -m "refactor: convert WinampTheme to class facade with SkinProvider"
```

---

## Task 11: Add skinPath to AppState and Load/Unload menu items

**Files:** `Wamp/Models/StateManager.swift`, `Wamp/AppDelegate.swift`

This task wires the menu and persistence so we can load skins manually before any view rendering changes are in place. With Tasks 1–10 complete, loading a skin via the menu should NOT crash — it just won't visually change anything yet.

- [ ] **Step 1:** Add `skinPath` to `AppState` in `StateManager.swift`. Find the `AppState` struct (currently lines 4–16) and add at the bottom of the property list:

```swift
    var skinPath: String?
```

Also add a generic save method (used by menu actions to persist `skinPath` directly):

```swift
// In StateManager class body
func saveAppState(_ state: AppState) {
    write(state, to: "state.json")
}
```

(The existing `saveWindowState` already writes the full state — `saveAppState` is a thin convenience that takes a pre-built state.)

- [ ] **Step 2:** In `AppDelegate.swift`, add startup skin restore. After `let appState = stateManager.loadAppState()` (~line 29) and BEFORE `mainWindow = MainWindow()` (~line 49), add:

```swift
// Restore saved skin (synchronous to avoid window flicker)
if let path = appState.skinPath, FileManager.default.fileExists(atPath: path) {
    try? SkinManager.shared.loadSkinSync(from: URL(fileURLWithPath: path))
}
```

- [ ] **Step 3:** Add menu items. In `setupMainMenu()` after the existing View menu items (after line 170, after `viewMenu.addItem(showPL)`), add:

```swift
viewMenu.addItem(.separator())

// Always-on-top moves here from the (deleted in Task 13) pin button.
let alwaysOnTop = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "t")
alwaysOnTop.keyEquivalentModifierMask = [.command, .shift]
alwaysOnTop.target = self
alwaysOnTop.state = mainWindow.alwaysOnTop ? .on : .off
self.alwaysOnTopMenuItem = alwaysOnTop
viewMenu.addItem(alwaysOnTop)

viewMenu.addItem(.separator())

let loadSkin = NSMenuItem(title: "Load Skin...", action: #selector(loadSkinAction), keyEquivalent: "S")
loadSkin.keyEquivalentModifierMask = [.command, .shift]
loadSkin.target = self
viewMenu.addItem(loadSkin)

let unloadSkin = NSMenuItem(title: "Unload Skin", action: #selector(unloadSkinAction), keyEquivalent: "")
unloadSkin.target = self
viewMenu.addItem(unloadSkin)
```

Add a stored property near `var mainWindow: MainWindow!`:

```swift
private weak var alwaysOnTopMenuItem: NSMenuItem?
```

- [ ] **Step 4:** Add the action methods. Add at the end of `AppDelegate` (after `togglePL`):

```swift
@objc private func toggleAlwaysOnTop() {
    mainWindow.alwaysOnTop.toggle()
    alwaysOnTopMenuItem?.state = mainWindow.alwaysOnTop ? .on : .off

    var state = stateManager.loadAppState()
    state.alwaysOnTop = mainWindow.alwaysOnTop
    stateManager.saveAppState(state)
}

@objc private func loadSkinAction() {
    let panel = NSOpenPanel()
    if let wsz = UTType(filenameExtension: "wsz") {
        panel.allowedContentTypes = [wsz, .zip]
    } else {
        panel.allowedContentTypes = [.zip]
    }
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else { return }

    Task {
        do {
            try await SkinManager.shared.loadSkin(from: url)
            var state = stateManager.loadAppState()
            state.skinPath = url.path
            stateManager.saveAppState(state)
            mainWindow.applyRegionMaskFromCurrentSkin()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to load skin"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

@objc private func unloadSkinAction() {
    SkinManager.shared.unloadSkin()
    var state = stateManager.loadAppState()
    state.skinPath = nil
    stateManager.saveAppState(state)
    mainWindow.applyRegionMaskFromCurrentSkin()
}
```

Add at the top of the file:

```swift
import UniformTypeIdentifiers
```

Note: `mainWindow.applyRegionMaskFromCurrentSkin()` will be defined in Task 14. For now this line will produce a build error — that's expected, we'll fix it in Task 14.

**Workaround for this task:** comment out the two `applyRegionMaskFromCurrentSkin()` lines so the build passes. Uncomment them in Task 14.

- [ ] **Step 5:** Build (with the region mask lines commented out) and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/Models/StateManager.swift Wamp/AppDelegate.swift
git commit -m "feat: add skinPath persistence and Load/Unload Skin menu"
```

---

## Task 12: Update WinampButton to support sprite rendering

**Files:** `Wamp/UI/Components/WinampButton.swift`

Add a `spriteKeyProvider` closure that maps `(active, pressed) → SpriteKey`. When set and the sprite exists, blit it instead of the programmatic path. Add a skin observer.

- [ ] **Step 1:** Read the current file to understand its draw method and `isActive`/`isPressed` properties.

- [ ] **Step 2:** Add at the top of the file:

```swift
import Combine
```

Add as new properties:

```swift
/// Closure that maps (active, pressed) → SpriteKey. Set by parent views.
/// When non-nil and the sprite resolves, the button renders the sprite instead of the programmatic path.
var spriteKeyProvider: ((Bool, Bool) -> SpriteKey)?

private var skinObserver: AnyCancellable?
```

In `init`:

```swift
skinObserver = SkinManager.shared.$currentSkin
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.needsDisplay = true }
```

- [ ] **Step 3:** At the very top of `draw(_:)`, before the existing programmatic rendering:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive,
       let provide = spriteKeyProvider,
       let sprite = WinampTheme.sprite(provide(isActive, isPressed)) {
        sprite.draw(in: bounds)
        return
    }
    // ... existing programmatic draw code unchanged ...
}
```

- [ ] **Step 4:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/UI/Components/WinampButton.swift
git commit -m "feat: add spriteKeyProvider to WinampButton"
```

---

## Task 13: Wire transport buttons + shuffle/repeat/EQ/PL toggles to sprite keys; remove pin button

**Files:** `Wamp/UI/Components/TransportBar.swift`, `Wamp/UI/MainPlayerView.swift`, `Wamp/UI/Components/TitleBarView.swift`

This task makes three permanent changes:
1. Wire transport buttons (`TransportBar`) to `cbuttons.bmp` sprite keys.
2. Wire `shuffleButton`/`repeatButton`/`eqButton`/`plButton` (in `MainPlayerView`) to `shufrep.bmp` sprite keys.
3. **Permanently delete** the pin button from `TitleBarView`. Always-on-top is now in the View menu (Task 11).

- [ ] **Step 1:** In `TransportBar.swift`, after the buttons are created in `setupButtons()`, add:

```swift
prevButton.spriteKeyProvider   = { _, pressed in .previous(pressed: pressed) }
playButton.spriteKeyProvider   = { _, pressed in .play(pressed: pressed) }
pauseButton.spriteKeyProvider  = { _, pressed in .pause(pressed: pressed) }
stopButton.spriteKeyProvider   = { _, pressed in .stop(pressed: pressed) }
nextButton.spriteKeyProvider   = { _, pressed in .next(pressed: pressed) }
ejectButton.spriteKeyProvider  = { _, pressed in .eject(pressed: pressed) }
```

- [ ] **Step 2:** In `MainPlayerView.swift`, in `setupSubviews()` after the toggle buttons are created (after line 38ish), add:

```swift
shuffleButton.spriteKeyProvider = { active, pressed in .shuffleButton(active: active, pressed: pressed) }
repeatButton.spriteKeyProvider  = { active, pressed in .repeatButton(active: active, pressed: pressed) }
eqButton.spriteKeyProvider      = { active, pressed in .eqToggleButton(active: active, pressed: pressed) }
plButton.spriteKeyProvider      = { active, pressed in .plToggleButton(active: active, pressed: pressed) }
```

- [ ] **Step 3:** Delete the pin button from `TitleBarView.swift`. Find and remove:
- Property `var onTogglePin: (() -> Void)?`
- Property `var isPinned: Bool = true { didSet { needsDisplay = true } }`
- Method `drawPinButton(_:pinned:)` (entire body)
- Any pinRect calculations and pin hit-testing branches in `mouseDown`/`mouseUp`
- Any call to `drawPinButton` inside `draw(_:)`

After this step, `grep "pin\|Pin\|pushpin" Wamp/UI/Components/TitleBarView.swift` should return nothing.

- [ ] **Step 4:** In `MainPlayerView.swift`, find the line that sets `titleBar.onTogglePin = { ... }` (currently line 74) and DELETE it. Also delete the property:

```swift
var isPinned: Bool { get/set ... }
```

(currently lines 19-22) and the `var onTogglePin: (() -> Void)?` callback (line 9).

`grep "isPinned\|onTogglePin" Wamp/UI/MainPlayerView.swift` should return nothing after this step.

- [ ] **Step 5:** Search the rest of the codebase for any remaining references and delete them:

```bash
grep -rn "onTogglePin\|isPinned\|togglePin\|pinButton" Wamp/
```

Each match must be deleted. Always-on-top is now toggled exclusively via the View menu (Task 11).

- [ ] **Step 6:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/UI/Components/TransportBar.swift Wamp/UI/MainPlayerView.swift Wamp/UI/Components/TitleBarView.swift
git commit -m "feat: wire transport+toggle buttons to sprites, remove pin button"
```

---

## Task 14: Add region mask to MainWindow

**Files:** `Wamp/UI/MainWindow.swift`, `Wamp/AppDelegate.swift`

The non-rectangular window shape from `region.txt`. Apply on skin load and unload.

- [ ] **Step 1:** Add to `MainWindow.swift`:

```swift
import QuartzCore

// In the MainWindow class body:
func applyRegionMaskFromCurrentSkin() {
    guard let contentView = self.contentView else { return }
    contentView.wantsLayer = true

    if let region = SkinManager.shared.currentSkin.mainWindowRegion {
        let mask = CAShapeLayer()
        mask.path = region.cgPath
        mask.fillColor = NSColor.black.cgColor
        contentView.layer?.mask = mask
    } else {
        contentView.layer?.mask = nil
    }
}
```

Add the `cgPath` extension at the bottom of the file (or in a shared location). Note: macOS 14+ has `NSBezierPath.cgPath` built in; this extension is for backwards compatibility. Wrap in availability check if Wamp's deployment target is 14+:

```swift
#if !(swift(>=5.9) && os(macOS) && false)  // always include for now
private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:    path.move(to: points[0])
            case .lineTo:    path.addLine(to: points[0])
            case .curveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
#endif
```

If `NSBezierPath.cgPath` already exists (macOS 14+), comment out the extension to avoid duplicate symbol errors. Try the build first; if it fails with redefinition, comment it out.

- [ ] **Step 2:** Uncomment the `mainWindow.applyRegionMaskFromCurrentSkin()` calls in `AppDelegate.swift` (the two lines commented out in Task 11).

- [ ] **Step 3:** Add startup region mask application in `AppDelegate.applicationDidFinishLaunching`. After `mainWindow.makeKeyAndOrderFront(nil)` (~line 64):

```swift
mainWindow.applyRegionMaskFromCurrentSkin()
```

- [ ] **Step 4:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/UI/MainWindow.swift Wamp/AppDelegate.swift
git commit -m "feat: add region mask support to MainWindow"
```

---

## Task 15: Add sprite rendering to WinampSlider, SevenSegmentView, TitleBarView, EQResponseView, SpectrumView

**Files:** `Wamp/UI/Components/WinampSlider.swift`, `Wamp/UI/Components/SevenSegmentView.swift`, `Wamp/UI/Components/TitleBarView.swift`, `Wamp/UI/Components/EQResponseView.swift`, `Wamp/UI/Components/SpectrumView.swift`

These are the leaf views that draw their own sprites without hide-when-skinned logic (no NSTextField children to toggle). Same pattern: extract existing code into `drawBuiltIn`, add `drawSkinned`, branch in `draw()`.

- [ ] **Step 1: WinampSlider** — sprite rendering for all 4 styles (seek/volume/balance/eqBand).

Add at top:

```swift
import Combine
private var skinObserver: AnyCancellable?
```

In `init`, set up the observer:

```swift
skinObserver = SkinManager.shared.$currentSkin
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.needsDisplay = true }
```

Refactor `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned()
        return
    }
    // existing built-in drawing
    if isVertical {
        drawVerticalSlider(in: bounds)
    } else {
        drawHorizontalSlider(in: bounds)
    }
}

private func drawSkinned() {
    let n = normalizedValue
    switch style {
    case .seek:
        if let bg = WinampTheme.sprite(.seekBackground) {
            bg.draw(in: bounds)
        }
        let thumbW: CGFloat = 29
        let thumbX = n * (bounds.width - thumbW)
        if let thumb = WinampTheme.sprite(.seekThumb(pressed: isUserInteracting)) {
            thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 10) / 2, width: thumbW, height: 10))
        }

    case .volume:
        let position = Int((n * 27).rounded())
        if let bg = WinampTheme.sprite(.volumeBackground(position: position)) {
            bg.draw(in: bounds)
        }
        let thumbW: CGFloat = 14
        let thumbX = n * (bounds.width - thumbW)
        if let thumb = WinampTheme.sprite(.volumeThumb(pressed: isUserInteracting)) {
            thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: thumbW, height: 11))
        }

    case .balance:
        let position = Int((n * 27).rounded())
        if let bg = WinampTheme.sprite(.balanceBackground(position: position)) {
            bg.draw(in: bounds)
        }
        let thumbW: CGFloat = 14
        let thumbX = n * (bounds.width - thumbW)
        if let thumb = WinampTheme.sprite(.balanceThumb(pressed: isUserInteracting)) {
            thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: thumbW, height: 11))
        }

    case .eqBand:
        if let bg = WinampTheme.sprite(.eqSliderBackground) {
            bg.draw(in: bounds)
        }
        // 14 thumb positions: 0 = bottom (-12 dB), 13 = top (+12 dB)
        let thumbPos = Int((n * 13).rounded())
        let thumbY = n * (bounds.height - 11)
        if let thumb = WinampTheme.sprite(.eqSliderThumb(position: thumbPos, pressed: isUserInteracting)) {
            thumb.draw(in: NSRect(x: (bounds.width - 11) / 2, y: thumbY, width: 11, height: 11))
        }
    }
}
```

- [ ] **Step 2: SevenSegmentView** — sprite digits.

Add observer (same pattern). In the digit-drawing path, before the existing seven-segment code, add:

```swift
if WinampTheme.skinIsActive,
   digit >= 0, digit <= 9,
   let sprite = WinampTheme.sprite(.digit(digit)) {
    sprite.draw(in: rect)
    return
}
// existing seven-segment fallback
```

Note: numbers.bmp digits are 9×13 in source. They will be scaled to whatever `rect` Wamp's `SevenSegmentView` provides — that's fine, NSImage scales linearly.

- [ ] **Step 3: TitleBarView** — sprite background and close button (used by EQ + Playlist windows; MainPlayerView's titleBar is hidden in Task 16, so this affects EqualizerView and PlaylistView only).

Add observer. In `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned()
        return
    }
    drawBuiltIn(dirtyRect)
}

private func drawSkinned() {
    let isActive = window?.isKeyWindow ?? true
    if let bg = WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive) {
        bg.draw(in: bounds)
    }
    // Title text is baked into the sprite — do not draw the titleText overlay.
    if showButtons {
        let btnSize: CGFloat = 9
        let btnY = (bounds.height - btnSize) / 2
        // close button at right edge
        if let close = WinampTheme.sprite(.titleBarCloseButton(pressed: false)) {
            close.draw(in: NSRect(x: bounds.width - 11, y: btnY, width: btnSize, height: btnSize))
        }
    }
}
```

Move the existing draw body into a `private func drawBuiltIn(_ dirtyRect: NSRect)` method.

- [ ] **Step 4: EQResponseView** — use the 19 graph line colors when skinned.

Add observer. In `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned()
        return
    }
    drawBuiltIn(dirtyRect)
}

private func drawSkinned() {
    // Background from eqmain.bmp at the graph rect
    if let bg = WinampTheme.sprite(.eqGraphBackground) {
        bg.draw(in: bounds)
    }
    // Draw response curve using the 19 line colors (top→bottom = +12dB→-12dB)
    let lines = WinampTheme.provider.eqGraphLineColors
    guard lines.count == 19, !bands.isEmpty else { return }

    // For each pixel column of the curve, look up which dB row this column lands on
    // and draw a 1-px tall rect of the corresponding line color.
    let cols = Int(bounds.width)
    for col in 0..<cols {
        let bandIndex = Int(Double(col) / Double(cols) * Double(bands.count))
        let band = bands[min(bandIndex, bands.count - 1)]
        // band is in -12...+12 dB; map to row 0..18
        let row = Int(round(Double(9 - Int(band))))
        let clampedRow = max(0, min(18, row))
        lines[clampedRow].setFill()
        NSRect(x: CGFloat(col), y: bounds.height - CGFloat(clampedRow + 1) * (bounds.height / 19),
               width: 1, height: max(1, bounds.height / 19)).fill()
    }
}
```

(Move existing draw body into `drawBuiltIn`.)

- [ ] **Step 5: SpectrumView** — read viscolors from provider.

Add observer. In `draw(_:)`, replace the hardcoded gradient construction with:

```swift
let viscolors = WinampTheme.provider.viscolors
let bottom = viscolors.count > 2 ? viscolors[2] : WinampTheme.spectrumBarBottom
let top = viscolors.count > 17 ? viscolors[17] : WinampTheme.spectrumBarTop
let gradient = NSGradient(starting: bottom, ending: top)
```

This works in both skinned and built-in modes (BuiltInSkin returns the default 24 viscolors which differ from `WinampTheme.spectrum*` constants; if you want the existing built-in look unchanged, branch on `skinIsActive`).

- [ ] **Step 6:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/UI/Components/
git commit -m "feat: add sprite rendering to slider, digits, title bar, EQ curve, spectrum"
```

---

## Task 16: Skin MainPlayerView (background, hide-when-skinned, text.bmp labels, mono/stereo)

**Files:** `Wamp/UI/MainPlayerView.swift`

The hardest task. `MainPlayerView` is layer-backed and hosts many subviews (panels, labels, sliders, buttons, time display). When skinned:
- Blit `main.bmp` covering the bottom 116 px of the view (above the title bar area).
- Hide title bar entirely; main.bmp's top 14 px provide the title strip.
- Hide left/right black panel NSViews (covered by main.bmp).
- Hide bitrate/sample rate/kbps/khz/mono/stereo NSTextFields. Render via TextSpriteRenderer + monoster sprites.
- Hide play indicator (deferred).
- Add invisible click hit-zones for close/minimize (since title bar is gone).

- [ ] **Step 1:** Add observer and visibility helper.

```swift
import Combine
// ... existing imports
private var skinObserver: AnyCancellable?
```

In `setupSubviews()` (after the existing setup, before `}`):

```swift
skinObserver = SkinManager.shared.$currentSkin
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.applySkinVisibility()
        self?.needsDisplay = true
        self?.needsLayout = true
    }
applySkinVisibility()
```

Add the helper method:

```swift
private func applySkinVisibility() {
    let active = WinampTheme.skinIsActive
    titleBar.isHidden = active
    leftPanel.isHidden = active
    rightPanel.isHidden = active
    bitrateLabel.isHidden = active
    sampleRateLabel.isHidden = active
    bitrateUnitLabel.isHidden = active
    sampleRateUnitLabel.isHidden = active
    monoLabel.isHidden = active
    stereoLabel.isHidden = active
    playIndicator.isHidden = active
}
```

- [ ] **Step 2:** Override `draw(_:)`. Currently `MainPlayerView` does not override `draw`. Add:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned()
    }
    // No drawBuiltIn needed: built-in rendering uses the layer.backgroundColor + subviews,
    // which AppKit composes automatically when subviews are visible.
}

private func drawSkinned() {
    // main.bmp covers the bottom 116 px of the view (the player area).
    // The view height includes the title bar area on top (which is hidden when skinned).
    let mainHeight: CGFloat = 116
    let mainRect = NSRect(x: 0, y: 0, width: bounds.width, height: mainHeight)
    if let bg = WinampTheme.sprite(.mainBackground) {
        // Disable interpolation so the 275×116 sprite stays crisp when scaled
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        bg.draw(in: mainRect)
        if let prev = prev { ctx?.imageInterpolation = prev }
    }

    // Mono/stereo sprites at fixed Webamp coordinates (Y measured from top of main.bmp).
    // Webamp positions: stereo at (212, 41), mono at (239, 41), each row is 12 px tall.
    // Convert to bounds coordinates: Y_bounds = mainHeight - 41 - 12 = 63
    let isStereo = playlistManager?.currentTrack?.isStereo ?? false
    let monoY: CGFloat = mainHeight - 41 - 12
    if let stereoSprite = WinampTheme.sprite(.stereo(active: isStereo)) {
        stereoSprite.draw(in: NSRect(x: 212, y: monoY, width: 29, height: 12))
    }
    if let monoSprite = WinampTheme.sprite(.mono(active: !isStereo)) {
        monoSprite.draw(in: NSRect(x: 239, y: monoY, width: 27, height: 12))
    }

    // Bitrate/sample rate via text.bmp.
    // Webamp positions: bitrate at (111, 43), 3 chars wide. Sample rate at (156, 43), 2 chars wide.
    // "kbps" and "khz" labels are NOT separate sprites — they're just text rendered at fixed positions.
    if let textSheet = WinampTheme.provider.textSheet,
       let track = playlistManager?.currentTrack {
        let textY = mainHeight - 43 - 6  // glyphs are 6 px tall
        let bitrateStr = track.bitrate > 0 ? String(format: "%3d", track.bitrate) : "   "
        let sampleStr = track.sampleRate > 0 ? String(format: "%2d", track.sampleRate / 1000) : "  "
        TextSpriteRenderer.draw(bitrateStr, at: NSPoint(x: 111, y: textY), sheet: textSheet)
        TextSpriteRenderer.draw(sampleStr,  at: NSPoint(x: 156, y: textY), sheet: textSheet)
        // "kbps" and "khz" — Wamp's existing labels show these as static strings. Render them similarly.
        TextSpriteRenderer.draw("kbps", at: NSPoint(x: 128, y: textY), sheet: textSheet)
        TextSpriteRenderer.draw("khz",  at: NSPoint(x: 168, y: textY), sheet: textSheet)
    }
}
```

**Important:** these coordinates are taken from Webamp's `main.css` and `MonoStereo.tsx`. They may need adjustment after smoke test (Task 17). The principle: take Webamp's pixel positions, convert from top-down (Webamp uses Y=0 at top of main.bmp) to bottom-up (AppKit uses Y=0 at bottom of view) using `Y_bounds = mainHeight - Y_webamp - height`.

- [ ] **Step 3:** Add invisible click hit-zones for close/minimize. After `applySkinVisibility` add:

```swift
private let closeHitZone = NSView()
private let minimizeHitZone = NSView()
```

Wait — those need to be properties. Add to the property list at the top:

```swift
private let closeHitZone = NSView()
private let minimizeHitZone = NSView()
```

In `setupSubviews()`:

```swift
addSubview(closeHitZone)
addSubview(minimizeHitZone)

let closeClick = NSClickGestureRecognizer(target: self, action: #selector(handleCloseClick))
closeHitZone.addGestureRecognizer(closeClick)

let minimizeClick = NSClickGestureRecognizer(target: self, action: #selector(handleMinimizeClick))
minimizeHitZone.addGestureRecognizer(minimizeClick)
```

In `applySkinVisibility()`:

```swift
closeHitZone.isHidden = !active
minimizeHitZone.isHidden = !active
```

In `layout()`, position them at the locations where main.bmp paints close/minimize:

```swift
// Webamp main.bmp close at (264, 3) 9×9; minimize at (244, 3) 9×9.
// Convert: Y_bounds = 116 - 3 - 9 = 104
if WinampTheme.skinIsActive {
    closeHitZone.frame = NSRect(x: 264, y: 104, width: 9, height: 9)
    minimizeHitZone.frame = NSRect(x: 244, y: 104, width: 9, height: 9)
}
```

Add the action methods:

```swift
@objc private func handleCloseClick() { NSApp.terminate(nil) }
@objc private func handleMinimizeClick() { window?.miniaturize(nil) }
```

- [ ] **Step 4:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/UI/MainPlayerView.swift
git commit -m "feat: skin MainPlayerView background, mono/stereo, text.bmp labels"
```

---

## Task 17: Skin EqualizerView, PlaylistView, LCDDisplay

**Files:** `Wamp/UI/EqualizerView.swift`, `Wamp/UI/PlaylistView.swift`, `Wamp/UI/Components/LCDDisplay.swift`

Three views remain. EqualizerView blits eqmain.bmp and hides freq/dB/PRE labels. PlaylistView renames CLR → REM ALL, blits frame tiles, hides info label and renders it via text.bmp. LCDDisplay renders scrolling text via text.bmp.

- [ ] **Step 1: EqualizerView**

Add observer (same pattern as Task 16). In `setupSubviews`, store the dB and PRE labels in properties for visibility toggling. Refactor existing inline `viewWithTag(...)` accesses to use stored properties:

```swift
private var dbLabels: [NSTextField] = []
private var preLabel: NSTextField?
private var dbUnitLabel: NSTextField?
```

In `setupSubviews`, replace the dB labels loop and PRE/dB label setup to store into these properties instead of (or in addition to) using tags.

Add visibility helper:

```swift
private func applySkinVisibility() {
    let active = WinampTheme.skinIsActive
    titleBar.isHidden = active
    bandLabels.forEach { $0.isHidden = active }
    dbLabels.forEach { $0.isHidden = active }
    preLabel?.isHidden = active
    dbUnitLabel?.isHidden = active
}
```

Override `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        if let bg = WinampTheme.sprite(.eqBackground) {
            // eqmain.bmp is 275×116. Wamp's EqualizerView.bounds.height may be smaller (112).
            // Blit at bottom-aligned 116 px high to preserve sprite proportions.
            bg.draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 116))
        }
        if let prev = prev { ctx?.imageInterpolation = prev }

        // Wire ON/AUTO/PRESETS button sprites via spriteKeyProvider (they're WinampButton instances).
        // This belongs in setupSubviews, not draw — see Step 1b below.
    }
}
```

**Step 1b:** In `setupSubviews`, after creating `onButton`, `autoButton`, `presetsButton`:

```swift
onButton.spriteKeyProvider = { active, pressed in .eqOnButton(active: active, pressed: pressed) }
autoButton.spriteKeyProvider = { active, pressed in .eqAutoButton(active: active, pressed: pressed) }
presetsButton.spriteKeyProvider = { _, pressed in .eqPresetsButton(pressed: pressed) }
```

The 10 band sliders + preamp are already `WinampSlider` instances and Task 15 wires their sprite rendering — no changes here.

- [ ] **Step 2: PlaylistView**

First, **rename** `clrButton` to `remAllButton`:

```bash
sed -i '' 's/clrButton/remAllButton/g' Wamp/UI/PlaylistView.swift
```

Then change the button title:

```swift
private let remAllButton = WinampButton(title: "REM ALL", style: .action)
```

(Replaces `private let clrButton = WinampButton(title: "CLR", style: .action)`)

The behavior (clearing the playlist on click) stays the same. The "REM ALL" name applies even in built-in mode.

Wire sprite keys for the three buttons:

```swift
addButton.spriteKeyProvider = { _, pressed in .playlistAddFile(pressed: pressed) }
remButton.spriteKeyProvider = { _, pressed in .playlistRemoveSelected(pressed: pressed) }
remAllButton.spriteKeyProvider = { _, pressed in .playlistRemoveAll(pressed: pressed) }
```

Add observer + visibility helper:

```swift
import Combine
private var skinObserver: AnyCancellable?

// in setupSubviews after existing setup:
skinObserver = SkinManager.shared.$currentSkin
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.applySkinVisibility()
        self?.tableView.reloadData()  // refresh row colors
        self?.needsDisplay = true
    }
applySkinVisibility()

private func applySkinVisibility() {
    let active = WinampTheme.skinIsActive
    titleBar.isHidden = active
    infoLabel.isHidden = active
    // searchField intentionally left visible — see spec §8 "searchField exception"
}
```

Override `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard WinampTheme.skinIsActive else { return }

    let ctx = NSGraphicsContext.current
    let prev = ctx?.imageInterpolation
    ctx?.imageInterpolation = .none
    defer { if let prev = prev { ctx?.imageInterpolation = prev } }

    let isActive = window?.isKeyWindow ?? true
    let w = bounds.width
    let h = bounds.height

    // Top: 3 corner pieces + repeating top-tile in between
    if let tl = WinampTheme.sprite(.playlistTopLeftCorner(active: isActive)) {
        tl.draw(in: NSRect(x: 0, y: h - 20, width: 25, height: 20))
    }
    if let tr = WinampTheme.sprite(.playlistTopRightCorner(active: isActive)) {
        tr.draw(in: NSRect(x: w - 25, y: h - 20, width: 25, height: 20))
    }
    // Title bar fills the middle of the top row
    if let title = WinampTheme.sprite(.playlistTopTitleBar(active: isActive)) {
        title.draw(in: NSRect(x: 25, y: h - 20, width: w - 50, height: 20))
    }

    // Sides: tile vertically
    if let lt = WinampTheme.sprite(.playlistLeftTile) {
        var y: CGFloat = 38
        while y < h - 20 {
            lt.draw(in: NSRect(x: 0, y: y, width: 12, height: min(29, h - 20 - y)))
            y += 29
        }
    }
    if let rt = WinampTheme.sprite(.playlistRightTile) {
        var y: CGFloat = 38
        while y < h - 20 {
            rt.draw(in: NSRect(x: w - 20, y: y, width: 20, height: min(29, h - 20 - y)))
            y += 29
        }
    }

    // Bottom: 3 corner pieces (bottom-right is wide, fills most of bottom row)
    if let bl = WinampTheme.sprite(.playlistBottomLeftCorner) {
        bl.draw(in: NSRect(x: 0, y: 0, width: 125, height: 38))
    }
    if let br = WinampTheme.sprite(.playlistBottomRightCorner) {
        br.draw(in: NSRect(x: w - 150, y: 0, width: 150, height: 38))
    }

    // Render info label via text.bmp
    if let textSheet = WinampTheme.provider.textSheet, let pm = playlistManager {
        let info = "\(pm.tracks.count) tracks"
        TextSpriteRenderer.draw(info, at: NSPoint(x: 10, y: 6), sheet: textSheet)
    }
}
```

(Coordinates are illustrative — adjust during smoke test.)

Update cell rendering colors to use `WinampTheme.provider.playlistStyle`:

```swift
// In tableView(_:viewFor:row:), where existing color references are
let style = WinampTheme.provider.playlistStyle
// use style.normal for normal text, style.current for currently-playing,
// style.normalBG for row background, style.selectedBG for selected row.
```

- [ ] **Step 3: LCDDisplay**

Add observer + drawSkinned:

```swift
import Combine
private var skinObserver: AnyCancellable?

// in init:
skinObserver = SkinManager.shared.$currentSkin
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.needsDisplay = true }
```

Refactor `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned()
    } else {
        drawBuiltIn(dirtyRect)
    }
}

private func drawBuiltIn(_ dirtyRect: NSRect) {
    // existing draw body (NSAttributedString rendering)
}

private func drawSkinned() {
    guard let textSheet = WinampTheme.provider.textSheet, !text.isEmpty else { return }
    let glyphCount = text.count
    let textWidth = CGFloat(glyphCount) * TextSpriteRenderer.glyphWidth
    let y = (bounds.height - TextSpriteRenderer.glyphHeight) / 2

    if textWidth <= bounds.width || !isScrolling {
        TextSpriteRenderer.draw(text, at: NSPoint(x: 2, y: y), sheet: textSheet)
    } else {
        let separator = "   *   "
        let combined = text + separator + text
        let pixelOffset = -scrollOffset
        TextSpriteRenderer.draw(combined, at: NSPoint(x: pixelOffset, y: y), sheet: textSheet)
    }
}
```

- [ ] **Step 4:** Build and commit:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
git add Wamp/UI/EqualizerView.swift Wamp/UI/PlaylistView.swift Wamp/UI/Components/LCDDisplay.swift
git commit -m "feat: skin EQ, Playlist, LCD with sprites and text.bmp"
```

---

## Task 18: End-to-end smoke test (zero-fallback verification)

**Files:** none (manual)

The acceptance test. **Four** skins ship in the repo at `skins/`. All must render without programmatic fallback bleed-through and without NSTextField labels showing in system fonts. Each skin exercises a different parser corner case:

| Skin | Tests |
|---|---|
| `base-2.91.wsz` | Full classic skin (all BMPs + region.txt + genex) — baseline |
| `OS8 AMP - Aquamarine.wsz` | Files in subdirectory; `nums_ex.bmp` instead of `numbers.bmp`; missing region/genex/viscolor/gen |
| `Blue Plasma.wsz` | Mixed-case filenames; non-image junk (`.psd`, `Readme.txt`); duplicate "Copy of..." files |
| `Radar_Amp.wsz` | Mixed-case across image AND text files (`PLEDIT.TXT`, `VISCOLOR.TXT` upper) |

- [ ] **Step 1: Build and launch**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Open `Wamp.xcodeproj` in Xcode, ⌘R. The app should launch in built-in mode (no skin), looking exactly as it does today.

- [ ] **Step 2: Load `skins/base-2.91.wsz` via View → Load Skin...**

Verify each:
- [ ] Main window background is `main.bmp` (no gray frame visible at edges)
- [ ] Title bar text shows the skin's "WINAMP" branding (NOT the Tahoma "WAMP" overlay)
- [ ] Title bar buttons (close/minimize) are sprite-rendered. Pin button is gone (permanently). Clicking the close-button area still terminates the app
- [ ] Transport buttons (prev/play/pause/stop/next/eject) render `cbuttons.bmp` sprites. Pressed states change correctly during clicks
- [ ] Time digits render `numbers.bmp` glyphs (not the seven-segment bars)
- [ ] Bitrate digits + "kbps" + "khz" rendered via text.bmp glyphs (small green bitmap font, NOT system Tahoma)
- [ ] mono/stereo indicator renders monoster.bmp sprites (NOT NSTextField)
- [ ] Seek slider renders posbar.bmp; thumb tracks correctly during drag
- [ ] Volume slider cycles through 28 background variants
- [ ] Balance slider cycles through 28 background variants
- [ ] Shuffle/Repeat/EQ/PL toggle buttons render shufrep.bmp sprites with active states
- [ ] Spectrum bar colors come from the skin's viscolor.txt (24-color gradient, not the bright lime green default)
- [ ] EQ window: eqmain.bmp covers the entire view; frequency labels (70/180/.../16K), dB labels (+12/0/-12), "PRE" text are part of the sprite — NO NSTextField overlays
- [ ] EQ ON / AUTO / PRESETS buttons render eqmain.bmp sprites
- [ ] EQ 10 band sliders + preamp render eqmain.bmp slider backgrounds and 14 thumb positions
- [ ] EQ response curve uses the 19 line colors sampled from eqmain.bmp
- [ ] Playlist: 9 frame tiles render correctly (corners + side tiles + bottom)
- [ ] Playlist row colors and font from pledit.txt
- [ ] Playlist info text (track count) rendered via text.bmp at the bottom (NOT NSTextField)
- [ ] "REM ALL" button visible (was "CLR", permanent rename)
- [ ] Window has a non-rectangular shape from region.txt (no rectangular corners visible)

**View Debugger acceptance:** Debug → View Debugging → Capture View Hierarchy. Confirm `isHidden = true` for: `bitrateLabel`, `sampleRateLabel`, `bitrateUnitLabel`, `sampleRateUnitLabel`, `monoLabel`, `stereoLabel`, `playIndicator`, `MainPlayerView.titleBar`, `leftPanel`, `rightPanel`, all `EqualizerView` band/dB/PRE/dB labels, `EqualizerView.titleBar`, `PlaylistView.titleBar`, `PlaylistView.infoLabel`. `searchField` should be visible (intentional exception).

- [ ] **Step 3: Load `skins/OS8 AMP - Aquamarine.wsz`**

This skin's files live inside an `Aquamarine/` subdirectory and it lacks `numbers.bmp`, `gen.bmp`, `genex.bmp`, `region.txt`, `viscolor.txt`. Verify:
- [ ] Files are found despite the subdirectory (parser strips paths and keys by basename)
- [ ] Time digits render — sourced from `nums_ex.bmp` (which loaded into the `images["numbers"]` key thanks to nums_ex unification)
- [ ] Spectrum uses default 24 viscolors (no `viscolor.txt` in this skin — defaults are correct, not a fallback)
- [ ] Window is rectangular (no `region.txt` — also correct, not a fallback)
- [ ] All other sprite elements render: background, transport, sliders, EQ, playlist frame
- [ ] Same View Debugger checks pass (all hide-when-skinned labels still hidden)

- [ ] **Step 3b: Load `skins/Blue Plasma.wsz`**

This skin tests case-insensitive filename matching and ignoring non-image files. It contains `Cbuttons.bmp`, `Numbers.bmp`, `Eqmain.bmp` etc. (capitalized), plus `.psd` source files, `Readme.txt`, and "Copy of Main.bmp" / "Eqmain copy.bmp" duplicates. Verify:
- [ ] Skin loads without crashing on `.psd` files (parser ignores them — `loadImage` only matches `.bmp`/`.png`)
- [ ] All elements render correctly despite mixed-case filenames (case-insensitive lookup works)
- [ ] "Copy of Main.bmp" does NOT replace `Main.bmp` (different basenames, both stored under different keys; only the canonical `main` key is read)
- [ ] `viscolor.txt` is parsed (lowercase in this skin)
- [ ] Same View Debugger checks

- [ ] **Step 3c: Load `skins/Radar_Amp.wsz`**

Tests mixed case across image AND text files (`PLEDIT.TXT`, `VISCOLOR.TXT` are uppercase here). Verify:
- [ ] Skin loads
- [ ] Playlist colors come from `PLEDIT.TXT` (uppercase) — confirms case-insensitive text-file lookup
- [ ] Spectrum colors come from `VISCOLOR.TXT` (uppercase)
- [ ] All sprite elements render
- [ ] Same View Debugger checks

- [ ] **Step 4: Test unload**

View → Unload Skin. Verify:
- All hidden NSTextFields reappear
- Programmatic rendering returns (no flicker, no zombie sprites)
- Pin button does NOT come back (permanently removed in Task 13)
- "REM ALL" button stays as "REM ALL" (permanent rename)

- [ ] **Step 5: Test persistence**

Load `base-2.91.wsz`, quit (⌘Q), relaunch. Skin restores on launch with no flicker (loaded synchronously before window creation).

- [ ] **Step 6: Test Always-on-Top menu**

View → Always on Top. Toggle a few times. Window stays on top when checked, returns to normal when unchecked. Quit, relaunch — state persists.

- [ ] **Step 7: Test error handling**

Try loading any non-skin ZIP. NSAlert appears, app stays on previous skin.

- [ ] **Step 8:** Commit any fixes discovered during the test:

```bash
git add -A
git commit -m "fix: smoke test corrections"
```

---

## Notes for the executor

- **Sprite coordinates may be slightly off.** The Webamp source is the source of truth. If a sprite looks misaligned during smoke test, open `https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts` and compare the offending case 1:1.
- **Disable image interpolation** before drawing sprite-sheet sliced images. The pattern is shown in `TextSpriteRenderer.draw()` and in MainPlayerView's `drawSkinned()`. Without it, 5×6 glyphs and 9×13 digits look blurry.
- **Webamp Y is top-down; AppKit Y is bottom-up.** When transcribing a Webamp coordinate like "draw at y=43", convert with `Y_appkit = mainHeight - Y_webamp - height`.
- **Don't change layout.** This work is about painting, not moving. If you find yourself adjusting frames in `layout()`, stop and re-read spec §1 and §12.3.
- **The transition order matters.** `SkinManager.transition(to:)` updates `WinampTheme.provider` first, then fires `@Published`. Don't reorder these. The first attempt did and produced render races.
