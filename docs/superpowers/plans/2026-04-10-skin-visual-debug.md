# Skin Visual Debugging Plan (Phase 2)

> **Continuation of:** `docs/superpowers/plans/2026-04-10-skin-support.md` (Tasks 1–17 complete on branch `feature/skin-v2`).
> **Spec to re-read first:** `docs/superpowers/specs/2026-04-10-skin-support-design.md`
> **For agentic workers:** This is an iterative visual fix plan, not a linear build plan. Use `superpowers:executing-plans` or work freeform — every fix needs a screenshot from the user, so it's not subagent-friendly.

## Context

Phase 1 (Tasks 1–17) added the skin parser, provider, and `drawSkinned` paths to all skinnable views on branch `feature/skin-v2`. The code compiles and skins load without crashing — the parser, ZIP extraction, and SkinManager lifecycle work. **But the visual output is broken across all four test skins.** This plan exists to fix that.

The user reports "all skins look broken" without further specifics. **Your first task is to find out HOW they're broken**, not to guess. Don't start patching coordinates blindly.

## What you need before starting

1. **Read these files in order:**
   - `docs/superpowers/specs/2026-04-10-skin-support-design.md` (the design — especially §2.2 on draw()-based rendering, §7 view integration, §8 hide-when-skinned, §12 known pitfalls)
   - `docs/superpowers/plans/2026-04-10-skin-support.md` (the build plan, for context on what was done and why)
   - `Wamp/Skinning/SpriteCatalog.swift` (the Webamp coordinates I ported)
   - `Wamp/Skinning/TextSpriteRenderer.swift` (the FONT_LOOKUP and Y-flip math)
   - `Wamp/UI/MainPlayerView.swift` — `drawSkinned()` and `applySkinVisibility()` and the click hit-zone math
   - `Wamp/UI/EqualizerView.swift` — `drawSkinned()` and `applySkinVisibility()`
   - `Wamp/UI/PlaylistView.swift` — `drawSkinned()` and the 9-tile frame layout
   - `Wamp/UI/Components/WinampSlider.swift` — `drawSkinned()` for all 4 styles
   - `Wamp/UI/Components/SevenSegmentView.swift` — sprite digit branch
   - `Wamp/UI/Components/TitleBarView.swift` — `drawSkinned()`
   - `Wamp/UI/Components/EQResponseView.swift` — `drawSkinned()` with 19-color graph
   - `Wamp/UI/Components/SpectrumView.swift` — viscolors gradient

2. **Confirm you're on the right branch:**
   ```bash
   git branch --show-current   # should be feature/skin-v2
   git log --oneline ^main feature/skin-v2 | head
   xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -3
   ```

3. **Verify the four test skins are present:**
   ```bash
   ls skins/
   # base-2.91.wsz, OS8 AMP - Aquamarine.wsz, Blue Plasma.wsz, Radar_Amp.wsz
   ```

## The fix-one-skin-first strategy

**Pick `base-2.91.wsz` first.** Reasons:
- It's the canonical Winamp 2.91 skin — sprite coordinates were ported with it as the reference
- It has all 13 sheets present (no missing-file edge cases to worry about)
- It has `region.txt` — exercises the window mask path
- If this doesn't render correctly, nothing else will. Get it right first.

After `base-2.91.wsz` looks correct, validate the other 3 in order:
1. `OS8 AMP - Aquamarine.wsz` — tests `nums_ex` unification + missing optional files + subdirectory wrapper
2. `Blue Plasma.wsz` — tests case-insensitive lookup + ignoring `.psd`/`Readme.txt` junk
3. `Radar_Amp.wsz` — tests mixed-case across image AND text files (`PLEDIT.TXT`, `VISCOLOR.TXT`)

The other skins should mostly "just work" once base-2.91 does — they share the same code paths.

## The iteration loop

This is not a linear plan. Each cycle is:

1. **Ask the user for a screenshot** of the current visual state with `base-2.91.wsz` loaded. Tell them: "Open Wamp.xcodeproj in Xcode, Cmd+R, View → Load Skin → skins/base-2.91.wsz, then take a screenshot of the whole window and drag it into the chat." The first screenshot is a survey.

2. **Identify problems by category** (see below). Don't rush to fix everything at once. Pick the most fundamental issue first — usually the background sprite or the coordinate space.

3. **Hypothesize and verify** before patching. If a sprite looks wrong, ask: is the issue (a) wrong coordinates in `SpriteCatalog`, (b) wrong rect in `drawSkinned`, (c) wrong scale, (d) Y-flip issue, (e) wrong sheet name, (f) sheet not being loaded? Each has a different fix.

4. **Make ONE change**, rebuild, ask for another screenshot. Multiple simultaneous changes make it impossible to attribute progress or regression.

5. **Commit each fix with a one-line message** that names the specific bug. Future-you will read these.

## Likely problem categories

Based on the design, here are the categories I expect to encounter, in rough order of likelihood:

### Category 1: coordinate system / scale mismatch

**Symptom:** Sprite is drawn but in the wrong size or wrong corner; appears stretched or shrunk; everything is "almost right" but offset by tens of pixels.

**Why it happens:** `MainWindow` scales the entire window by `WinampTheme.scale = 1.3`. Inside views, `bounds.width` is the **logical** 275, not the scaled 357. The sprites are drawn in logical coordinate space and then the layer scales them. **But:** if any code accidentally uses `frame` instead of `bounds`, or scales twice, the result is broken.

**Where to look first:**
- `MainPlayerView.drawSkinned()` — `mainRect = NSRect(x: 0, y: 0, width: bounds.width, height: 116)`. Is `bounds.width` actually 275 here? Add a `print(bounds)` to confirm.
- `MainWindow.swift` initializer — `container.setBoundsSize(NSSize(width: WinampTheme.windowWidth, height: height))` should ensure bounds are logical.
- Verify with View Debugger: select MainPlayerView and read its `bounds` and `frame`.

**Likely fix:** Adjust drawSkinned rects to match the actual logical bounds, OR remove a stray multiplication.

### Category 2: Y-axis flipped

**Symptom:** Sprites appear at the wrong vertical position — bitrate text at the top instead of middle, mono/stereo above the LCD instead of inside it, etc. Often "mirrored" vertically.

**Why it happens:** Webamp uses Y=0 at the top of `main.bmp` (Y-down). AppKit uses Y=0 at the bottom of the view (Y-up). Every Webamp coordinate has to be flipped: `Y_appkit = mainHeight - Y_webamp - height`. I did this conversion in `MainPlayerView.drawSkinned`. The values may be wrong.

**Where to look first:**
- `MainPlayerView.drawSkinned`, the mono/stereo and text.bmp blocks. Verify the Y conversion is correct against Webamp's actual coordinates.
- Webamp source for reference: `https://github.com/captbaritone/webamp/blob/master/packages/webamp/css/main-window.css`
- `RegionParser.parseMainWindowRegion` — Y-flip happens there too. If the window mask is mirrored, fix this.

**Note:** `bg.draw(in: rect)` itself flips the image automatically (NSImage.draw handles AppKit's coordinate space). The Y issue only affects the **positions** where you draw individual sub-sprites on top of the background.

### Category 3: hide-when-skinned not actually hiding

**Symptom:** You see both the sprite AND the NSTextField label / black panel / Tahoma "WAMP" text simultaneously. Double-rendering.

**Why it happens:** `applySkinVisibility()` is called from the SkinManager observer sink, which runs on `DispatchQueue.main`. If the view's `wantsLayer = true` and the layer is composited before the sink fires, you see a flash of the old state. Or `applySkinVisibility` isn't called at all on initial load (the spec restores skin BEFORE views are created).

**Where to look first:**
- `MainPlayerView.init` — does it call `applySkinVisibility()` at the end? Yes, it does in the current code. But the sink fires AFTER init returns. If a skin is restored at startup (before MainPlayerView is created), then init's `applySkinVisibility()` sees an already-active skin and hides correctly. This is the happy path.
- Use Xcode View Debugger: Capture View Hierarchy and confirm `isHidden = true` on `bitrateLabel`, `monoLabel`, `titleBar`, `leftPanel`, `rightPanel`, etc. If any are `false`, the toggle didn't happen.
- If they're hidden but you still see them in the screenshot, then **the layer cached an old draw** and you need `needsDisplay = true` after toggling. The current code does this — verify.

### Category 4: sprite coordinates wrong in SpriteCatalog

**Symptom:** A specific sprite (e.g. play button) is rendered but shows the wrong content — part of an adjacent sprite, or a slice from the wrong row.

**Why it happens:** I ported the coordinates from Webamp manually. There may be off-by-one errors, swapped X/Y, or wrong sprite sheet for a key.

**Where to look:**
- `Wamp/Skinning/SpriteCatalog.swift` — find the case for the broken sprite
- Compare against `https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts` (use WebFetch)
- Most likely culprits: `eqSliderBackground` (I used `(13, 164, 14, 63)` but Webamp may use a different rect — needs verification), `eqOnButton`/`eqAutoButton` x positions for active+pressed combinations, the BALANCE thumb x coordinates (I have `pressed ? 0 : 15` — verify it's not the other way around).

### Category 5: text.bmp glyph rendering wrong

**Symptom:** The bitrate / "kbps" / "khz" / scrolling LCD shows random characters or blank spaces or only some glyphs.

**Why it happens:** The Y-flip in `TextSpriteRenderer.draw()` may be wrong. Or the FONT_LOOKUP table I ported has a typo. Or the destination Y in callers is wrong.

**Where to look:**
- `Wamp/Skinning/TextSpriteRenderer.swift` — the Y-flip logic in `draw(_:at:sheet:)`. The line is `let cgY = CGFloat(cg.height) - rect.origin.y - rect.height`. Verify this against actual text.bmp content by extracting one glyph manually.
- `MainPlayerView.drawSkinned` — the `textY` calculation: `textY = mainHeight - 43 - 6`. Webamp's `Time.tsx` has the actual Y position; verify.

### Category 6: PlaylistView frame tiles misaligned

**Symptom:** The playlist window has visible gaps between frame tiles, or tiles overlap, or the title bar centerpiece is in the wrong place.

**Why it happens:** I tile the top and side pieces with hard-coded math (`while x < titleX { topTile.draw(...); x += 25 }`). If the playlist width isn't a multiple of 25 + corner widths, the last tile clips. The bottom row uses `playlistBottomLeftCorner` (125 wide) and `playlistBottomRightCorner` (150 wide) — they may overlap or leave a gap depending on playlist width.

**Where to look:**
- `Wamp/UI/PlaylistView.swift` `drawSkinned()` — the tile loops
- Verify against Webamp's `PlaylistShade` / `Playlist` rendering

### Category 7: button frames don't match sprite sizes

**Symptom:** Sprites for buttons look "squashed" or "stretched" — they're being drawn into the existing Wamp button frames which have different aspect ratios than the Winamp originals.

**Why it happens:** Wamp's `MainPlayerView.layout()` sizes buttons based on Wamp's layout math, not Winamp's pixel dimensions. For example, the transport button frame is `22×18`, which matches `cbuttons.bmp` (good), but the toggle buttons are `20×16` while shufrep sprites are `23×12` (eq/pl) or `47×15` (shuffle) or `28×15` (repeat) — different dimensions.

**Where to look:**
- `MainPlayerView.layout()` — the toggle button frames. Either resize them to match sprite dimensions, or accept the stretching.
- Same for `EqualizerView.layout()` — `onButton.frame` is `26×14`, sprite is `26×12`. Close but not exact.

**Decision:** Spec §1 says "we do not move buttons or add new controls". Resizing a button's *frame* technically changes its size but not its position. Acceptable if it makes the sprite look right. If you change a button frame, do it minimally and document why.

## Fix workflow per cycle

For each round of "screenshot → fix":

1. Ask user for current screenshot
2. Identify the **single most fundamental** problem visible (start with backgrounds before details)
3. State your hypothesis: "I think X is wrong because Y. The fix is Z. Want me to try?"
4. On approval, make the fix
5. Run `xcodebuild ... build 2>&1 | tail -5` — pre-commit hook will catch errors
6. `git commit` with a one-line message naming the specific bug fixed
7. Ask for the next screenshot
8. Repeat

**Don't:**
- Patch multiple things at once. You won't know which fix did what.
- Guess at coordinates. Read Webamp's source and compare.
- Skip the rebuild. The pre-commit hook will catch it but better to know early.
- Forget to ask for a screenshot. Your eyes can't see the result.

## Tools available

- `xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build` — should always pass; pre-commit hook gates this
- `WebFetch` against Webamp source — `https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts` and other files in that tree
- `Read` on any file in the project
- The four `.wsz` skins in `skins/` are extracted ZIP files; you can unzip them to `/tmp/` to inspect their actual `.bmp` files visually if needed
- The user has Xcode View Debugger and can capture view hierarchies on request

## What "done" looks like

For `base-2.91.wsz`:
- Main window: skin background visible, no gray frame, title strip with "WINAMP" baked in, transport buttons sprite-rendered with pressed states, time digits from numbers.bmp, bitrate/kbps/khz via text.bmp, mono/stereo from monoster
- EQ window: eqmain background covers everything, freq/dB/PRE labels are baked into the sprite (not NSTextField overlay), 10 sliders + preamp render correctly, on/auto/presets button sprites work, response curve uses the 19 line colors
- Playlist: 9 frame tiles render as one continuous frame (no gaps), text colors from pledit.txt, info text via text.bmp at the bottom, "REM ALL" button visible
- Window has the non-rectangular shape from region.txt
- Spectrum bars use viscolor.txt's gradient colors
- View Debugger: every label in spec §8 hide-when-skinned table is `isHidden = true`

Then verify the other three skins one by one. They should mostly just work — flag any new issues as separate fix cycles.

## Out of scope for this plan

- Adding new features
- Rewriting any existing built-in rendering paths
- Layout changes (moving buttons, resizing the window, etc.)
- WindowShade mode, custom cursors, .wal skins, anything in spec §14 (Phase 1-Extended)
- Re-running the parser on other skins to find new edge cases — wait until base-2.91 is correct

## Done condition for the plan

User says "all four skins look right" or equivalent. Then invoke `superpowers:finishing-a-development-branch` to merge `feature/skin-v2` into `main`.
