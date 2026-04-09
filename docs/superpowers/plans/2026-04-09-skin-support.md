# Skin Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Winamp 2.x classic skin (.wsz) support to Wamp, ported from Webamp's skin parser.

**Architecture:** SkinParser extracts sprites/colors/regions from .wsz ZIP files into SkinModel. WinampClassicSkin wraps the model behind SkinProvider protocol. WinampTheme becomes a facade delegating to the current SkinProvider. Views check for sprites first, fall back to programmatic rendering.

**Tech Stack:** Swift, AppKit, ZipFoundation (SPM), AVFoundation, Combine, Accelerate

**Spec:** `docs/superpowers/specs/2026-04-09-skin-support-design.md`

---

### Task 1: Add ZipFoundation via SPM

**Files:**
- Modify: `Wamp.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add ZipFoundation package dependency**

Open Xcode project and add the SPM dependency:

```bash
cd /Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac
# Use xcodebuild to resolve packages after manual addition, or use swift package commands
# Since there's no Package.swift, add via Xcode's SPM integration in the .xcodeproj
```

In Xcode: File → Add Package Dependencies → Enter URL: `https://github.com/weichsel/ZIPFoundation.git` → Up to Next Major Version from `0.9.0` → Add to target "Wamp".

Alternatively, if running headless, create a `Package.swift` wrapper or manually edit the pbxproj. The recommended approach is Xcode GUI since the project uses `.xcodeproj` (not SPM-native).

- [ ] **Step 2: Verify ZipFoundation resolves**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug -resolvePackageDependencies
```

Expected: resolves ZIPFoundation successfully.

- [ ] **Step 3: Verify project still builds**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: add ZipFoundation SPM dependency"
```

---

### Task 2: Create SkinModel and data types

**Files:**
- Create: `Wamp/Skinning/SkinModel.swift`

- [ ] **Step 1: Create directory and SkinModel.swift**

```bash
mkdir -p /Users/valerijbakalenko/Documents/Stranger/Code/AI/WinampMac/Wamp/Skinning
```

```swift
// Wamp/Skinning/SkinModel.swift
// Ported from: packages/webamp/js/types.ts @ webamp/master

import AppKit

struct SkinModel {
    let images: [String: CGImage]
    let viscolors: [NSColor]
    let playlistStyle: PlaylistStyle
    let regions: [String: [[CGPoint]]]
    let genLetterWidths: [String: Int]
    let genTextSprites: [String: CGImage]
    let genExColors: GenExColors?
    let cursors: [String: Data]
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
}

struct GenExColors {
    let itemBackground: NSColor
    let itemForeground: NSColor
    let windowBackground: NSColor
    let buttonText: NSColor
    let windowText: NSColor
    let divider: NSColor
    let playlistSelection: NSColor
    let listHeaderBackground: NSColor
    let listHeaderText: NSColor
    let listHeaderFrameTopAndLeft: NSColor
    let listHeaderFrameBottomAndRight: NSColor
    let listHeaderFramePressed: NSColor
    let listHeaderDeadArea: NSColor
    let scrollbarOne: NSColor
    let scrollbarTwo: NSColor
    let pressedScrollbarOne: NSColor
    let pressedScrollbarTwo: NSColor
    let scrollbarDeadArea: NSColor
    let listTextHighlighted: NSColor
    let listTextHighlightedBackground: NSColor
    let listTextSelected: NSColor
    let listTextSelectedBackground: NSColor
}

enum SkinParserError: LocalizedError {
    case missingRequiredFile(String)
    case invalidZip
    case corruptedImage(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredFile(let name): return "Required skin file missing: \(name)"
        case .invalidZip: return "Invalid or corrupted skin archive"
        case .corruptedImage(let name): return "Could not load image: \(name)"
        }
    }
}

extension PlaylistStyle {
    /// Default Winamp visualization colors (from Webamp baseSkin.json)
    static let defaultViscolors: [NSColor] = [
        NSColor(r: 0, g: 0, b: 0),
        NSColor(r: 24, g: 33, b: 41),
        NSColor(r: 239, g: 49, b: 16),
        NSColor(r: 206, g: 41, b: 16),
        NSColor(r: 214, g: 90, b: 0),
        NSColor(r: 214, g: 102, b: 0),
        NSColor(r: 214, g: 115, b: 0),
        NSColor(r: 198, g: 123, b: 8),
        NSColor(r: 222, g: 165, b: 24),
        NSColor(r: 214, g: 181, b: 33),
        NSColor(r: 189, g: 222, b: 41),
        NSColor(r: 148, g: 222, b: 33),
        NSColor(r: 41, g: 206, b: 16),
        NSColor(r: 50, g: 190, b: 16),
        NSColor(r: 57, g: 181, b: 16),
        NSColor(r: 49, g: 156, b: 8),
        NSColor(r: 41, g: 148, b: 0),
        NSColor(r: 24, g: 132, b: 8),
        NSColor(r: 255, g: 255, b: 255),
        NSColor(r: 214, g: 214, b: 222),
        NSColor(r: 181, g: 189, b: 189),
        NSColor(r: 160, g: 170, b: 175),
        NSColor(r: 148, g: 156, b: 165),
        NSColor(r: 150, g: 150, b: 150),
    ]
}

private extension NSColor {
    convenience init(r: Int, g: Int, b: Int) {
        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/SkinModel.swift
git commit -m "feat: add SkinModel data types"
```

---

### Task 3: Create SpriteKey and coordinate mapping

**Files:**
- Create: `Wamp/Skinning/SkinSprites.swift`

This is a large file (~900 LOC) ported from Webamp's `skinSprites.ts`. It contains the sprite coordinate constants for all Winamp skin elements.

- [ ] **Step 1: Create SkinSprites.swift with SpriteSheet enum, SpriteKey enum, and coordinate mapping**

Port all sprite definitions from `https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts`.

Use WebFetch to read the Webamp file, then translate every sprite group into Swift. The file must contain:

```swift
// Wamp/Skinning/SkinSprites.swift
// Ported from: packages/webamp/js/skinSprites.ts @ webamp/master

import Foundation

enum SpriteSheet: String, CaseIterable {
    case main, titlebar, cbuttons, numbers, numsEx
    case playpaus, monoster, posbar, volume, balance
    case eqmain, eqEx, pledit, shufrep, gen, text
}

enum SpriteKey: Hashable {
    // MAIN
    case mainBackground

    // CBUTTONS
    case previous(pressed: Bool)
    case play(pressed: Bool)
    case pause(pressed: Bool)
    case stop(pressed: Bool)
    case next(pressed: Bool)
    case eject(pressed: Bool)

    // NUMBERS
    case digit(Int)         // 0-9
    case digitMinus
    case digitNoMinus

    // PLAYPAUS
    case statusPlaying
    case statusPaused
    case statusStopped
    case statusWorking
    case statusNotWorking

    // MONOSTER
    case mono(active: Bool)
    case stereo(active: Bool)

    // TITLEBAR
    case titleBarActive
    case titleBarInactive
    case titleBarCloseButton(pressed: Bool)
    case titleBarMinimizeButton(pressed: Bool)
    case titleBarShadeButton(pressed: Bool)
    case titleBarOptionsButton(pressed: Bool)
    // shade mode sprites excluded from MVP

    // POSBAR
    case seekBackground
    case seekThumb(pressed: Bool)

    // VOLUME
    case volumeBackground(position: Int)   // 0-27
    case volumeThumb(pressed: Bool)

    // BALANCE
    case balanceBackground(position: Int)  // 0-27
    case balanceThumb(pressed: Bool)

    // SHUFREP
    case shuffleButton(active: Bool, pressed: Bool)
    case repeatButton(active: Bool, pressed: Bool)
    case eqButton(active: Bool, pressed: Bool)
    case playlistButton(active: Bool, pressed: Bool)

    // EQMAIN
    case eqBackground
    case eqTitleBarActive
    case eqTitleBarInactive
    case eqCloseButton(pressed: Bool)
    case eqSliderBackground
    case eqSliderThumb(pressed: Bool)
    case eqOnButton(active: Bool, pressed: Bool)
    case eqAutoButton(active: Bool, pressed: Bool)
    case eqPresetsButton(pressed: Bool)
    case eqGraphBackground
    case eqGraphLineColors
    case eqPreampLine

    // PLEDIT
    case playlistTopLeftCorner(active: Bool)
    case playlistTitleBar(active: Bool)
    case playlistTopRightCorner(active: Bool)
    case playlistTopTile(active: Bool)
    case playlistLeftTile
    case playlistRightTile
    case playlistBottomLeftCorner
    case playlistBottomTile
    case playlistBottomRightCorner
    case playlistScrollHandle(pressed: Bool)
    // playlist action buttons
    case playlistAddURL(pressed: Bool)
    case playlistAddDir(pressed: Bool)
    case playlistAddFile(pressed: Bool)
    case playlistRemoveAll(pressed: Bool)
    case playlistRemoveSelected(pressed: Bool)
    case playlistCrop(pressed: Bool)
    case playlistSelectAll(pressed: Bool)
    case playlistSelectZero(pressed: Bool)
    case playlistInvertSelection(pressed: Bool)
    case playlistSortList(pressed: Bool)
    case playlistFileInfo(pressed: Bool)
    case playlistMiscOptions(pressed: Bool)
    case playlistNewList(pressed: Bool)
    case playlistSaveList(pressed: Bool)
    case playlistLoadList(pressed: Bool)
    case playlistClose(pressed: Bool)
    case playlistVisualizerBackground
}

struct SpriteInfo {
    let sheet: SpriteSheet
    let rect: CGRect
}

// MARK: - Sprite Coordinate Mapping

enum SpriteCoordinates {
    /// Resolves a SpriteKey to its sheet and rectangle.
    /// All coordinates ported 1:1 from Webamp skinSprites.ts.
    static func resolve(_ key: SpriteKey) -> SpriteInfo {
        switch key {
        // MAIN
        case .mainBackground:
            return SpriteInfo(sheet: .main, rect: CGRect(x: 0, y: 0, width: 275, height: 116))

        // CBUTTONS
        case .previous(let pressed):
            return SpriteInfo(sheet: .cbuttons, rect: CGRect(x: 0, y: pressed ? 18 : 0, width: 23, height: 18))
        case .play(let pressed):
            return SpriteInfo(sheet: .cbuttons, rect: CGRect(x: 23, y: pressed ? 18 : 0, width: 23, height: 18))
        case .pause(let pressed):
            return SpriteInfo(sheet: .cbuttons, rect: CGRect(x: 46, y: pressed ? 18 : 0, width: 23, height: 18))
        case .stop(let pressed):
            return SpriteInfo(sheet: .cbuttons, rect: CGRect(x: 69, y: pressed ? 18 : 0, width: 23, height: 18))
        case .next(let pressed):
            return SpriteInfo(sheet: .cbuttons, rect: CGRect(x: 92, y: pressed ? 18 : 0, width: pressed ? 22 : 23, height: 18))
        case .eject(let pressed):
            return SpriteInfo(sheet: .cbuttons, rect: CGRect(x: 114, y: pressed ? 16 : 0, width: 22, height: 16))

        // NUMBERS
        case .digit(let n):
            let d = max(0, min(9, n))
            return SpriteInfo(sheet: .numbers, rect: CGRect(x: d * 9, y: 0, width: 9, height: 13))
        case .digitMinus:
            return SpriteInfo(sheet: .numbers, rect: CGRect(x: 20, y: 6, width: 5, height: 1))
        case .digitNoMinus:
            return SpriteInfo(sheet: .numbers, rect: CGRect(x: 9, y: 6, width: 5, height: 1))

        // PLAYPAUS
        case .statusPlaying:
            return SpriteInfo(sheet: .playpaus, rect: CGRect(x: 0, y: 0, width: 9, height: 9))
        case .statusPaused:
            return SpriteInfo(sheet: .playpaus, rect: CGRect(x: 9, y: 0, width: 9, height: 9))
        case .statusStopped:
            return SpriteInfo(sheet: .playpaus, rect: CGRect(x: 18, y: 0, width: 9, height: 9))
        case .statusNotWorking:
            return SpriteInfo(sheet: .playpaus, rect: CGRect(x: 36, y: 0, width: 9, height: 9))
        case .statusWorking:
            return SpriteInfo(sheet: .playpaus, rect: CGRect(x: 39, y: 0, width: 9, height: 9))

        // MONOSTER
        case .stereo(let active):
            return SpriteInfo(sheet: .monoster, rect: CGRect(x: 0, y: active ? 0 : 12, width: 29, height: 12))
        case .mono(let active):
            return SpriteInfo(sheet: .monoster, rect: CGRect(x: 29, y: active ? 0 : 12, width: 27, height: 12))

        // TITLEBAR
        case .titleBarActive:
            return SpriteInfo(sheet: .titlebar, rect: CGRect(x: 27, y: 0, width: 275, height: 14))
        case .titleBarInactive:
            return SpriteInfo(sheet: .titlebar, rect: CGRect(x: 27, y: 15, width: 275, height: 14))
        case .titleBarOptionsButton(let pressed):
            return SpriteInfo(sheet: .titlebar, rect: CGRect(x: 0, y: pressed ? 9 : 0, width: 9, height: 9))
        case .titleBarMinimizeButton(let pressed):
            return SpriteInfo(sheet: .titlebar, rect: CGRect(x: 9, y: pressed ? 9 : 0, width: 9, height: 9))
        case .titleBarShadeButton(let pressed):
            return SpriteInfo(sheet: .titlebar, rect: CGRect(x: 0, y: pressed ? 27 : 18, width: 9, height: 9))
        case .titleBarCloseButton(let pressed):
            return SpriteInfo(sheet: .titlebar, rect: CGRect(x: 18, y: pressed ? 9 : 0, width: 9, height: 9))

        // POSBAR
        case .seekBackground:
            return SpriteInfo(sheet: .posbar, rect: CGRect(x: 0, y: 0, width: 248, height: 10))
        case .seekThumb(let pressed):
            return SpriteInfo(sheet: .posbar, rect: CGRect(x: pressed ? 278 : 248, y: 0, width: 29, height: 10))

        // VOLUME
        case .volumeBackground(let position):
            let p = max(0, min(27, position))
            return SpriteInfo(sheet: .volume, rect: CGRect(x: 0, y: p * 15, width: 68, height: 13))
        case .volumeThumb(let pressed):
            return SpriteInfo(sheet: .volume, rect: CGRect(x: pressed ? 0 : 15, y: 422, width: 14, height: 11))

        // BALANCE
        case .balanceBackground(let position):
            let p = max(0, min(27, position))
            return SpriteInfo(sheet: .balance, rect: CGRect(x: 9, y: p * 15, width: 38, height: 13))
        case .balanceThumb(let pressed):
            return SpriteInfo(sheet: .balance, rect: CGRect(x: pressed ? 0 : 15, y: 422, width: 14, height: 11))

        // SHUFREP
        case .repeatButton(let active, let pressed):
            let y = (active ? 30 : 0) + (pressed ? 15 : 0)
            return SpriteInfo(sheet: .shufrep, rect: CGRect(x: 0, y: y, width: 28, height: 15))
        case .shuffleButton(let active, let pressed):
            let y = (active ? 30 : 0) + (pressed ? 15 : 0)
            return SpriteInfo(sheet: .shufrep, rect: CGRect(x: 28, y: y, width: 47, height: 15))
        case .eqButton(let active, let pressed):
            let x = pressed ? 46 : 0
            let y = active ? 73 : 61
            return SpriteInfo(sheet: .shufrep, rect: CGRect(x: x, y: y, width: 23, height: 12))
        case .playlistButton(let active, let pressed):
            let x = (pressed ? 46 : 0) + 23
            let y = active ? 73 : 61
            return SpriteInfo(sheet: .shufrep, rect: CGRect(x: x, y: y, width: 23, height: 12))

        // EQMAIN
        case .eqBackground:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: 0, width: 275, height: 116))
        case .eqTitleBarActive:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: 134, width: 275, height: 14))
        case .eqTitleBarInactive:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: 149, width: 275, height: 14))
        case .eqCloseButton(let pressed):
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: pressed ? 125 : 116, width: 9, height: 9))
        case .eqSliderBackground:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 13, y: 164, width: 209, height: 129))
        case .eqSliderThumb(let pressed):
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: pressed ? 176 : 164, width: 11, height: 11))
        case .eqOnButton(let active, let pressed):
            let x: Int
            if active {
                x = pressed ? 187 : 69
            } else {
                x = pressed ? 128 : 10
            }
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: x, y: 119, width: 26, height: 12))
        case .eqAutoButton(let active, let pressed):
            let x: Int
            if active {
                x = pressed ? 213 : 95
            } else {
                x = pressed ? 154 : 36
            }
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: x, y: 119, width: 32, height: 12))
        case .eqPresetsButton(let pressed):
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 224, y: pressed ? 176 : 164, width: 44, height: 12))
        case .eqGraphBackground:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: 294, width: 113, height: 19))
        case .eqGraphLineColors:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 115, y: 294, width: 1, height: 19))
        case .eqPreampLine:
            return SpriteInfo(sheet: .eqmain, rect: CGRect(x: 0, y: 314, width: 113, height: 1))

        // PLEDIT
        case .playlistTopLeftCorner(let active):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 0, y: active ? 0 : 21, width: 25, height: 20))
        case .playlistTitleBar(let active):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 26, y: active ? 0 : 21, width: 100, height: 20))
        case .playlistTopRightCorner(let active):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 153, y: active ? 0 : 21, width: 25, height: 20))
        case .playlistTopTile(let active):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 127, y: active ? 0 : 21, width: 25, height: 20))
        case .playlistLeftTile:
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 0, y: 42, width: 12, height: 29))
        case .playlistRightTile:
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 31, y: 42, width: 20, height: 29))
        case .playlistBottomLeftCorner:
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 0, y: 72, width: 125, height: 38))
        case .playlistBottomTile:
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 179, y: 0, width: 25, height: 38))
        case .playlistBottomRightCorner:
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 126, y: 72, width: 150, height: 38))
        case .playlistScrollHandle(let pressed):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: pressed ? 61 : 52, y: 53, width: 8, height: 18))
        case .playlistClose(let pressed):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: pressed ? 52 : 52, y: 42, width: 9, height: 9))
        case .playlistVisualizerBackground:
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: 205, y: 0, width: 75, height: 38))
        case .playlistAddURL(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 23 : 0, y: 111, width: 22, height: 18))
        case .playlistAddDir(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 23 : 0, y: 130, width: 22, height: 18))
        case .playlistAddFile(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 23 : 0, y: 149, width: 22, height: 18))
        case .playlistRemoveAll(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 77 : 54, y: 111, width: 22, height: 18))
        case .playlistCrop(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 77 : 54, y: 130, width: 22, height: 18))
        case .playlistRemoveSelected(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 77 : 54, y: 149, width: 22, height: 18))
        case .playlistInvertSelection(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 127 : 104, y: 111, width: 22, height: 18))
        case .playlistSelectZero(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 127 : 104, y: 130, width: 22, height: 18))
        case .playlistSelectAll(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 127 : 104, y: 149, width: 22, height: 18))
        case .playlistSortList(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 177 : 154, y: 111, width: 22, height: 18))
        case .playlistFileInfo(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 177 : 154, y: 130, width: 22, height: 18))
        case .playlistMiscOptions(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 177 : 154, y: 149, width: 22, height: 18))
        case .playlistNewList(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 227 : 204, y: 111, width: 22, height: 18))
        case .playlistSaveList(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 227 : 204, y: 130, width: 22, height: 18))
        case .playlistLoadList(let p):
            return SpriteInfo(sheet: .pledit, rect: CGRect(x: p ? 227 : 204, y: 149, width: 22, height: 18))
        }
    }
}
```

Note: The full file will be ~900 LOC. The agent implementing this task MUST fetch the Webamp skinSprites.ts file and port ALL sprite coordinates exactly. The code above shows the pattern — every case in `SpriteCoordinates.resolve()` must match the Webamp constant 1:1.

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/SkinSprites.swift
git commit -m "feat: add SpriteKey enum and coordinate mapping from Webamp"
```

---

### Task 4: Create IniParser

**Files:**
- Create: `Wamp/Skinning/IniParser.swift`

- [ ] **Step 1: Create IniParser.swift**

Port `parseIni()` from Webamp `utils.ts`:

```swift
// Wamp/Skinning/IniParser.swift
// Ported from: packages/webamp/js/utils.ts @ webamp/master

import Foundation

enum IniParser {
    /// Parses INI-format text into nested dictionary.
    /// Keys are lowercased. Handles ; comments, BOM, \r\n.
    static func parse(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var currentSection: String?

        let sectionRegex = try! NSRegularExpression(pattern: #"^\s*\[(.+?)\]\s*$"#)
        let propertyRegex = try! NSRegularExpression(pattern: #"^\s*([^;][^=]*)\s*=\s*(.*)\s*$"#)

        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "") // BOM

        for line in cleaned.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(";") { continue }

            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let match = sectionRegex.firstMatch(in: trimmed, range: range),
               let sectionRange = Range(match.range(at: 1), in: trimmed) {
                currentSection = String(trimmed[sectionRange]).lowercased()
                if result[currentSection!] == nil {
                    result[currentSection!] = [:]
                }
            } else if let section = currentSection,
                      let match = propertyRegex.firstMatch(in: trimmed, range: range),
                      let keyRange = Range(match.range(at: 1), in: trimmed),
                      let valueRange = Range(match.range(at: 2), in: trimmed) {
                let key = String(trimmed[keyRange]).trimmingCharacters(in: .whitespaces).lowercased()
                var value = String(trimmed[valueRange]).trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes
                if value.count >= 2,
                   (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                result[section]?[key] = value
            }
        }
        return result
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/IniParser.swift
git commit -m "feat: add IniParser ported from Webamp"
```

---

### Task 5: Create ViscolorsParser

**Files:**
- Create: `Wamp/Skinning/ViscolorsParser.swift`

- [ ] **Step 1: Create ViscolorsParser.swift**

```swift
// Wamp/Skinning/ViscolorsParser.swift
// Ported from: packages/webamp/js/utils.ts (parseViscolors) @ webamp/master

import AppKit

enum ViscolorsParser {
    private static let colorRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s*,?\s*(\d+)\s*,?\s*(\d+)"#
    )

    /// Parses viscolor.txt content into 24 NSColors.
    /// Missing entries are filled from defaults.
    static func parse(_ text: String) -> [NSColor] {
        var colors = PlaylistStyle.defaultViscolors
        let lines = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() where index < 24 {
            let range = NSRange(line.startIndex..., in: line)
            if let match = colorRegex.firstMatch(in: line, range: range),
               let rRange = Range(match.range(at: 1), in: line),
               let gRange = Range(match.range(at: 2), in: line),
               let bRange = Range(match.range(at: 3), in: line),
               let r = Int(line[rRange]),
               let g = Int(line[gRange]),
               let b = Int(line[bRange]) {
                colors[index] = NSColor(
                    red: CGFloat(r) / 255.0,
                    green: CGFloat(g) / 255.0,
                    blue: CGFloat(b) / 255.0,
                    alpha: 1.0
                )
            }
        }
        return colors
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/ViscolorsParser.swift
git commit -m "feat: add ViscolorsParser"
```

---

### Task 6: Create PlaylistStyleParser

**Files:**
- Create: `Wamp/Skinning/PlaylistStyleParser.swift`

- [ ] **Step 1: Create PlaylistStyleParser.swift**

```swift
// Wamp/Skinning/PlaylistStyleParser.swift
// Ported from: packages/webamp/js/skinParserUtils.ts (getPlaylistStyle) @ webamp/master

import AppKit

enum PlaylistStyleParser {
    /// Parses pledit.txt content into PlaylistStyle.
    /// Merges with defaults for missing fields.
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

    /// Normalizes Winamp color string to NSColor.
    /// Handles: "00FF00", "#00FF00", "#00FF00FF" (extra chars trimmed to 7).
    private static func parseColor(_ value: String?) -> NSColor? {
        guard var hex = value?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else {
            return nil
        }
        if !hex.hasPrefix("#") { hex = "#" + hex }
        if hex.count > 7 { hex = String(hex.prefix(7)) }
        guard hex.count == 7 else { return nil }

        let scanner = Scanner(string: hex)
        scanner.currentIndex = hex.index(after: hex.startIndex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }

        return NSColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/PlaylistStyleParser.swift
git commit -m "feat: add PlaylistStyleParser"
```

---

### Task 7: Create RegionParser

**Files:**
- Create: `Wamp/Skinning/RegionParser.swift`

- [ ] **Step 1: Create RegionParser.swift**

```swift
// Wamp/Skinning/RegionParser.swift
// Ported from: packages/webamp/js/regionParser.ts @ webamp/master

import Foundation

enum RegionParser {
    /// Parses region.txt content into section -> array of polygons.
    /// Each polygon is an array of CGPoints (minimum 3 points).
    static func parse(_ text: String) -> [String: [[CGPoint]]] {
        let ini = IniParser.parse(text)
        var result: [String: [[CGPoint]]] = [:]

        for (section, properties) in ini {
            guard let numpointsStr = properties["numpoints"],
                  let pointlistStr = properties["pointlist"] else { continue }

            let numpoints = numpointsStr
                .components(separatedBy: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

            let allCoords = pointlistStr
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            var allPoints: [CGPoint] = []
            for coord in allCoords {
                let parts = coord.components(separatedBy: ",")
                if parts.count == 2,
                   let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                   let y = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    allPoints.append(CGPoint(x: x, y: y))
                }
            }

            var polygons: [[CGPoint]] = []
            var offset = 0
            for count in numpoints {
                guard offset + count <= allPoints.count else { break }
                let polygon = Array(allPoints[offset..<(offset + count)])
                if polygon.count >= 3 {
                    polygons.append(polygon)
                }
                offset += count
            }

            if !polygons.isEmpty {
                result[section] = polygons
            }
        }
        return result
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/RegionParser.swift
git commit -m "feat: add RegionParser"
```

---

### Task 8: Create GenExColorsParser

**Files:**
- Create: `Wamp/Skinning/GenExColorsParser.swift`

- [ ] **Step 1: Create GenExColorsParser.swift**

```swift
// Wamp/Skinning/GenExColorsParser.swift
// Ported from: packages/webamp/js/skinParserUtils.ts (getGenExColors) @ webamp/master

import AppKit

enum GenExColorsParser {
    /// X coordinates to sample from genex.bmp at Y=0 (22 colors).
    private static let xCoordinates = [
        48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68,
        70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90
    ]

    /// Extracts 22 UI colors from genex.bmp by sampling pixels at row Y=0.
    static func parse(from image: CGImage) -> GenExColors? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }

        let buffer = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)

        func colorAt(x: Int) -> NSColor {
            guard x < image.width else { return .black }
            let offset = x * 4 // Y=0, first row
            let r = CGFloat(buffer[offset]) / 255.0
            let g = CGFloat(buffer[offset + 1]) / 255.0
            let b = CGFloat(buffer[offset + 2]) / 255.0
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }

        let c = xCoordinates.map { colorAt(x: $0) }
        guard c.count == 22 else { return nil }

        return GenExColors(
            itemBackground: c[0], itemForeground: c[1],
            windowBackground: c[2], buttonText: c[3],
            windowText: c[4], divider: c[5],
            playlistSelection: c[6], listHeaderBackground: c[7],
            listHeaderText: c[8], listHeaderFrameTopAndLeft: c[9],
            listHeaderFrameBottomAndRight: c[10], listHeaderFramePressed: c[11],
            listHeaderDeadArea: c[12], scrollbarOne: c[13],
            scrollbarTwo: c[14], pressedScrollbarOne: c[15],
            pressedScrollbarTwo: c[16], scrollbarDeadArea: c[17],
            listTextHighlighted: c[18], listTextHighlightedBackground: c[19],
            listTextSelected: c[20], listTextSelectedBackground: c[21]
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/GenExColorsParser.swift
git commit -m "feat: add GenExColorsParser"
```

---

### Task 9: Create SkinParserUtils (ZIP extraction + image loading)

**Files:**
- Create: `Wamp/Skinning/SkinParserUtils.swift`

- [ ] **Step 1: Create SkinParserUtils.swift**

```swift
// Wamp/Skinning/SkinParserUtils.swift
// Ported from: packages/webamp/js/skinParserUtils.ts @ webamp/master

import AppKit
import ZIPFoundation

enum SkinParserUtils {

    // MARK: - ZIP Extraction

    /// Extracts all files from ZIP data into a dictionary.
    /// Keys are lowercased filenames (no directory prefix). Last match wins for duplicates.
    static func extractZip(_ data: Data) throws -> [String: Data] {
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw SkinParserError.invalidZip
        }

        var entries: [String: Data] = [:]
        for entry in archive where entry.type == .file {
            var fileData = Data()
            _ = try archive.extract(entry) { chunk in
                fileData.append(chunk)
            }
            // Normalize: lowercase, take filename only (strip directory), normalize separators
            let name = entry.path
                .replacingOccurrences(of: "\\", with: "/")
                .components(separatedBy: "/")
                .last?
                .lowercased() ?? ""
            if !name.isEmpty {
                entries[name] = fileData // last match wins (Webamp behavior)
            }
        }
        return entries
    }

    /// Case-insensitive file lookup from extracted entries.
    static func findFile(_ name: String, in entries: [String: Data]) -> Data? {
        return entries[name.lowercased()]
    }

    // MARK: - Image Loading

    /// Loads BMP or PNG data as CGImage via NSImage.
    /// Returns nil if the data cannot be decoded.
    static func loadImage(from data: Data) -> CGImage? {
        guard let nsImage = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Loads a named image file (tries both .bmp and .png extensions).
    static func loadImage(named name: String, from entries: [String: Data]) -> CGImage? {
        // Try exact name first
        if let data = entries[name.lowercased()] {
            return loadImage(from: data)
        }
        // Try alternate extension
        let base = (name as NSString).deletingPathExtension.lowercased()
        for ext in ["bmp", "png"] {
            let key = "\(base).\(ext)"
            if let data = entries[key] {
                return loadImage(from: data)
            }
        }
        return nil
    }

    /// Loads all sprite sheet images from ZIP entries.
    static func loadAllImages(from entries: [String: Data]) -> [String: CGImage] {
        var images: [String: CGImage] = [:]
        for sheet in SpriteSheet.allCases {
            let baseName = sheet.rawValue
            if let image = loadImage(named: "\(baseName).bmp", from: entries) {
                images[baseName] = image
            }
        }
        return images
    }

    // MARK: - Sprite Slicing

    /// Crops a sprite from a sheet image using the given rect.
    /// Returns nil if the rect is outside the image bounds.
    static func sliceSprite(from sheet: CGImage, rect: CGRect) -> NSImage? {
        let cgRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        guard let cropped = sheet.cropping(to: cgRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    // MARK: - GenTextSprites

    /// Scans gen.bmp for letter sprites at Y=88 (selected) and Y=96 (normal).
    /// Returns letter widths and sliced letter sprites.
    static func parseGenTextSprites(
        from image: CGImage
    ) -> (widths: [String: Int], sprites: [String: CGImage]) {
        guard image.height > 96 + 7 else { return ([:], [:]) }

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return ([:], [:]) }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return ([:], [:]) }

        let buffer = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)

        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\"\u{00C5}\u{00D6}\u{00C4}0123456789..."

        var widths: [String: Int] = [:]
        var sprites: [String: CGImage] = [:]

        for (yOffset, suffix) in [(88, "_SELECTED"), (96, "")] {
            // Background color from first pixel of the row
            let bgOffset = yOffset * image.width * 4
            let bgR = buffer[bgOffset]
            let bgG = buffer[bgOffset + 1]
            let bgB = buffer[bgOffset + 2]

            var x = 0
            for char in letters {
                guard x < image.width else { break }
                // Scan right until background color found
                var charWidth = 0
                while x + charWidth < image.width {
                    let px = (yOffset * image.width + x + charWidth) * 4
                    if buffer[px] == bgR && buffer[px + 1] == bgG && buffer[px + 2] == bgB && charWidth > 0 {
                        break
                    }
                    charWidth += 1
                }

                let name = "GEN_TEXT_\(char)\(suffix)"
                widths[name] = charWidth

                if charWidth > 0, let cropped = image.cropping(to: CGRect(x: x, y: yOffset, width: charWidth, height: 7)) {
                    sprites[name] = cropped
                }

                x += charWidth + 1 // skip 1px separator
            }
        }

        return (widths, sprites)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/SkinParserUtils.swift
git commit -m "feat: add SkinParserUtils (ZIP, image loading, sprite slicing)"
```

---

### Task 10: Create SkinParser orchestrator

**Files:**
- Create: `Wamp/Skinning/SkinParser.swift`

- [ ] **Step 1: Create SkinParser.swift**

```swift
// Wamp/Skinning/SkinParser.swift
// Ported from: packages/webamp/js/skinParser.js @ webamp/master

import AppKit

final class SkinParser {

    /// Synchronous parse for app startup.
    func parseSync(contentsOf url: URL) throws -> SkinModel {
        let data = try Data(contentsOf: url)
        return try buildModel(from: data)
    }

    /// Async parse for runtime skin loading.
    func parse(contentsOf url: URL) async throws -> SkinModel {
        let data = try Data(contentsOf: url)
        return try buildModel(from: data)
    }

    /// Shared parsing logic used by both sync and async paths.
    private func buildModel(from data: Data) throws -> SkinModel {
        let entries = try SkinParserUtils.extractZip(data)

        // main.bmp is required
        guard let mainImage = SkinParserUtils.loadImage(named: "main.bmp", from: entries) else {
            throw SkinParserError.missingRequiredFile("main.bmp")
        }

        // Load all sprite sheet images
        var images = SkinParserUtils.loadAllImages(from: entries)
        images["main"] = mainImage

        // Parse viscolor.txt
        let viscolors: [NSColor]
        if let viscolorData = SkinParserUtils.findFile("viscolor.txt", in: entries),
           let text = String(data: viscolorData, encoding: .utf8)
              ?? String(data: viscolorData, encoding: .windowsCP1252) {
            viscolors = ViscolorsParser.parse(text)
        } else {
            viscolors = PlaylistStyle.defaultViscolors
        }

        // Parse pledit.txt
        let playlistStyle: PlaylistStyle
        if let pleditData = SkinParserUtils.findFile("pledit.txt", in: entries),
           let text = String(data: pleditData, encoding: .utf8)
              ?? String(data: pleditData, encoding: .windowsCP1252) {
            playlistStyle = PlaylistStyleParser.parse(text)
        } else {
            playlistStyle = .default
        }

        // Parse region.txt
        let regions: [String: [[CGPoint]]]
        if let regionData = SkinParserUtils.findFile("region.txt", in: entries),
           let text = String(data: regionData, encoding: .utf8)
              ?? String(data: regionData, encoding: .windowsCP1252) {
            regions = RegionParser.parse(text)
        } else {
            regions = [:]
        }

        // Parse genex.bmp for UI colors
        let genExColors: GenExColors?
        if let genexImage = SkinParserUtils.loadImage(named: "genex.bmp", from: entries) {
            genExColors = GenExColorsParser.parse(from: genexImage)
        } else {
            genExColors = nil
        }

        // Parse gen.bmp for text sprites
        let genLetterWidths: [String: Int]
        let genTextSprites: [String: CGImage]
        if let genImage = images["gen"] {
            let result = SkinParserUtils.parseGenTextSprites(from: genImage)
            genLetterWidths = result.widths
            genTextSprites = result.sprites
        } else {
            genLetterWidths = [:]
            genTextSprites = [:]
        }

        // Collect cursor data (raw, parsing deferred to Phase 1-Extended)
        var cursors: [String: Data] = [:]
        for key in entries.keys where key.hasSuffix(".cur") {
            cursors[key] = entries[key]
        }

        return SkinModel(
            images: images,
            viscolors: viscolors,
            playlistStyle: playlistStyle,
            regions: regions,
            genLetterWidths: genLetterWidths,
            genTextSprites: genTextSprites,
            genExColors: genExColors,
            cursors: cursors
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/SkinParser.swift
git commit -m "feat: add SkinParser orchestrator"
```

---

### Task 11: Create SkinProvider protocol, BuiltInSkin, and WinampClassicSkin

**Files:**
- Create: `Wamp/Skinning/SkinProvider.swift`
- Create: `Wamp/Skinning/WinampClassicSkin.swift`

- [ ] **Step 1: Create SkinProvider.swift**

```swift
// Wamp/Skinning/SkinProvider.swift

import AppKit

protocol SkinProvider: AnyObject {
    func sprite(_ key: SpriteKey) -> NSImage?
    var frameBackground: NSColor { get }
    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var genExColors: GenExColors? { get }
    var mainWindowRegion: NSBezierPath? { get }
    var equalizerWindowRegion: NSBezierPath? { get }
}

final class BuiltInSkin: SkinProvider {
    func sprite(_ key: SpriteKey) -> NSImage? { nil }
    var frameBackground: NSColor { NSColor(hex: 0x3C4250) }
    var viscolors: [NSColor] { PlaylistStyle.defaultViscolors }
    var playlistStyle: PlaylistStyle { .default }
    var genExColors: GenExColors? { nil }
    var mainWindowRegion: NSBezierPath? { nil }
    var equalizerWindowRegion: NSBezierPath? { nil }
}
```

- [ ] **Step 2: Create WinampClassicSkin.swift**

```swift
// Wamp/Skinning/WinampClassicSkin.swift

import AppKit

final class WinampClassicSkin: SkinProvider {
    private let model: SkinModel
    private let spriteCache = NSCache<NSString, NSImage>()

    init(model: SkinModel) {
        self.model = model
    }

    func sprite(_ key: SpriteKey) -> NSImage? {
        let cacheKey = "\(key)" as NSString
        if let cached = spriteCache.object(forKey: cacheKey) {
            return cached
        }

        let info = SpriteCoordinates.resolve(key)
        guard let sheet = model.images[info.sheet.rawValue] else { return nil }
        guard let image = SkinParserUtils.sliceSprite(from: sheet, rect: info.rect) else { return nil }

        spriteCache.setObject(image, forKey: cacheKey)
        return image
    }

    var frameBackground: NSColor {
        NSColor(hex: 0x3C4250) // Skins don't change frame bg; use default
    }

    var viscolors: [NSColor] { model.viscolors }
    var playlistStyle: PlaylistStyle { model.playlistStyle }
    var genExColors: GenExColors? { model.genExColors }

    var mainWindowRegion: NSBezierPath? {
        buildRegionPath(for: "normal", windowHeight: 116)
    }

    var equalizerWindowRegion: NSBezierPath? {
        buildRegionPath(for: "equalizer", windowHeight: 116)
    }

    /// Converts region polygons to NSBezierPath with Y-flip (Winamp top-left -> macOS bottom-left).
    private func buildRegionPath(for section: String, windowHeight: CGFloat) -> NSBezierPath? {
        guard let polygons = model.regions[section], !polygons.isEmpty else { return nil }

        let path = NSBezierPath()
        for polygon in polygons {
            guard polygon.count >= 3 else { continue }
            let flipped = polygon.map { CGPoint(x: $0.x, y: windowHeight - $0.y) }
            path.move(to: flipped[0])
            for point in flipped.dropFirst() {
                path.line(to: point)
            }
            path.close()
        }
        return path
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/Skinning/SkinProvider.swift Wamp/Skinning/WinampClassicSkin.swift
git commit -m "feat: add SkinProvider protocol, BuiltInSkin, and WinampClassicSkin"
```

---

### Task 12: Create SkinManager

**Files:**
- Create: `Wamp/Skinning/SkinManager.swift`

- [ ] **Step 1: Create SkinManager.swift**

```swift
// Wamp/Skinning/SkinManager.swift

import AppKit
import Combine

final class SkinManager: ObservableObject {
    static let shared = SkinManager()

    @Published private(set) var currentSkin: SkinProvider = BuiltInSkin()

    private init() {}

    func loadSkin(from url: URL) async throws {
        let model = try await SkinParser().parse(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        await MainActor.run {
            self.currentSkin = skin
            WinampTheme.provider = skin
        }
    }

    /// Synchronous load for app startup (avoids flicker).
    /// Reuses SkinParser's internal logic but runs synchronously.
    func loadSkinSync(from url: URL) throws {
        let parser = SkinParser()
        let model = try parser.parseSync(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        self.currentSkin = skin
        WinampTheme.provider = skin
    }

    func unloadSkin() {
        currentSkin = BuiltInSkin()
        WinampTheme.provider = currentSkin
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Skinning/SkinManager.swift
git commit -m "feat: add SkinManager with sync/async skin loading"
```

---

### Task 13: Refactor WinampTheme from enum to class facade

**Files:**
- Modify: `Wamp/UI/WinampTheme.swift`

- [ ] **Step 1: Convert WinampTheme from enum to final class**

Change line 14 from `enum WinampTheme` to `final class WinampTheme`. Add the static provider property and sprite method. Change `frameBackground` from `static let` to computed property. All other color/font/dimension properties remain as `static let` (they are only used when sprite() returns nil — built-in rendering fallback).

```swift
// Line 14: change from:
enum WinampTheme {
// to:
final class WinampTheme {
    static var provider: SkinProvider = BuiltInSkin()

    static func sprite(_ key: SpriteKey) -> NSImage? {
        provider.sprite(key)
    }

    // frameBackground becomes computed (delegates to provider)
    static var frameBackground: NSColor { provider.frameBackground }
```

Keep all other `static let` properties exactly as they are (lines 17-108). They remain hardcoded — they're the fallback values used when no skin sprite is available.

- [ ] **Step 2: Verify build — all existing references to WinampTheme must still compile**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` — no changes to any view code, all `WinampTheme.someColor` references still work.

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/WinampTheme.swift
git commit -m "refactor: convert WinampTheme from enum to class facade with SkinProvider"
```

---

### Task 14: Add skin persistence to StateManager

**Files:**
- Modify: `Wamp/Models/StateManager.swift` (line 4-16, AppState struct)

- [ ] **Step 1: Add skinPath field to AppState**

Add after line 15 (before the closing brace of AppState):

```swift
    var skinPath: String?
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/Models/StateManager.swift
git commit -m "feat: add skinPath to AppState for skin persistence"
```

---

### Task 15: Add Load/Unload Skin menu and startup restore in AppDelegate

**Files:**
- Modify: `Wamp/AppDelegate.swift`

- [ ] **Step 1: Add skin restore at app startup**

In `applicationDidFinishLaunching`, after `loadEQState()` call (around line 36) and BEFORE `MainWindow` creation, add:

```swift
// Restore saved skin
let state = stateManager.loadAppState()
if let skinPath = state.skinPath,
   FileManager.default.fileExists(atPath: skinPath) {
    try? SkinManager.shared.loadSkinSync(from: URL(fileURLWithPath: skinPath))
}
```

- [ ] **Step 2: Add menu items in setupMainMenu()**

After the existing View menu items (after line 170), add:

```swift
viewMenu.addItem(NSMenuItem.separator())

let loadSkinItem = NSMenuItem(title: "Load Skin...", action: #selector(loadSkin), keyEquivalent: "S")
loadSkinItem.keyEquivalentModifierMask = [.command, .shift]
loadSkinItem.target = self
viewMenu.addItem(loadSkinItem)

let unloadSkinItem = NSMenuItem(title: "Unload Skin", action: #selector(unloadSkin), keyEquivalent: "")
unloadSkinItem.target = self
viewMenu.addItem(unloadSkinItem)
```

- [ ] **Step 3: Add loadSkin and unloadSkin action methods**

Add these methods to AppDelegate:

```swift
@objc func loadSkin() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [
        .init(filenameExtension: "wsz")!,
        .zip
    ]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else { return }

    Task {
        do {
            try await SkinManager.shared.loadSkin(from: url)
            // Persist skin path
            var appState = stateManager.loadAppState()
            appState.skinPath = url.path
            stateManager.saveAppState(appState)
            // Apply region mask
            mainWindow.applyRegionMask()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to load skin"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

@objc func unloadSkin() {
    SkinManager.shared.unloadSkin()
    var appState = stateManager.loadAppState()
    appState.skinPath = nil
    stateManager.saveAppState(appState)
    mainWindow.applyRegionMask()
}
```

Note: The `saveAppState(_:)` method may not exist yet on StateManager. If so, add a simple method:

```swift
// In StateManager.swift
func saveAppState(_ state: AppState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: appStateURL, options: .atomic)
}
```

Also need to add `import UniformTypeIdentifiers` at the top of AppDelegate.swift for `.zip` UTType.

- [ ] **Step 4: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Wamp/AppDelegate.swift Wamp/Models/StateManager.swift
git commit -m "feat: add Load/Unload Skin menu items and startup restore"
```

---

### Task 16: Add skin observer and sprite support to WinampButton

**Files:**
- Modify: `Wamp/UI/Components/WinampButton.swift`

- [ ] **Step 1: Add spriteKeyProvider and skin observer**

Add these properties after line 15 (after `var drawIcon`):

```swift
var spriteKeyProvider: ((Bool) -> SpriteKey)?
private var skinCancellable: AnyCancellable?
```

Add import at top:

```swift
import Combine
```

In `init`, add skin observer setup:

```swift
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.needsDisplay = true }
```

- [ ] **Step 2: Add sprite rendering in draw()**

At the beginning of `draw(_ dirtyRect:)` (line 29), add before existing code:

```swift
if let keyProvider = spriteKeyProvider,
   let image = WinampTheme.sprite(keyProvider(isPressed)) {
    image.draw(in: bounds)
    return
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/Components/WinampButton.swift
git commit -m "feat: add sprite rendering support to WinampButton"
```

---

### Task 17: Wire TransportBar buttons to sprite keys

**Files:**
- Modify: `Wamp/UI/Components/TransportBar.swift`

- [ ] **Step 1: Set spriteKeyProvider on each transport button**

In `setupButtons()` (line 25), after the button assignment lines (lines 27-32), add:

```swift
prevButton.spriteKeyProvider = { pressed in .previous(pressed: pressed) }
playButton.spriteKeyProvider = { pressed in .play(pressed: pressed) }
pauseButton.spriteKeyProvider = { pressed in .pause(pressed: pressed) }
stopButton.spriteKeyProvider = { pressed in .stop(pressed: pressed) }
nextButton.spriteKeyProvider = { pressed in .next(pressed: pressed) }
ejectButton.spriteKeyProvider = { pressed in .eject(pressed: pressed) }
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/Components/TransportBar.swift
git commit -m "feat: wire transport buttons to skin sprite keys"
```

---

### Task 18: Add sprite support to WinampSlider

**Files:**
- Modify: `Wamp/UI/Components/WinampSlider.swift`

- [ ] **Step 1: Add skin observer**

Add at top of file:

```swift
import Combine
```

Add property:

```swift
private var skinCancellable: AnyCancellable?
```

In init, add:

```swift
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.needsDisplay = true }
```

- [ ] **Step 2: Add sprite rendering at the top of draw()**

At the beginning of `draw(_ dirtyRect:)` (line 48), add sprite lookup before existing horizontal/vertical rendering:

```swift
if trySpriteRender() { return }
```

Add the helper method:

```swift
private func trySpriteRender() -> Bool {
    switch style {
    case .seek:
        guard let bg = WinampTheme.sprite(.seekBackground) else { return false }
        bg.draw(in: bounds)
        let thumbPressed = isDragging
        let normalizedX = CGFloat((value - minValue) / (maxValue - minValue))
        let thumbW: CGFloat = 29
        let thumbX = normalizedX * (bounds.width - thumbW)
        if let thumb = WinampTheme.sprite(.seekThumb(pressed: thumbPressed)) {
            thumb.draw(in: NSRect(x: thumbX, y: 0, width: thumbW, height: bounds.height))
        }
        return true

    case .volume:
        let position = Int(CGFloat((value - minValue) / (maxValue - minValue)) * 27)
        guard let bg = WinampTheme.sprite(.volumeBackground(position: position)) else { return false }
        bg.draw(in: bounds)
        let normalizedX = CGFloat((value - minValue) / (maxValue - minValue))
        let thumbW: CGFloat = 14
        let thumbX = normalizedX * (bounds.width - thumbW)
        if let thumb = WinampTheme.sprite(.volumeThumb(pressed: isDragging)) {
            thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: 14, height: 11))
        }
        return true

    case .balance:
        let normalized = CGFloat((value - minValue) / (maxValue - minValue))
        let position = Int(normalized * 27)
        guard let bg = WinampTheme.sprite(.balanceBackground(position: position)) else { return false }
        bg.draw(in: bounds)
        let thumbW: CGFloat = 14
        let thumbX = normalized * (bounds.width - thumbW)
        if let thumb = WinampTheme.sprite(.balanceThumb(pressed: isDragging)) {
            thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: 14, height: 11))
        }
        return true

    case .eqBand:
        guard let bg = WinampTheme.sprite(.eqSliderBackground) else { return false }
        // EQ slider background is a shared image; draw the portion for this band
        bg.draw(in: bounds)
        let normalized = CGFloat((value - minValue) / (maxValue - minValue))
        let thumbY = normalized * (bounds.height - 11)
        if let thumb = WinampTheme.sprite(.eqSliderThumb(pressed: isDragging)) {
            thumb.draw(in: NSRect(x: (bounds.width - 11) / 2, y: thumbY, width: 11, height: 11))
        }
        return true
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/Components/WinampSlider.swift
git commit -m "feat: add sprite rendering to WinampSlider for all 4 styles"
```

---

### Task 19: Add sprite support to TitleBarView

**Files:**
- Modify: `Wamp/UI/Components/TitleBarView.swift`

- [ ] **Step 1: Add skin observer**

Add import and property:

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?
```

In init or setup, add:

```swift
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.needsDisplay = true }
```

- [ ] **Step 2: Add sprite rendering at the top of draw()**

At the beginning of `draw(_ dirtyRect:)`, before the existing gradient rendering, add:

```swift
// Try sprite-based title bar
let isActive = window?.isKeyWindow ?? true
if let titleSprite = WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive) {
    titleSprite.draw(in: bounds)

    // Draw title bar buttons from sprites
    let btnSize: CGFloat = 9
    let btnY = (bounds.height - btnSize) / 2
    let b = bounds

    // Close button
    let closeRect = NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize)
    if let closeSprite = WinampTheme.sprite(.titleBarCloseButton(pressed: false)) {
        closeSprite.draw(in: closeRect)
    }

    // Minimize button
    let minRect = NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize)
    if let minSprite = WinampTheme.sprite(.titleBarMinimizeButton(pressed: false)) {
        minSprite.draw(in: minRect)
    }

    // Shade button / Pin button area
    let shadeRect = NSRect(x: b.width - 33, y: btnY, width: btnSize, height: btnSize)
    if let shadeSprite = WinampTheme.sprite(.titleBarShadeButton(pressed: false)) {
        shadeSprite.draw(in: shadeRect)
    }

    return
}
// ... existing gradient code continues as fallback
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/Components/TitleBarView.swift
git commit -m "feat: add sprite rendering to TitleBarView"
```

---

### Task 20: Add sprite digits to SevenSegmentView

**Files:**
- Modify: `Wamp/UI/Components/SevenSegmentView.swift`

- [ ] **Step 1: Add skin observer and sprite digit rendering**

Add import and property:

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?
```

In init, add:

```swift
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.needsDisplay = true }
```

In the digit rendering method (around line 58, `drawDigit`), add sprite check at the top:

```swift
private func drawDigit(_ digit: Int, at rect: NSRect) {
    // Try sprite-based digit first
    if digit >= 0, digit <= 9,
       let sprite = WinampTheme.sprite(.digit(digit)) {
        sprite.draw(in: rect)
        return
    }
    // Existing seven-segment fallback below...
    guard digit >= 0, digit <= 9 else { return }
    // ... rest of existing code
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/Components/SevenSegmentView.swift
git commit -m "feat: add sprite digit rendering to SevenSegmentView"
```

---

### Task 21: Add skin background to MainPlayerView

**Files:**
- Modify: `Wamp/UI/MainPlayerView.swift`

- [ ] **Step 1: Add skin observer**

Add import and property:

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?
```

In `setupSubviews()` (line 63), add:

```swift
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.updateSkinBackground() }
```

- [ ] **Step 2: Add skin background method**

```swift
private func updateSkinBackground() {
    if let mainBg = WinampTheme.sprite(.mainBackground),
       let cgImage = mainBg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        layer?.contents = cgImage
        layer?.backgroundColor = nil
    } else {
        layer?.contents = nil
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
    }
    needsDisplay = true
}
```

Call this method also at the end of `setupSubviews()` for initial state.

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/MainPlayerView.swift
git commit -m "feat: add skin background sprite to MainPlayerView"
```

---

### Task 22: Add skin support to EqualizerView

**Files:**
- Modify: `Wamp/UI/EqualizerView.swift`

- [ ] **Step 1: Add skin observer and background**

Add import, property, and observer (same pattern as MainPlayerView):

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?

// In setupSubviews():
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.updateSkinBackground() }

private func updateSkinBackground() {
    if let eqBg = WinampTheme.sprite(.eqBackground),
       let cgImage = eqBg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        layer?.contents = cgImage
        layer?.backgroundColor = nil
    } else {
        layer?.contents = nil
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
    }
    needsDisplay = true
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/EqualizerView.swift
git commit -m "feat: add skin background to EqualizerView"
```

---

### Task 23: Add skin colors to PlaylistView

**Files:**
- Modify: `Wamp/UI/PlaylistView.swift`

- [ ] **Step 1: Add skin observer**

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?

// In setupSubviews():
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in
        self?.tableView.reloadData()
        self?.needsDisplay = true
    }
```

- [ ] **Step 2: Replace hardcoded colors in cell rendering**

In `tableView(_:viewFor:row:)` (lines 269-320), replace color references:

```swift
// Replace WinampTheme.white with:
let style = WinampTheme.provider.playlistStyle
let playingColor = style.current
let normalNumColor = style.normal  // was greenSecondary
let normalNameColor = style.normal  // was greenBright

// Replace WinampTheme.selectionBlue in WinampRowView.drawSelection:
style.selectedBG

// Replace NSColor.black in WinampRowView.drawBackground:
style.normalBG
```

Also update the playlist font:

```swift
// Replace WinampTheme.playlistFont with:
let fontName = WinampTheme.provider.playlistStyle.font
let font = NSFont(name: fontName, size: 8.5) ?? NSFont.systemFont(ofSize: 8.5)
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/PlaylistView.swift
git commit -m "feat: add skin colors and font to PlaylistView"
```

---

### Task 24: Add skin colors to SpectrumView

**Files:**
- Modify: `Wamp/UI/Components/SpectrumView.swift`

- [ ] **Step 1: Add skin observer and use viscolors**

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?

// In init:
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.needsDisplay = true }
```

In `draw(_ dirtyRect:)`, replace the hardcoded gradient colors (line 21):

```swift
// Replace:
// let gradient = NSGradient(starting: WinampTheme.spectrumBarBottom, ending: WinampTheme.spectrumBarTop)
// With viscolors-based coloring:
let viscolors = WinampTheme.provider.viscolors
// Use viscolors for bar gradient: colors 18-23 are white/gray (peaks), 2-17 are spectrum colors
let bottomColor = viscolors.count > 2 ? viscolors[2] : WinampTheme.spectrumBarBottom
let topColor = viscolors.count > 18 ? viscolors[18] : WinampTheme.spectrumBarTop
let gradient = NSGradient(starting: bottomColor, ending: topColor)
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/Components/SpectrumView.swift
git commit -m "feat: add skin viscolors to SpectrumView"
```

---

### Task 25: Add region mask to MainWindow

**Files:**
- Modify: `Wamp/UI/MainWindow.swift`

- [ ] **Step 1: Add applyRegionMask method**

Add this method to MainWindow:

```swift
func applyRegionMask() {
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

Add `import QuartzCore` at the top if not already present.

The `cgPath` property on NSBezierPath needs a helper. Add this extension (can be in the same file or in a shared location):

```swift
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/MainWindow.swift
git commit -m "feat: add region mask support to MainWindow"
```

---

### Task 26: Add skin observers to remaining views

**Files:**
- Modify: `Wamp/UI/Components/LCDDisplay.swift`
- Modify: `Wamp/UI/Components/EQResponseView.swift`

- [ ] **Step 1: Add skin observer to LCDDisplay**

```swift
import Combine
// ...
private var skinCancellable: AnyCancellable?

// In init:
skinCancellable = SkinManager.shared.$currentSkin
    .sink { [weak self] _ in self?.needsDisplay = true }
```

- [ ] **Step 2: Add skin observer to EQResponseView**

Same pattern as LCDDisplay.

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/Components/LCDDisplay.swift Wamp/UI/Components/EQResponseView.swift
git commit -m "feat: add skin observers to LCDDisplay and EQResponseView"
```

---

### Task 27: Add shuffle/repeat/EQ/playlist toggle button sprites in MainPlayerView

**Files:**
- Modify: `Wamp/UI/MainPlayerView.swift`

- [ ] **Step 1: Set spriteKeyProvider on toggle buttons**

In `setupSubviews()`, after the shuffle/repeat/EQ/playlist buttons are created, add:

```swift
shuffleButton.spriteKeyProvider = { pressed in
    .shuffleButton(active: self.shuffleButton.isActive, pressed: pressed)
}
repeatButton.spriteKeyProvider = { pressed in
    .repeatButton(active: self.repeatButton.isActive, pressed: pressed)
}
eqButton.spriteKeyProvider = { pressed in
    .eqButton(active: self.eqButton.isActive, pressed: pressed)
}
plButton.spriteKeyProvider = { pressed in
    .playlistButton(active: self.plButton.isActive, pressed: pressed)
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/MainPlayerView.swift
git commit -m "feat: wire shuffle/repeat/EQ/playlist buttons to skin sprites"
```

---

### Task 28: End-to-end smoke test

**Files:** None (manual testing)

- [ ] **Step 1: Download test skin**

```bash
# Download the classic Winamp 2.91 base skin from Webamp repo
curl -L -o /tmp/base-2.91.wsz "https://github.com/captbaritone/webamp/raw/master/packages/webamp/assets/skins/base-2.91.wsz"
```

- [ ] **Step 2: Build and run**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```

Open the app, go to View → Load Skin..., select `/tmp/base-2.91.wsz`.

- [ ] **Step 3: Visual verification checklist**

Verify each element renders from skin sprites:
- [ ] Main window background (main.bmp)
- [ ] Title bar (active/inactive states)
- [ ] Transport buttons (prev/play/pause/stop/next/eject — normal + pressed)
- [ ] Time display digits (numbers.bmp)
- [ ] Seek slider (background + thumb)
- [ ] Volume slider (28 background positions + thumb)
- [ ] Balance slider
- [ ] Shuffle/Repeat/EQ/Playlist toggle buttons
- [ ] Equalizer background
- [ ] EQ sliders
- [ ] Playlist text colors

- [ ] **Step 4: Test unload skin**

View → Unload Skin. Verify app returns to built-in programmatic rendering without artifacts.

- [ ] **Step 5: Test persistence**

Load a skin, quit app, relaunch. Verify skin is restored from saved path.

- [ ] **Step 6: Test error handling**

Try loading a non-skin ZIP file. Verify error alert appears and app stays on current skin.

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: smoke test fixes for skin rendering"
```
