# Skin Visual Debug — Round 2 (base-2.91)

> **Continuation of:** `2026-04-10-skin-visual-debug.md`. Round 1 fixed the main-window title, EQ title clipping, time digits, marquee glyph Y-flip, and playlist layout + running-time placement. All on branch `feature/skin-v2`.
>
> **Reference spec:** `docs/superpowers/specs/2026-04-10-skin-support-design.md`

## Context

With base-2.91 loaded the overall layout is correct: sprite backgrounds, titles, marquee text, and time digits all render right. The remaining issues are a mix of sprite-coordinate bugs, state-binding gaps, NSTableView quirks, and double-rendering between native AppKit chrome and baked Winamp sprites.

Do these fixes one-by-one, rebuild after each, **ask for a screenshot**, then commit with a one-line message naming the bug. Don't batch. Round 1 taught us that "obvious" fixes often need a second pass to place things correctly — trust the screenshot, not the code reasoning.

## Open bugs

### Bug A — mono/stereo indicators swapped

**Symptom:** The mono and stereo sprites in the main player's bitrate row are in the wrong positions — stereo shows where mono should and vice versa.

**Hypothesis:** In `MainPlayerView.drawSkinned()`, the stereo sprite draws at `x=212` and mono at `x=239`. Webamp's CSS puts `#stereo` at `left:239` and `#mono` at `left:212`. The X positions are swapped. Also verify the sheet-row `active` parameter isn't inverted in `SpriteCatalog` (Webamp's monoster.bmp row 0 is inactive, row 12 is active — or the other way around, need to confirm against the actual sheet).

**Fix plan:**
1. Swap the `x` arguments for `.stereo` and `.mono` draw rects in `MainPlayerView.drawSkinned`.
2. Open `/tmp/base-skin/MONOSTER.BMP` in Preview and verify which row is active — double-check `SpriteCatalog.mono`/`.stereo` rect.y values.

**Files:** `Wamp/UI/MainPlayerView.swift`, possibly `Wamp/Skinning/SpriteCatalog.swift`.

---

### Bug B — kbps / khz wrong color + artifact behind them + numbers may not update

**Symptom:** The `kbps` / `khz` labels render via text.bmp but with a wrong color, and there's a visible artifact behind them. It's unclear whether the bitrate / sample-rate numbers ever actually update when the track changes.

**Hypotheses (investigate in order):**
1. **Numbers not updating:** `MainPlayerView.drawSkinned` reads `playlistManager?.currentTrack?.bitrate` / `.sampleRate`, but `drawSkinned` is only invoked on `needsDisplay`. Check whether `bindToModels`' `currentIndex` sink triggers `needsDisplay = true` on self in addition to calling `updateTrackInfo()` — `updateTrackInfo` only updates the hidden NSTextField labels, it does not invalidate the drawSkinned overlay.
2. **Wrong color:** text.bmp in base-2.91 has glyphs in a specific color (usually bright green). If the user sees a different color, either (a) the sheet isn't being decoded correctly (verify by drawing the full text.bmp somewhere as a debug overlay), or (b) the blend mode is wrong — the glyphs may have a background color baked in that's showing through. Check what base-2.91's TEXT.BMP actually looks like.
3. **Artifact behind:** could be (a) the old `bitrateUnitLabel` / `sampleRateUnitLabel` NSTextField still visible (verify `applySkinVisibility()` hides them — it currently does), (b) text.bmp glyph rows overlapping (check `TextSpriteRenderer.draw` increments x by `glyphWidth = 5` only, no extra padding, so adjacent glyphs can't overlap), or (c) leftover pixels from a previous `drawSkinned` call not being cleared (NSView drawing should clear, but check `wantsLayer` state).

**Fix plan:**
1. Add a `needsDisplay = true` to the `currentIndex` sink in `MainPlayerView.bindToModels` so the drawSkinned overlay re-runs when track changes. Confirm bitrate/sample-rate now update on track change.
2. Extract TEXT.BMP from base-2.91 to `/tmp` and view it. Note the actual glyph colors. If wrong, ensure the parser isn't stripping alpha or applying color correction in `SkinParser.swift` → `loadSheet`.
3. Capture the main player in View Debugger with skin active. Confirm every hidden NSTextField in the bitrate/mono/stereo row has `isHidden = true`.

**Files:** `Wamp/UI/MainPlayerView.swift`, possibly `Wamp/Skinning/SkinParser.swift`, possibly `Wamp/Skinning/TextSpriteRenderer.swift`.

---

### Bug C — EQ slider background color wrong

**Symptom:** The EQ band slider track backgrounds are a completely different color from what base-2.91 should display.

**Hypothesis:** The eqmain.bmp body sprite (`.eqBackground` at (0,0,275,116)) already contains baked slider tracks as part of the window background. The `WinampSlider` with `style: .eqBand` additionally draws `.eqSliderBackground` (currently `(13, 164, 14, 63)`) on top of its bounds — which is either the wrong sheet region or shouldn't be drawn at all because it double-renders over the already-baked pixels.

**Fix plan:**
1. First hypothesis: remove the `.eqSliderBackground` draw entirely when the slider is inside an EQ and the `.eqBackground` is already painted by the parent view. Rebuild, screenshot. If the sliders look correct (just using the baked track), done.
2. If the baked tracks are NOT at the slider positions, we need to draw the correct slider-track sprite. Check Webamp's actual coordinates for EQ band slider background — `skinSprites.ts` should have a `BAND_LINE` or similar entry. Update `SpriteCatalog.eqSliderBackground` to match.
3. Also check the thumb sprite `eqSliderThumb(position:, pressed:)` — it may have the wrong y-row too.

**Files:** `Wamp/UI/Components/WinampSlider.swift`, `Wamp/Skinning/SpriteCatalog.swift`.

---

### Bug D — playlist row height too tall

**Symptom:** Each track row in the playlist is noticeably taller than in classic Winamp.

**Hypothesis:** `PlaylistView.setupSubviews` hardcodes `tableView.rowHeight = 18`. Classic Winamp playlist uses the text.bmp font which is ~6 px tall per glyph — rows are typically rendered at 13 px or less. When a skin is active we should either (a) shrink `rowHeight` or (b) switch to a text.bmp-rendered row cell entirely.

**Fix plan:**
1. When skin activates, set `tableView.rowHeight` to a smaller value (try 13 first). Update `applySkinVisibility` to toggle this. Call `tableView.reloadData()` after changing rowHeight so visible rows re-render.
2. The row cell itself still uses NSTextField with `WinampTheme.playlistFont`. For an authentic look, the cell content should also render via text.bmp glyphs — but that's Phase 3 work. For now just fix the row height. Adjust font size so text still fits legibly inside the shorter row.
3. Pledit.txt parses `PlaylistStyle` (normal/current/normal-bg/selected-bg colors + font). Make sure the existing `PlaylistStyle` is applied to row cells when skinned (textColor, backgroundColor), using the parsed colors instead of `WinampTheme.greenBright` etc.

**Files:** `Wamp/UI/PlaylistView.swift`.

---

### Bug E — track duration clipped by scrollbar + reflows on insert

**Symptom:** The duration column on the right side of each row is partially hidden under the vertical scroll bar. When a new track is added, the table reloads and the duration becomes fully visible.

**Hypothesis:** The cell layout in `tableView(_:viewFor:row:)` computes `durLabel.frame.x = cellW - durWidth - 10` where `cellW = tableColumn?.width ?? 200`. But `column.width` is set once in `setupSubviews` and later adjusted in `layout()` to `scrollView.frame.width - scrollerWidth - 2`. When `setupSubviews` first creates cells, the column width hasn't been adjusted yet. On reload the newer column width takes effect and cells recomputed correctly. The fix is to either (a) resize the column before any cells render, or (b) make the cell use `tableColumn.width` at draw time instead of a captured value, or (c) use Auto Layout inside the cell so it reflows with the column.

**Fix plan:**
1. Verify the hypothesis: log `tableColumn?.width` inside `viewFor:row:` on first render vs. subsequent renders.
2. Fix by either setting a conservative initial column width that accounts for the scroller (subtract ~16 at init), OR by using `tableView.reloadData()` after the first `layout()` pass, OR by making `durLabel` use an Auto Layout constraint trailing the cell's right edge with a padding that accounts for the scroller.
3. After fix, confirm rows render correctly on initial load without needing to add a track.

**Files:** `Wamp/UI/PlaylistView.swift`.

---

### Bug F — two scrollbars: native NSScroller visible alongside empty space for skin scroller

**Symptom:** The playlist reserves a 20 px strip on the right for the skinned scroll handle (`playlistRightTile`), but no scroll handle is drawn there. Instead the native NSScroller renders to the *left* of that strip, giving the impression of two scrollbars — an empty skin scroller and a working standard one.

**Hypothesis:** When skinned, we should:
1. Hide the native NSScroller entirely.
2. Draw the `.playlistScrollHandle` sprite at the correct position inside the reserved right strip, with its Y offset computed from `scrollView.documentVisibleRect.origin.y / contentHeight` and handle height = `visibleHeight / contentHeight * trackHeight`.
3. Make the handle draggable (mouse events on the tile area call `scrollView.contentView.scroll(to:)`).

This is a small custom scroller implementation. Alternatively, a quicker temporary fix is to hide the native scroller and accept no scrolling via mouse (keyboard arrows still work). That's unacceptable UX though.

**Fix plan:**
1. Create a `PlaylistSkinScroller: NSView` that lives in the right-tile area when skinned. It observes `scrollView.contentView.bounds` changes and redraws the `.playlistScrollHandle` sprite at the right Y.
2. Handle mouse drag on the scroller view to scroll the clipView.
3. Hide `scrollView.verticalScroller` when skinned. Re-enable when unskinned.
4. Adjust `scrollView.frame.width` in `layoutSkinned` so it doesn't overlap the skin scroller strip.

**Files:** `Wamp/UI/PlaylistView.swift`, possibly a new file `Wamp/UI/Components/PlaylistSkinScroller.swift`.

---

## Recommended order

Do Bug A first (trivial, one-line-ish fix — warms up the cycle). Then B (investigate whether numbers update at all — root cause hunt, may reveal misc binding issues). Then D (row height — affects the feel of the playlist the most). Then E (duration clipping — depends on D). Then C (EQ slider bg — isolated). Then F (scroller — biggest change, save for last so the previous fixes are already validated).

After each bug is fixed and committed, re-screenshot all three panels (main / EQ / playlist) to catch any regressions from the previous fix.

## When this round is done

Move on to the other three test skins: `OS8 AMP - Aquamarine.wsz`, `Blue Plasma.wsz`, `Radar_Amp.wsz`. Any new bug categories get their own round plan.

## Out of scope for this round

- Making the baked ADD/REM/SEL/MISC buttons in pledit clickable (hit zones) — separate task, not blocking.
- Making the baked main-window transport buttons (eject strip) clickable — same.
- Anything in the original plan §14 "Phase 1-Extended" (WindowShade, .wal, custom cursors).
- Rewriting the playlist cell to render via text.bmp glyphs — future Phase 3.
