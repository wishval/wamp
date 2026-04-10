# Wamp Skin Support — Design Spec

**Date:** 2026-04-10
**Scope:** Phase 1 MVP — Winamp 2.x classic skin (`.wsz`) support
**Source of truth:** Webamp (https://github.com/captbaritone/webamp, MIT)
**External dependency:** ZIPFoundation (pure Swift, SPM)

This is the second design pass on this feature. The first attempt (branch `feature/skin-support`) hit two failure modes documented in §12: (a) `layer.contents`-based skin backgrounds caused unload race conditions and required CATransaction workarounds, and (b) the work drifted into a "pixel-perfect Winamp 2.x rewrite" that moved Wamp's layout to match classic dimensions, which the user rejected. This spec replaces both approaches.

---

## 1. Goal

Apply a Winamp 2.x classic skin to Wamp such that **every visible UI element renders from the skin's sprites or hides itself**. When a skin is loaded there is **zero programmatic fallback rendering** in user-facing surfaces. Wamp's layout, sizes, and control set stay where they are — we do not move buttons or add new controls to mimic classic Winamp.

The four skins shipped in `skins/` are the acceptance set, each chosen to exercise a different parser corner case:

| Skin | What it tests |
|---|---|
| `base-2.91.wsz` | Full classic skin: all BMPs + `region.txt` + `genex.bmp`. Baseline for "everything renders" |
| `OS8 AMP - Aquamarine.wsz` | Minimal skin nested in a subdirectory; **no `numbers.bmp` (has `nums_ex.bmp`)**; no `gen.bmp`, `genex.bmp`, `region.txt`, `viscolor.txt`. Tests nums_ex unification and default fallbacks |
| `Blue Plasma.wsz` | Mixed-case filenames (`Cbuttons.bmp`, `Numbers.bmp`, `Eqmain.bmp`, ...); contains non-image junk (`.psd` files, `Readme.txt`); has `Copy of Main.bmp` / `Eqmain copy.bmp` duplicates. Tests case-insensitive lookup and "ignore non-image files without crashing" |
| `Radar_Amp.wsz` | Mixed case across the board (`main.bmp` lower, `Numbers.bmp` mixed, `PLEDIT.TXT` and `VISCOLOR.TXT` upper); contains `info.txt`. Tests case-insensitive text-file lookup |

If all four render with no NSTextField labels showing through, no programmatic gradients in slider/button areas, and no system-font text overlays, the MVP is done.

---

## 2. Architecture

### 2.1 Three layers

1. **Parser layer** (`Wamp/Skinning/`): pure-Swift `.wsz` reader. Produces a `SkinModel` value.
2. **Provider layer**: `SkinProvider` protocol with two implementations — `BuiltInSkin` (no skin loaded, sprite() returns nil) and `WinampClassicSkin` (wraps `SkinModel`, slices sprites lazily, caches results).
3. **View layer**: existing Wamp views override `draw(_:)`. At the top of each `draw()` they branch:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned(dirtyRect)
    } else {
        drawBuiltIn(dirtyRect)
    }
}
```

`drawBuiltIn` is the existing rendering code (extracted into a method, unchanged). `drawSkinned` is the new code that blits sprites and text.bmp glyphs. The two paths never mix at runtime — exactly one runs per draw cycle.

### 2.2 Why `draw(_:)` and not `layer.contents`

The first attempt set `layer?.contents = mainBackgroundCGImage` on `MainPlayerView`. This caused three classes of problem:
- On unload, clearing `layer.contents = nil` left a flicker; needed `CATransaction.disableActions` workarounds.
- Subviews drawn on top of the layer-contents background did not interact correctly with `needsDisplay` invalidation when the skin changed.
- Drawing additional sprites (text.bmp glyphs, monoster sprites) on top required overriding `draw()` anyway, and `draw()` is not called on a view whose `layer.contents` is set externally.

`draw(_:)` based rendering avoids all three. The view stays layer-backed (`wantsLayer = true` for compositing), but we never poke `layer.contents` directly. AppKit caches the result of `draw()` in the layer, and a single `needsDisplay = true` invalidates and re-runs the path cleanly.

### 2.3 Skin lifecycle: atomic transition

The first attempt had a race: `@Published currentSkin` fired before `WinampTheme.provider` was updated, so observers briefly saw a state where `currentSkin = newSkin` but `WinampTheme.sprite(...)` still asked the old provider. Fix: one private method on `SkinManager` that updates both atomically before notifying:

```swift
private func transition(to newSkin: SkinProvider) {
    WinampTheme.provider = newSkin   // 1. update facade FIRST
    self.currentSkin = newSkin       // 2. fire @Published — observers see consistent state
}
```

Both `loadSkin`, `loadSkinSync`, and `unloadSkin` go through `transition()`. No other code touches `WinampTheme.provider`.

---

## 3. Data Model

```swift
struct SkinModel {
    let images: [String: CGImage]      // sprite sheets keyed by lowercase basename
    let viscolors: [NSColor]           // 24 colors (defaults if viscolor.txt missing)
    let playlistStyle: PlaylistStyle   // colors+font (defaults if pledit.txt missing)
    let region: [CGPoint]?             // [Normal] polygon for main window, nil if absent
    let eqGraphLineColors: [NSColor]   // 19 colors sampled from eqmain.bmp at y=313
    let eqPreampLineColor: NSColor     // 1 color from eqmain.bmp
}

struct PlaylistStyle {
    let normal: NSColor       // default #00FF00
    let current: NSColor      // default #FFFFFF
    let normalBG: NSColor     // default #000000
    let selectedBG: NSColor   // default #0000FF
    let font: String          // default "Arial"
}
```

**Removed compared to first attempt:**
- `genLetterWidths`, `genTextSprites` — Wamp has no GEN window, no consumer.
- `genExColors: GenExColors?` (22 fields) — used only for playlist scrollbar/header tinting in Webamp; Wamp's NSScrollView is system-styled and we accept default coloring.
- `cursors: [String: Data]` — Phase 1-Extended.
- Separate `regions: [String: [[CGPoint]]]` dictionary — only `[Normal]` for the main window is used; stored as a single `[CGPoint]?`.
- `equalizerWindowRegion` — EQ window is rectangular in classic Winamp.

---

## 4. Sprite Catalog

The full Webamp `skinSprites.ts` defines ~50 named sheets and ~150 sprite rectangles. Wamp uses a strict subset. Anything not in this list is not parsed.

### 4.1 Sheets stored in `SkinModel.images`

| Key | File(s) | Used by |
|---|---|---|
| `main` | `main.bmp` (required) | `MainPlayerView` background |
| `titlebar` | `titlebar.bmp` | `TitleBarView` for EQ/Playlist windows |
| `cbuttons` | `cbuttons.bmp` | `TransportBar` 6 buttons |
| `numbers` | `numbers.bmp` OR `nums_ex.bmp` (last write wins) | `SevenSegmentView` time digits |
| `playpaus` | `playpaus.bmp` | play/pause/stop/work indicators (deferred — see §6) |
| `monoster` | `monoster.bmp` | mono/stereo word sprites |
| `posbar` | `posbar.bmp` | seek slider |
| `volume` | `volume.bmp` | volume slider (28 backgrounds + thumb) |
| `balance` | `balance.bmp` | balance slider (28 backgrounds + thumb) |
| `shufrep` | `shufrep.bmp` | shuffle, repeat, EQ, PL toggle buttons |
| `eqmain` | `eqmain.bmp` | `EqualizerView` background, sliders, on/auto/presets |
| `pledit` | `pledit.bmp` | `PlaylistView` frame tiles, scroll handle, action buttons |
| `text` | `text.bmp` | `LCDDisplay`, bitrate, sample rate, kbps, khz, playlist info |

### 4.2 SpriteKey enum

```swift
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
    case eqSliderThumb(position: Int, pressed: Bool)  // position 0–13 picks one of 14 thumb variants
    case eqOnButton(active: Bool, pressed: Bool)
    case eqAutoButton(active: Bool, pressed: Bool)
    case eqPresetsButton(pressed: Bool)
    case eqGraphBackground

    // pledit (only the 9 frame tiles + scroll handle + the 3 buttons we use)
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
    case playlistAddFile(pressed: Bool)        // ADD button → "add file" sub-button
    case playlistRemoveSelected(pressed: Bool) // REM button → "rem sel" sub-button
    case playlistRemoveAll(pressed: Bool)      // REM ALL button → "rem all" sub-button

    // text.bmp — caller blits via TextSpriteRenderer (no per-glyph SpriteKey)
}
```

Coordinates for each case are ported 1:1 from `packages/webamp/js/skinSprites.ts`. The mapping function is `SpriteCoordinates.resolve(_ key: SpriteKey) -> (sheet: String, rect: CGRect)`.

### 4.3 numbers / nums_ex unification

Webamp handles this via CSS cascade: both `DIGIT_N` (from `numbers.bmp`) and `DIGIT_N_EX` (from `nums_ex.bmp`) generate rules for the same `.digit-N` class, and whichever was loaded wins. Swift equivalent in `SkinParserUtils.loadAllImages`:

```swift
if let img = loadImage("numbers.bmp", from: entries) { images["numbers"] = img }
if let img = loadImage("nums_ex.bmp", from: entries) { images["numbers"] = img } // overwrites
```

Both sheets have 9×13 digits at x=0,9,18,...,81 y=0. SpriteCoordinates uses that fixed layout for `.digit(N)` regardless of which file populated the key.

### 4.4 19 EQ graph line colors

The first attempt referenced `.eqGraphLineColors` as a sprite rect but never wired it. Webamp samples 19 specific pixels from `eqmain.bmp` at y=313 (preamp line at y=314) into a `[NSColor]` of 19 entries. These colors map to vertical positions on `EQResponseView`'s 19-pixel-tall response curve (one color per pixel row, top = +12dB, bottom = -12dB). Stored in `SkinModel.eqGraphLineColors`. Used in `EQResponseView.drawSkinned`.

---

## 5. Parser

Single synchronous parser. Async wrapper exists only to keep the load call off the main thread for runtime loads (startup load runs sync to avoid window flicker).

```swift
final class SkinParser {
    func parseSync(contentsOf url: URL) throws -> SkinModel
    func parse(contentsOf url: URL) async throws -> SkinModel  // wraps parseSync in Task.detached
}
```

### Parse pipeline

1. `Data(contentsOf: url)` → ZIP bytes
2. `ZipFoundation.Archive` → `[String: Data]` keyed by lowercased basename, last-write-wins
3. Required: `main.bmp` → `CGImage`. Throws `SkinParserError.missingRequiredFile("main.bmp")` if absent.
4. Optional sheets: iterate the table from §4.1, load via `NSImage(data:).cgImage(...)`. nums_ex unification per §4.3.
5. `viscolor.txt` (if present) → `ViscolorsParser.parse` → 24 colors. Else default 24.
6. `pledit.txt` (if present) → `IniParser.parse → PlaylistStyleParser.parse` → `PlaylistStyle`. Else default.
7. `region.txt` (if present) → `IniParser.parse → RegionParser.parse` → `[CGPoint]?` for `[Normal]` only. Y-flipped to macOS coordinates.
8. `eqmain` image (if loaded) → sample 19 pixels at y=313 + 1 pixel at y=314 → `[NSColor]` and a single `NSColor`.

All optional resources fall back to documented Winamp defaults during parse. **Defaults are not "fallback rendering"** — they are the correct value to use when the skin omits the file. The phrase "no programmatic fallback" applies only to the view layer (§7).

### Supporting parsers

| File | Purpose | Approx LOC |
|---|---|---|
| `IniParser.swift` | INI text → `[section: [key: value]]`, lowercase, handles BOM/CRLF/comments | 70 |
| `ViscolorsParser.swift` | viscolor.txt → 24 NSColors with regex `^\s*(\d+)\s*,?\s*(\d+)\s*,?\s*(\d+)` | 50 |
| `PlaylistStyleParser.swift` | pledit.txt `[text]` section → PlaylistStyle (hex color normalization) | 80 |
| `RegionParser.swift` | region.txt `[Normal]` section → CGPoint polygon, Y-flip | 80 |
| `EqGraphColorsParser.swift` | sample 19+1 pixels from eqmain CGImage | 50 |
| `SkinParserUtils.swift` | ZIP extraction, image loading, nums_ex unification | 120 |

---

## 6. SkinProvider

```swift
protocol SkinProvider: AnyObject {
    func sprite(_ key: SpriteKey) -> NSImage?
    var textSheet: NSImage? { get }       // text.bmp as a whole, for TextSpriteRenderer
    var viscolors: [NSColor] { get }
    var playlistStyle: PlaylistStyle { get }
    var eqGraphLineColors: [NSColor] { get }
    var eqPreampLineColor: NSColor { get }
    var mainWindowRegion: NSBezierPath? { get }
}
```

### BuiltInSkin

Returns nil/defaults for everything sprite-related:

```swift
final class BuiltInSkin: SkinProvider {
    func sprite(_ key: SpriteKey) -> NSImage? { nil }
    var textSheet: NSImage? { nil }
    var viscolors: [NSColor] { Self.defaultViscolors }
    var playlistStyle: PlaylistStyle { .default }
    var eqGraphLineColors: [NSColor] { [] }
    var eqPreampLineColor: NSColor { .green }
    var mainWindowRegion: NSBezierPath? { nil }
}
```

When `BuiltInSkin` is the active provider, `WinampTheme.skinIsActive` is `false` and views run their `drawBuiltIn` path — the existing programmatic rendering. Nothing new happens at runtime; this is the current Wamp app exactly.

### WinampClassicSkin

Wraps a parsed `SkinModel`. `sprite(_:)` does:

```swift
let info = SpriteCoordinates.resolve(key)         // (sheetName, rect)
guard let sheet = model.images[info.sheetName] else { return nil }
let cacheKey = "\(key)" as NSString
if let cached = cache.object(forKey: cacheKey) { return cached }
guard let cropped = sheet.cropping(to: info.rect) else { return nil }
let image = NSImage(cgImage: cropped, size: info.rect.size)
cache.setObject(image, forKey: cacheKey)
return image
```

`cache` is an `NSCache<NSString, NSImage>`. Lazy slicing — sheets stay as `CGImage`, individual sprites materialized on first access.

### Note on play indicator status sprites

`playpaus.bmp` is parsed and stored, but **the MVP does not wire its rendering**. Wamp's `MainPlayerView` currently shows a small `playIndicator: NSView` that's not visually distinct from blank space and isn't part of the user-visible critical path. We hide it when skinned (§7) and defer wiring `.statusPlaying/.statusPaused/.statusStopped` to a Phase 1-Extended task. This keeps the MVP scope tight.

---

## 7. View Integration

### 7.1 Pattern

Every skinnable view has the structure:

```swift
private var skinObserver: AnyCancellable?

override init(frame: NSRect) {
    super.init(frame: frame)
    setup()
    skinObserver = SkinManager.shared.$currentSkin
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.applySkinVisibility()
            self?.needsDisplay = true
            self?.needsLayout = true   // some views need to relayout when sizes change
        }
    applySkinVisibility()
}

override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    if WinampTheme.skinIsActive {
        drawSkinned(dirtyRect)
    } else {
        drawBuiltIn(dirtyRect)
    }
}

private func drawBuiltIn(_ dirtyRect: NSRect) {
    // existing rendering code, moved into this method unchanged
}

private func drawSkinned(_ dirtyRect: NSRect) {
    // new sprite-blitting code
}

private func applySkinVisibility() {
    // toggle isHidden on the NSTextField/NSView children listed in §8
}
```

### 7.2 Per-view summary

| View | Sprites used | drawSkinned essence |
|---|---|---|
| `MainPlayerView` | `.mainBackground`, monoster, text.bmp | Blit main.bmp scaled to bounds; on top, blit mono/stereo at fixed coords; render bitrate/sample/kbps/khz via TextSpriteRenderer at fixed coords |
| `TitleBarView` (in EQ + Playlist windows) | `.titleBarActive/Inactive`, `.titleBarCloseButton`, `.titleBarShadeButton` | Blit titlebar bg; blit close button. Title text NOT drawn (baked in sprite) |
| `SevenSegmentView` | `.digit(N)` × N | Blit each digit sprite at its position, scaled to digit cell size |
| `LCDDisplay` | text.bmp via `TextSpriteRenderer` | Render scrolling track text using text.bmp glyphs |
| `TransportBar` | none (delegates to children) | Each `WinampButton` self-renders sprite via `spriteKeyProvider` |
| `WinampButton` | varies via `spriteKeyProvider` closure | If closure set and sprite exists, blit sprite for current `(active, pressed)`; else current programmatic path |
| `WinampSlider` (seek/volume/balance/eqBand) | `.seekBackground`/`.volumeBackground(p)`/`.balanceBackground(p)`/`.eqSliderBackground` + thumb | Blit background then thumb. Volume/balance use 28 prerendered backgrounds. EQ thumb has 14 positional variants |
| `EqualizerView` | `.eqBackground`, `.eqOnButton`, `.eqAutoButton`, `.eqPresetsButton` | Blit eqmain bg covering entire view bounds; the freq/dB/PRE/dB labels are baked into the sprite. ON/AUTO/PRESETS sprites blitted at fixed coords matching Wamp's existing button frames |
| `EQResponseView` | `eqGraphLineColors` array | Draw response curve using 1 color per pixel row from the 19-color array; bg from `.eqGraphBackground` |
| `PlaylistView` | 9 frame tiles, scroll handle, ADD/REM/REM ALL sub-buttons | Blit 9 frame tiles at corners and as repeated tile rows for sides; rename CLR → REM ALL; sub-buttons drawn in a tight horizontal row matching pledit submenu layout |
| `SpectrumView` | none (uses `viscolors` array) | Reads bar colors from `WinampTheme.provider.viscolors[2..17]`, peak from `[18]` |

### 7.3 Coordinate system

`MainPlayerView` and `EqualizerView` are 275px wide in logical coordinates (matching `WinampTheme.windowWidth`). Webamp's main.bmp is also 275×116. Wamp's `MainPlayerView` is taller (`mainPlayerHeight = 126`) to accommodate the title bar above the 116px Winamp area.

**Sprite drawing uses logical coordinates.** Wamp's `WinampTheme.scale = 1.3` is applied at the window level (the whole window is scaled), not inside view drawing. Inside `MainPlayerView.draw()`, `bounds.width` is 275 and `bounds.height` is 126 — sprites are drawn in this space directly. main.bmp is blitted to `NSRect(x: 0, y: 0, width: 275, height: 116)` at the bottom of the view, leaving the existing `TitleBarView` (16px) above untouched.

For child views (transport bar, sliders, labels), each has its own `bounds` matching the rect where it sits. Sprites blit at `bounds` directly. No scale arithmetic inside `drawSkinned`.

### 7.4 What about the title bar of MainPlayerView?

Wamp's `MainPlayerView` has its own `TitleBarView` instance at the top showing "WAMP". Classic Winamp's main window does **not** have a separate title bar — the title strip is baked into `main.bmp` rows 0–14, including the "WINAMP" text and the close/minimize/options buttons drawn as pixels. Two options:

- **A.** Hide `MainPlayerView.titleBar` entirely when skinned, let main.bmp's top 14 rows show through. Lose the macOS-style click handlers for close/minimize.
- **B.** Keep `MainPlayerView.titleBar` visible, draw `.titleBarActive` sprite over its bounds, but lose main.bmp's top strip (covered by titleBar's frame).

**Decision: A.** Hide `titleBar` when skinned. Add invisible `NSView` click hit-zones at the locations where main.bmp paints the close/minimize buttons (top-right corner) so user can still close/minimize the window. The hit zones are wired to the same callbacks `titleBar.onClose/onMinimize` previously used.

For `EqualizerView` and `PlaylistView` the title bars stay visible and use `.titleBarActive` sprite (those are dedicated title bars matching classic Winamp's EQ/Playlist windows).

---

## 8. Hide-when-skinned controls

When `WinampTheme.skinIsActive == true`, the following views/labels become `isHidden = true`. When the user unloads the skin, they reappear.

| Container | Control(s) | Why hidden | Replacement |
|---|---|---|---|
| `MainPlayerView` | `titleBar` | Title strip is baked into main.bmp rows 0–14 | main.bmp top rows visible; invisible click hit-zones for close/minimize |
| `MainPlayerView` | `leftPanel`, `rightPanel` (black NSViews) | Whole left/right panel area is part of main.bmp | main.bmp visible |
| `MainPlayerView` | `bitrateLabel`, `sampleRateLabel`, `bitrateUnitLabel` ("kbps"), `sampleRateUnitLabel` ("khz") | Original Winamp uses text.bmp glyphs at fixed positions | `TextSpriteRenderer` blits in `drawSkinned` at the fixed Webamp coords |
| `MainPlayerView` | `monoLabel`, `stereoLabel` | `monoster.bmp` contains pre-rendered "mono"/"stereo" word sprites | `.mono(active:)` and `.stereo(active:)` blitted at fixed coords |
| `MainPlayerView` | `playIndicator` | Currently a placeholder NSView; play status sprites deferred to Phase 1-Extended | nothing in MVP |
| `EqualizerView` | All 10 `bandLabels` (70/180/.../16K) | Frequency labels are baked into `eqmain.bmp` | eqmain.bmp visible |
| `EqualizerView` | dB labels (tagged 200/201/202: +12, 0, -12) | Baked into eqmain.bmp | eqmain.bmp visible |
| `EqualizerView` | PRE label (tag 210), dB label (tag 211) | Baked into eqmain.bmp | eqmain.bmp visible |
| `PlaylistView` | `titleBar` (when not specifically used as the playlist title sprite) | Title bar sprite from `pledit.bmp` covers it | pledit title sprite blitted in `drawSkinned` |
| `PlaylistView` | `infoLabel` (track count/duration) | Original Winamp renders via text.bmp at the bottom of the playlist frame | `TextSpriteRenderer` blits in `drawSkinned` |

The hide/show toggle happens in each view's `applySkinVisibility()` method, called from the SkinManager observer sink.

### `searchField` exception

`PlaylistView.searchField` has no Winamp 2.x equivalent. The user explicitly asked to keep it visible for now and revisit later. **MVP decision: searchField stays visible even with a skin loaded.** This is the only acknowledged exception to the zero-fallback rule. The decision is documented here and revisited after MVP.

---

## 9. Permanent UI changes

These changes apply to Wamp **regardless** of skin state because the affected controls have no classic Winamp equivalent. They are not part of the skin system per se — the skin work is the trigger to make them.

### 9.1 Pin button removed from `TitleBarView`

Classic Winamp 2.x has no "always on top" button in its title bar. The first attempt left the pin button in place and tried to draw a sprite over it — there is no such sprite. We remove the pin button entirely and move "always on top" to the View menu as a checkable item.

**Files affected:** `TitleBarView.swift`, `MainPlayerView.swift` (which wires `titleBar.onTogglePin`), `AppDelegate.swift` (adds View menu item), `MainWindow.swift` if needed.

### 9.2 CLR button → REM ALL

Wamp's `PlaylistView` currently has three buttons: ADD, REM, CLR. Classic Winamp's playlist editor has two visible buttons (ADD, REM) each with submenus. The closest sprite for "clear playlist" is the **REM ALL** sub-button inside REM's submenu region of `pledit.bmp`. We rename `clrButton` → `remAllButton`, change the title from "CLR" to "REM ALL", and map it to the REM ALL sub-button sprite. Behavior is unchanged (still clears the playlist). Visible label changes from "CLR" to "REM ALL" even in built-in mode.

**Files affected:** `PlaylistView.swift`.

---

## 10. Persistence

Add one field to `AppState`:

```swift
var skinPath: String?  // nil = built-in
```

Saved via the existing `StateManager.saveWindowState` flow. On launch, after `loadAppState()` and before `MainWindow` creation, if `skinPath` is non-nil and the file exists, call `SkinManager.shared.loadSkinSync(from:)`. If the file is missing or parse fails, silently fall back to built-in (no error popup at launch). Window region mask is applied after `MainWindow` creation finishes.

Runtime load (via menu) uses async `loadSkin`, shows an `NSAlert` on failure, and stays on the previous skin if parsing throws.

---

## 11. Menu

Two items added to the existing View menu in `AppDelegate.setupMainMenu` after the existing "Show Player/EQ/Playlist" entries:

- Separator
- `Always on Top` — checkable, toggles `mainWindow.alwaysOnTop`. Default keyboard shortcut: ⌘⇧T. Persists via existing `AppState.alwaysOnTop`.
- Separator
- `Load Skin...` — opens `NSOpenPanel` filtered to `.wsz`/`.zip`. ⌘⇧S.
- `Unload Skin` — restores `BuiltInSkin`, clears `skinPath`.

The "Always on Top" item is added by this work because §9.1 removes the pin button which previously controlled it.

---

## 12. Known pitfalls (lessons from `feature/skin-support`)

The first attempt left these landmines. Each is addressed in this design:

1. **Provider/observer race.** `@Published currentSkin` fired before `WinampTheme.provider` was updated, so observers briefly saw inconsistent state. **Fix:** §2.3 atomic `transition()` method, provider updated first.
2. **`layer.contents` flicker on unload.** Setting `layer?.contents = nil` left frames of the old image until next display cycle. CATransaction workarounds were brittle. **Fix:** §2.2 — never use `layer.contents`. All skin rendering happens inside `draw(_:)`.
3. **Pixel-perfect rewrite drift.** The first attempt expanded scope into rewriting `MainPlayerView`/`EqualizerView`/`PlaylistView` with classic Winamp dimensions, adding `ClutterBarView`/`StatusIndicatorView`/`WorkIndicatorView`, and changing scale to 1.0/2.0. **Decision: do not.** This work touches existing views minimally — it adds `drawSkinned` methods, hides labels, and changes nothing about layout, sizes, or the control set.
4. **Sprite/NSTextField double-draw.** When the first attempt set `layer.contents = main_bmp`, the NSTextField labels (bitrate, mono/stereo, EQ freq labels) still rendered on top in their system fonts, producing a double-rendered ugly result. **Fix:** §8 hide-when-skinned table, applied unconditionally.

---

## 13. Acceptance

MVP is complete when a build passes manual verification with **all four** skins in `skins/`. The detailed checklist is in plan Task 18. Summary:

**`base-2.91.wsz`:**
- main.bmp visible as background, including title strip with "WINAMP" text
- transport buttons render cbuttons.bmp sprites with correct pressed states
- time digits render numbers.bmp glyphs
- bitrate, "kbps", "khz" rendered as text.bmp glyphs (no system font visible)
- mono/stereo render monoster.bmp sprites
- volume/balance/seek sliders render their sprites with correct thumb tracking
- shuffle/repeat/EQ/PL toggle buttons render shufrep.bmp sprites
- spectrum bars use viscolor.txt's 24 colors
- EQ window: eqmain.bmp background visible including baked freq/dB/PRE labels; ON/AUTO/PRESETS render sprites; 10 band sliders + preamp render sprites; response curve uses 19 colors from eqmain
- Playlist: 9 frame tiles render correctly (corners, top tiles, bottom tiles, side tiles); ADD/REM/REM ALL buttons render pledit submenu sprites; row colors and font from pledit.txt; info label rendered via text.bmp at bottom
- Window has non-rectangular shape from region.txt
- View Debugger: every label in §8 has `isHidden = true`; pin button does not exist; `clrButton` does not exist (only `remAllButton`)

**`OS8 AMP - Aquamarine.wsz`:**
- All sprites that exist render correctly
- Time digits render from `nums_ex.bmp` (no `numbers.bmp` present)
- Spectrum uses default 24 viscolors (no `viscolor.txt` present) — this is correct, not a fallback
- Window is rectangular (no `region.txt` present) — correct
- Same View Debugger checks pass

**Unload check:** View → Unload Skin restores all hidden labels, transport/sliders/EQ/playlist render their built-in code, no flicker, no zombie cached sprites. Pin button does NOT come back (permanently removed). CLR button does NOT come back (renamed permanently).

**Persistence check:** Load `base-2.91.wsz`, quit app, relaunch. Skin is restored on launch with no flicker. Always-on-top toggle persists.

---

## 14. Out of scope (Phase 1-Extended)

- WindowShade mode rendering
- 8-bit indexed palette BMP decoder (use NSImage; if a real skin breaks visually, add a custom decoder)
- Custom cursors (`.cur` files)
- GEN window tiles
- Play status indicators (`playpaus.bmp` sprites — sheet is parsed and stored, but not drawn in MVP)
- `genex.bmp` UI colors for scrollbar/playlist headers
- Freeform polygon hit-testing on the main window region
- Skin library/browser UI
- `.wal` (Winamp Modern) skins

---

## 15. File structure

New files in `Wamp/Skinning/`:

| File | LOC | Purpose |
|---|---|---|
| `SkinModel.swift` | 70 | Data types: SkinModel, PlaylistStyle, default viscolors, SkinParserError |
| `SpriteCatalog.swift` | 350 | SpriteKey enum + SpriteCoordinates.resolve mapping (ported from skinSprites.ts) |
| `SkinParserUtils.swift` | 120 | ZIP extraction, image loading, nums_ex unification |
| `IniParser.swift` | 70 | Generic INI text parser |
| `ViscolorsParser.swift` | 50 | viscolor.txt → 24 NSColors |
| `PlaylistStyleParser.swift` | 80 | pledit.txt → PlaylistStyle |
| `RegionParser.swift` | 80 | region.txt [Normal] → [CGPoint] with Y-flip |
| `EqGraphColorsParser.swift` | 50 | Sample 19+1 pixels from eqmain.bmp |
| `SkinParser.swift` | 150 | Orchestrator: parseSync + async wrapper |
| `SkinProvider.swift` | 70 | Protocol + BuiltInSkin |
| `WinampClassicSkin.swift` | 100 | SkinModel-backed provider with NSCache |
| `SkinManager.swift` | 80 | ObservableObject, atomic transition() |
| `TextSpriteRenderer.swift` | 120 | text.bmp glyph map (real Webamp FONT_LOOKUP) + draw() |
| **Total** | **~1390** | |

Modified files (10):

`WinampTheme.swift`, `MainPlayerView.swift`, `EqualizerView.swift`, `PlaylistView.swift`, `LCDDisplay.swift`, `SevenSegmentView.swift`, `EQResponseView.swift`, `WinampButton.swift`, `WinampSlider.swift`, `TitleBarView.swift`.

Plus: `AppDelegate.swift` (menu items, startup load), `StateManager.swift` (skinPath field), `MainWindow.swift` (region mask application), `Wamp.xcodeproj/project.pbxproj` (ZIPFoundation SPM dependency).

---

## 16. Risks

| Risk | Mitigation |
|---|---|
| 8-bit palette BMPs decoded wrong by NSImage | Try with both shipped skins first; only build a custom decoder if visual artifacts appear |
| Sprite coordinates wrong (typo during port) | Compare side-by-side with Webamp source for any sprite that looks misaligned in smoke test |
| `draw(_:)` called too frequently when sprites swap on every press | NSCache amortizes per-sprite cost; benchmark if frames drop during sliding |
| `text.bmp` glyph rendering looks blurry due to scaling | text.bmp glyphs are 5×6 — blit at integer pixel positions, disable interpolation: `NSGraphicsContext.current?.imageInterpolation = .none` before draw |
| Region mask doesn't update on unload | Toggle via `MainWindow.applyRegionMask()` called from the SkinManager observer in MainWindow |
