# Visual Polish & Play Bug — Design Spec

Date: 2026-04-13

## Tasks

### 1. Playlist bottom button labels
Rename: "REM ALL" → "CLEAR", "LIST OPTS" → "LISTS". Add missing `spriteKeyProvider` for listOptsButton. Add `SpriteKey` cases for selectAll and miscOpts from pledit.bmp. Ensure skin mapping works correctly when skin is active.

### 2. Dotted line style consistency
Add horizontal dotted line at bottom of left panel (below spectrum). Unify dash pattern with existing vertical line — both should use same dash/gap ratio. Forms L-shaped corner.

### 3. EQ section colors from original skin
Extract colors from `skins/base-2.91.wsz` eqmain.bmp. Update `WinampTheme` unskinned palette to match original Winamp 2.x EQ colors.

### 4. Volume slider gradation from original skin
Extract volume bar colors from `skins/base-2.91.wsz` volume.bmp. Update unskinned volume slider to use matching color gradation.

### 5. Fix play-on-launch bug
Root cause: `AppDelegate` restores `playlistManager.currentIndex` but never calls `audioEngine.loadAndPlay()`. AudioEngine.play() silently returns when `audioFile == nil`. Fix: after playlist restore, load (but don't auto-play) the current track so pressing Play works.

### 6. EQ response curve gradient coloring
Replace solid green line with HSV gradient: green at cut (-12dB), yellow at flat (0dB), red at boost (+12dB). Match the existing EQ slider fill color logic in WinampSlider.
