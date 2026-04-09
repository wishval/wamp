# Wamp Skin Support — Design Spec

**Date:** 2026-04-09
**Scope:** Phase 1 MVP — Winamp 2.x classic skin (.wsz) support
**Approach:** Port from Webamp (MIT, github.com/captbaritone/webamp)
**External dependency:** ZipFoundation (pure Swift, SPM)

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| WinampTheme integration | Facade (variant A) — WinampTheme delegates to SkinProvider | Minimal view changes, single API surface |
| Error handling | main.bmp required, everything else optional with fallback | Matches real-world skins; original Winamp behavior |
| Skin preview | No preview — apply immediately on load | MVP simplicity; instant switch, easy rollback |
| Skin library | No library — Load Skin via NSOpenPanel, persist last path | MVP scope; library is Phase 1-Extended |
| File formats | .wsz and .zip only, no unpacked folders | All skins distributed as .wsz |

---

## 1. Data Model (SkinModel)

```swift
struct SkinModel {
    let images: [String: CGImage]           // sprite sheets, key = lowercase filename without ext
    let viscolors: [NSColor]                // 24 colors, merged with defaults
    let playlistStyle: PlaylistStyle        // merged with defaults, non-optional
    let regions: [String: [[CGPoint]]]      // section -> polygons, empty if no region.txt
    let genLetterWidths: [String: Int]      // empty if no gen.bmp
    let genTextSprites: [String: CGImage]   // empty if no gen.bmp
    let genExColors: GenExColors?           // 22 UI colors from genex.bmp, nullable
    let cursors: [String: Data]             // raw cursor data, empty if none (Phase 1-Extended)
}

struct PlaylistStyle {
    let normal: NSColor         // default: #00FF00
    let current: NSColor        // default: #FFFFFF
    let normalBG: NSColor       // default: #000000
    let selectedBG: NSColor     // default: #0000FF
    let font: String            // default: "Arial", non-optional

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
```

Default viscolors (24 RGB values from Webamp):
```
rgb(0,0,0), rgb(24,33,41), rgb(239,49,16), rgb(206,41,16),
rgb(214,90,0), rgb(214,102,0), rgb(214,115,0), rgb(198,123,8),
rgb(222,165,24), rgb(214,181,33), rgb(189,222,41), rgb(148,222,33),
rgb(41,206,16), rgb(50,190,16), rgb(57,181,16), rgb(49,156,8),
rgb(41,148,0), rgb(24,132,8), rgb(255,255,255), rgb(214,214,222),
rgb(181,189,189), rgb(160,170,175), rgb(148,156,165), rgb(150,150,150)
```

---

## 2. Sprite System

### SpriteSheet

```swift
enum SpriteSheet: String {
    case main, titlebar, cbuttons, numbers, numsEx
    case playpaus, monoster, posbar, volume, balance
    case eqmain, eqEx, pledit, shufrep, gen, text
}
```

### SpriteKey (MVP subset)

Transport buttons (cbuttons.bmp): previous/play/pause/stop/next/eject x pressed state
Numbers (numbers.bmp): digits 0-9, minus, no-minus, blank
Play status (playpaus.bmp): playing, paused, stopped, working, notWorking
Mono/Stereo (monoster.bmp): mono/stereo x active state
Title bar (titlebar.bmp): active/inactive background, close/minimize/shade buttons x pressed
Seek (posbar.bmp): background, thumb x pressed
Volume (volume.bmp): 28 background positions, thumb x pressed
Balance (balance.bmp): 28 background positions, thumb x pressed
Shuffle/Repeat (shufrep.bmp): shuffle/repeat/eq/playlist x active x pressed
EQ (eqmain.bmp): background, title bar, slider bg, slider thumb x 14 positions, on/auto/presets buttons, graph background, graph line colors, preamp line
Playlist (pledit.bmp): 9 frame tiles (corners + sides + title) x active, scroll handle, add/remove/select/misc sub-menu buttons, close/expand/collapse
Main (main.bmp): full window background 275x116

Each SpriteKey resolves to `(sheet: SpriteSheet, rect: CGRect)` via static mapping ported 1:1 from Webamp skinSprites.ts (~900 LOC constants).

### Sprite Slicing

Lazy: SkinModel stores full sprite sheets as CGImage. Individual sprites extracted via `CGImage.cropping(to:)` on first access, cached in NSCache keyed by SpriteKey.

### Volume/Balance: 28 background positions

volume.bmp and balance.bmp contain 28 pre-rendered background variants showing different fill levels. The slider selects background by `Int(normalizedValue * 27)` — no separate fill bar drawn on top.

### EQ slider thumb: 14 positions

eqmain.bmp contains 14 thumb variants. Selected by slider position index.

---

## 3. Parser

### SkinParser (orchestrator)

```swift
final class SkinParser {
    func parse(contentsOf url: URL) async throws -> SkinModel
}
```

- Reads ZIP data, extracts all entries via ZipExtractor
- Validates main.bmp exists and loads as CGImage (throws SkinParserError.missingRequiredFile if not)
- Loads all other resources in parallel via async let (images, viscolors, playlistStyle, regions, genLetterWidths, genTextSprites, genExColors, cursors)
- All optional resources return defaults or empty collections on failure

### Supporting Parsers

**ZipExtractor** (inside SkinParserUtils.swift):
- Wraps ZipFoundation
- Returns `[String: Data]` with lowercase keys, normalized path separators
- Case-insensitive lookup takes LAST matching file (matches Windows/Winamp behavior)

**CGImageLoader** (inside SkinParserUtils.swift):
- `NSImage(data:)` -> `CGImage` conversion
- Handles BMP and PNG
- 8-bit palette BMP fallback: deferred to Phase 1-Extended, use NSImage for MVP

**GenTextSprites parser** (inside SkinParserUtils.swift):
- Scans gen.bmp at Y=88 (selected) and Y=96 (normal)
- Detects letter boundaries by background color at x=0
- Returns letter widths and sliced letter sprites

**IniParser.swift** (~100 LOC):
- Port of parseIni() from Webamp utils.ts
- Handles sections [Section], key=value pairs, ; comments, BOM, \r\n
- Returns `[String: [String: String]]`, all keys lowercase

**ViscolorsParser.swift** (~60 LOC):
- Regex: `^\s*(\d+)\s*,?\s*(\d+)\s*,?\s*(\d+)`
- Merges parsed colors with 24 defaults

**PlaylistStyleParser.swift** (~80 LOC):
- Parses pledit.txt via IniParser, section [Text]
- Color normalization: add # if missing, limit to 7 chars
- Merges with PlaylistStyle.default

**RegionParser.swift** (~150 LOC):
- Port of regionParser.ts
- Parses numpoints (comma-separated counts) + pointlist (sequential coordinates)
- Distributes points across polygons per numpoints
- Filters polygons with <3 points
- Returns `[String: [[CGPoint]]]`

**GenExColorsParser.swift** (~80 LOC):
- Loads genex.bmp, samples 22 pixels at row Y=0, X coordinates: 48,50,52,...,90
- Returns GenExColors or nil

---

## 4. SkinProvider + WinampTheme Refactor

### SkinProvider protocol

```swift
protocol SkinProvider: AnyObject {
    func sprite(_ key: SpriteKey) -> NSImage?
    var frameBackground: NSColor { get }
    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var genExColors: GenExColors? { get }
    var mainWindowRegion: NSBezierPath? { get }
    var equalizerWindowRegion: NSBezierPath? { get }
}
```

### BuiltInSkin

- Returns current hardcoded WinampTheme values for frameBackground
- sprite() always returns nil (triggers programmatic fallback in views)
- viscolors: default 24 colors
- playlistStyle: PlaylistStyle.default
- genExColors: nil
- regions: nil

### WinampClassicSkin

- Wraps SkinModel
- sprite() slices from CGImage sheets, caches in NSCache
- Colors from SkinModel fields
- Regions converted to NSBezierPath with Y-flip (Winamp Y-down -> macOS Y-up)

### WinampTheme refactor

enum -> class with:
- `static var provider: SkinProvider = BuiltInSkin()`
- All existing ~47 color properties remain as `static let` (used only when sprite() returns nil)
- New computed properties delegate to provider: `static var frameBackground: NSColor { provider.frameBackground }`
- New method: `static func sprite(_ key: SpriteKey) -> NSImage? { provider.sprite(key) }`
- Dimensions and scale remain unchanged as static let

### SkinManager

```swift
final class SkinManager: ObservableObject {
    static let shared = SkinManager()
    @Published private(set) var currentSkin: SkinProvider = BuiltInSkin()

    func loadSkin(from url: URL) async throws {
        let model = try await SkinParser().parse(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        await MainActor.run {
            self.currentSkin = skin
            WinampTheme.provider = skin
        }
    }

    func unloadSkin() {
        currentSkin = BuiltInSkin()
        WinampTheme.provider = currentSkin
    }
}
```

---

## 5. View Integration

### Pattern: sprite lookup with programmatic fallback

Every view that renders skinnable content follows:

```swift
// In draw():
if let image = WinampTheme.sprite(.someKey) {
    image.draw(in: bounds)
} else {
    // existing programmatic render code, unchanged
}
```

### Skin change reactivity

Each skinnable view subscribes to SkinManager:

```swift
private var skinCancellable: AnyCancellable?

func setupSkinObserver() {
    skinCancellable = SkinManager.shared.$currentSkin
        .sink { [weak self] _ in self?.needsDisplay = true }
}
```

Called in init/setup of each view (~12 classes, 3 lines each).

### Per-component details

**WinampButton:**
- New property: `var spriteKeyProvider: ((Bool) -> SpriteKey)?` (Bool = isPressed)
- In draw(): if spriteKeyProvider set and sprite exists, draw sprite and return; else existing code

**WinampSlider:**
- Seek: sprite(.seekBackground) + sprite(.seekThumb(pressed:))
- Volume: sprite(.volumeBackground(position: Int(value * 27))) — 28 pre-rendered backgrounds, no fill bar
- Balance: same as volume, 28 positions
- EQ band: sprite(.eqSliderBackground) + sprite(.eqSliderThumb(position:)) — 14 thumb variants
- Fallback: existing gradient rendering

**TransportBar:**
- Sets spriteKeyProvider on each button at creation time
- Example: `prevButton.spriteKeyProvider = { pressed in .previous(pressed: pressed) }`

**TitleBarView:**
- draw() checks sprite(.titleBarActive) / sprite(.titleBarInactive) for background
- Inline button rendering checks sprite(.titleBarButtonClose(pressed:)) etc.
- Fallback: existing gradient + stripe rendering

**SevenSegmentView:**
- draw() checks sprite(.digit(N)) for each digit
- If sprite exists: blit 9x13 image scaled to digit rect
- Fallback: existing seven-segment rendering

**MainPlayerView:**
- Background: set layer?.contents = mainBackground CGImage (or keep layer?.backgroundColor for fallback)
- Subviews render on top (layer-backed view, correct z-order confirmed)

**EqualizerView:**
- Background: sprite(.eqBackground)
- EQ graph: sprite(.eqGraphBackground) + sprite(.eqGraphLineColors)
- Buttons: sprite(.eqOnButton(active:pressed:)) etc.

**PlaylistView:**
- Frame tiles from pledit.bmp: top-left corner, title bar, top-right corner (x active/inactive = 8 sprites), left tile, right tile, bottom-left corner, bottom tile, bottom-right corner, scroll handle (x pressed = 2)
- Text colors from WinampTheme.provider.playlistStyle (normal, current, normalBG, selectedBG)
- Font from playlistStyle.font
- Cell rendering stays NSTextField-based, only colors change
- Playlist action buttons (add/rem/sel/misc/list) from pledit.bmp sub-menu sprites

**SpectrumView:**
- Bar colors from WinampTheme.provider.viscolors (24 colors mapped to bar heights)

**LCDDisplay:**
- Text color change only for MVP
- Full text.bmp sprite rendering: Phase 1-Extended

---

## 6. Region Mask (Non-rectangular Windows)

### Application

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

### Coordinate system

- Mask uses bounds coordinates (logical 275px), not frame (scaled)
- Y-flip required: Winamp Y=0 is top, macOS Y=0 is bottom
- Conversion: `y_macos = windowHeight - y_winamp`
- Y-flip applied in WinampClassicSkin when converting regions to NSBezierPath

### Hit-testing

Automatic in AppKit — clicks on masked-out areas pass through. No extra code needed.

### Scope

MVP: [Normal] section only for main window and equalizer.
Phase 1-Extended: [WindowShade], [EqualizerWS] sections.

---

## 7. UI & Persistence

### Menu

Added to View menu in setupMainMenu() after existing items:
- Separator
- "Load Skin..." (Cmd+Shift+S) -> NSOpenPanel with .wsz/.zip filter
- "Unload Skin" -> returns to BuiltInSkin

### Error handling

- Parse failure: NSAlert with error description, stay on current skin
- main.bmp missing: SkinParserError.missingRequiredFile, shown in alert

### Persistence

AppState gets new field:
```swift
var skinPath: String?  // nil = built-in
```

Saved via existing StateManager save flow. Restored at app launch BEFORE window creation to avoid flicker:

```
applicationDidFinishLaunching:
1. loadAppState()
2. loadEQState()
3. Load skin synchronously if skinPath exists and file present
4. Create MainWindow
5. bindToModels()
```

If saved skin file missing/moved: silently fallback to built-in.

---

## 8. File Structure

### New files (Wamp/Skinning/)

| File | ~LOC | Ported from |
|------|------|-------------|
| SkinModel.swift | 100 | types.ts |
| SkinSprites.swift | 900 | skinSprites.ts |
| SkinParser.swift | 250 | skinParser.js |
| SkinParserUtils.swift | 550 | skinParserUtils.ts |
| IniParser.swift | 100 | utils.ts |
| ViscolorsParser.swift | 60 | utils.ts |
| PlaylistStyleParser.swift | 80 | skinParserUtils.ts |
| RegionParser.swift | 150 | regionParser.ts |
| GenExColorsParser.swift | 80 | skinParserUtils.ts |
| SkinProvider.swift | 50 | — |
| WinampClassicSkin.swift | 150 | — |
| SkinManager.swift | 60 | — |
| **Total** | **~2530** | |

### Modified files (15)

WinampTheme.swift, WinampButton.swift, WinampSlider.swift, TitleBarView.swift, SevenSegmentView.swift, MainPlayerView.swift, EqualizerView.swift, PlaylistView.swift, SpectrumView.swift, TransportBar.swift, LCDDisplay.swift, EQResponseView.swift, MainWindow.swift, AppDelegate.swift, StateManager.swift

### External dependency

ZipFoundation via Swift Package Manager (pure Swift, MIT, zero C dependencies).

---

## 9. MVP Scope

### Included

- Main window: background, titlebar, transport buttons, number digits, play status, mono/stereo, seek/volume/balance sliders
- Equalizer: background, titlebar, 10 band sliders + preamp, on/auto/presets buttons, graph background
- Playlist: frame tiles (9 sprites), text colors from pledit.txt, font
- Visualizer colors from viscolor.txt
- Non-rectangular windows via region.txt [Normal] section
- Menu: Load Skin / Unload Skin
- Persistence of last skin path
- Fallback to built-in render when skin not loaded or sprite missing

### Excluded (Phase 1-Extended)

- WindowShade mode
- 8-bit indexed palette BMP decoder (use NSImage, add custom decoder only if real skins break)
- Custom cursors (.cur files)
- Text sprite rendering from text.bmp (LCD scrolling text)
- GEN window tiles
- Freeform polygon hit-testing
- Skin library/browser
- .wal (Winamp Modern) skins

---

## 10. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| 8-bit palette BMP colors wrong via NSImage | Some skins look wrong | Defer custom decoder; add if >30% test skins affected |
| region.txt edge cases | Window mask wrong | Port Webamp logic exactly; test with diverse skins |
| Sprite coordinate mismatch | UI elements misaligned | Migration tests with golden JSON from Webamp |
| ZIP case sensitivity | Files not found | Last-match strategy from Webamp |
| Performance of lazy sprite slicing | Lag on first render | NSCache ensures one-time cost per sprite |
