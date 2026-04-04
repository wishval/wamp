# WampMac — Design Specification

Native macOS audio player inspired by Winamp 2.x. Pixel-accurate recreation of the classic UI with modern Apple audio frameworks.

> **Naming:** Xcode project is `WinampMac`. UI branding in title bars is "WAMP" / "WAMP EQUALIZER" / "WAMP PLAYLIST".

## Stack & Constraints

- **Language:** Swift, AppKit. No SwiftUI, no XIBs, no storyboards. All UI programmatic.
- **Audio:** AVAudioEngine + AVAudioPlayerNode + AVAudioUnitEQ. Apple frameworks only — no third-party dependencies.
- **Target:** macOS 12.0+, Apple Silicon.
- **State management:** Combine (`@Published` + `sink`). No KVO, no delegate-based state propagation.
- **Persistence:** Plain JSON in `~/Library/Application Support/WinampMac/`. No CoreData.
- **Sandbox:** Disabled (entitlements) for unrestricted file access.
- **Entry point:** `@main AppDelegate`. No Main.xib — all windows created in code.
- **Distribution:** Personal use / GitHub open source. No code signing or notarization.

## Architecture

Single NSWindow with vertical NSStackView hosting three togglable sections. Combine-based reactive data flow.

### File Structure

```
WinampMac/
├── AppDelegate.swift              — entry, menu bar, system tray, wires components
├── Audio/
│   └── AudioEngine.swift          — AVAudioEngine playback core
├── Models/
│   ├── Track.swift                — audio file model + ID3 metadata
│   ├── PlaylistManager.swift      — track list, ordering, shuffle, advance
│   └── StateManager.swift         — JSON persistence, app state save/restore
├── UI/
│   ├── MainWindow.swift           — single NSWindow, hosts stack of sections
│   ├── MainPlayerView.swift       — LCD, transport, seek, volume (≈275×116)
│   ├── EqualizerView.swift        — EQ with sliders + presets (≈275×116)
│   ├── PlaylistView.swift         — track list, search, controls (≈275×232)
│   ├── Components/
│   │   ├── WinampSlider.swift     — custom horizontal/vertical slider
│   │   ├── WinampButton.swift     — custom drawn button with states
│   │   ├── LCDDisplay.swift       — green-on-black scrolling text display
│   │   ├── SpectrumView.swift     — real-time FFT spectrum analyzer
│   │   ├── SevenSegmentView.swift — 7-segment digital time display
│   │   ├── EQResponseView.swift   — EQ frequency response curve
│   │   └── TransportBar.swift     — prev/play/pause/stop/next/eject group
│   └── WinampTheme.swift          — all colors, fonts, dimensions as constants
├── Utils/
│   └── HotKeyManager.swift        — media keys + Now Playing info center
├── Info.plist
└── WinampMac.entitlements
```

### Data Flow

```
AppDelegate (owns everything, wires subscriptions)
  │
  ├── AudioEngine (ObservableObject)
  │   @Published: isPlaying, currentTime, duration, volume, balance, isMuted
  │   @Published: repeatMode (.off / .track / .playlist), eqEnabled, eqBands, preampGain
  │   Methods: play(url), pause(), stop(), seek(to:), setEQ(band:gain:), setPreamp(gain:)
  │   Posts: .trackDidFinish notification
  │   Provides: spectrum data via audio tap for visualization
  │
  ├── PlaylistManager (ObservableObject)
  │   @Published: tracks, currentIndex, isShuffled, searchQuery, filteredTracks
  │   Subscribes to: .trackDidFinish → auto-advances based on repeat/shuffle mode
  │   Methods: add/remove/clear, next/previous, shuffle, search, save/load playlists
  │
  ├── StateManager
  │   Subscribes to: AudioEngine + PlaylistManager @Published props
  │   Auto-saves on changes (debounced 0.5s) to ~/Library/Application Support/WinampMac/
  │   Restores full state on launch
  │
  └── MainWindow
      ├── MainPlayerView — binds to AudioEngine + PlaylistManager
      ├── EqualizerView  — binds to AudioEngine EQ state
      └── PlaylistView   — binds to PlaylistManager

User action → View calls model method → @Published updates → UI redraws via sink
```

## Window Architecture

Single borderless `NSWindow` (`styleMask: .borderless`) with `isMovableByWindowBackground = true`. Contains a vertical `NSStackView` with three section views.

### Section Visibility

Main player is always visible. Equalizer and Playlist sections toggle via `isHidden` on the section view. Window resizes with animation to fit visible sections. Toggled via:
- EQ/PL buttons in the main player transport bar
- View menu (Cmd+1, Cmd+2, Cmd+3)

| Configuration | Approximate Size |
|---|---|
| All visible | 275 × 510 |
| Player + Playlist | 275 × 380 |
| Player + EQ | 275 × 264 |
| Player only | 275 × 148 |

## UI Design — Winamp 2.x Faithful

All custom UI elements are `NSView` subclasses with `draw(_ dirtyRect:)`. No standard AppKit controls for visual elements. Custom-drawn everything for authentic Winamp pixel art feel.

### Color Palette

| Token | Hex | Usage |
|---|---|---|
| Frame background | `#3C4250` | Metallic blue-gray app frame |
| Frame border light | `#5A6070` | Top/left beveled edge |
| Frame border dark | `#20242C` | Bottom/right beveled edge |
| Title bar gradient | `#4A5268` → `#222840` | Title bar background |
| Title bar stripes | `#B8860B` / `#DAA520` | Yellow-orange decorative grip lines |
| Title bar text | `#C0C8E0` | Title text color |
| LCD background | `#000000` | Display panels |
| Green bright | `#00E000` | Active text, indicators, time digits |
| Green secondary | `#00A800` | Track numbers, durations |
| Green dim | `#1A3A1A` | Inactive indicators |
| Green dim text | `#1A5A1A` | Labels (kbps, kHz) |
| White | `#FFFFFF` | Currently playing track text |
| Selection blue | `#0000C0` | Playlist selection highlight |
| Button face | `#4A4E58` → `#3A3E48` | 3D embossed buttons |
| Button border light | `#5A5E68` | Button top/left bevel |
| Button border dark | `#2A2E38` | Button bottom/right bevel |
| Seek/balance fill | `#6A8A40` → `#4A6A28` | Olive-green slider fill |
| Seek thumb | `#9AA060` → `#4A5A28` | Olive slider thumb |
| Volume background | `#1A1200` → `#AA7000` | Orange gradient volume track |
| Volume fill | `#8A6A20` → `#FFAA00` | Orange volume fill |
| Volume thumb | `#DAA520` → `#8A6000` | Orange/gold volume thumb |
| EQ slider bg | `#2A2810` → `#332E14` | Yellow-tinted EQ track |
| EQ thumb | `#B0BA60` → `#6A7A28` | Olive-yellow EQ thumb |
| EQ fill | `#2A6A10` → `#4A8A20` | Green EQ band fill |
| Spectrum bars | `#00C000` → `#E0E000` | Green-to-yellow gradient |

### Fonts

- Title bars: Tahoma 8px bold, letter-spacing 1.5px
- Track title scroll: Tahoma 9px
- Bitrate/kHz labels: Tahoma 6-7px
- Playlist tracks: Arial 8.5px
- Time display: Custom 7-segment SVG digits
- EQ labels: Tahoma 6px
- Buttons: Tahoma 7px bold

### Main Player Section (≈275 × 116 px)

Title bar: "WAMP" with yellow-orange stripe bars on both sides. Minimize, shade, close buttons on right.

**Left display panel** (unified black background):
- Top row: play state indicator (▶ triangles) left-aligned, 7-segment time display (M:SS) right-aligned
- Bottom: spectrum analyzer bars spanning full width (real-time FFT visualization)

**Right display panel** (black background):
- Scrolling track title: "N. Artist - Title (duration)" in green
- Metadata row: bitrate box (128 kbps), sample rate box (48 kHz), mono/stereo indicators

**Controls below displays:**
- Seek bar: full width, olive-green fill with thumb
- Volume slider (orange gradient background + orange thumb) and balance slider (olive-green) side by side
- Transport buttons: ⏮ ▶ ⏸ ⏹ ⏭ ⏏ (custom-drawn, active state in green)
- Shuffle icon (crossing arrows), Repeat icon (circular arrows) — SVG icons, green when active
- EQ toggle, PL toggle — text buttons, green when active

### Equalizer Section (≈275 × 116 px)

Title bar: "WAMP EQUALIZER" with yellow-orange stripes.

**Controls row:** ON button (green when active), AUTO button, PRESETS button (opens preset menu).

**Slider area:**
- dB scale labels on far left: +12, 0, -12
- Preamp vertical slider (labeled "PRE")
- dB response curve display (labeled "dB") — SVG polyline showing current EQ shape
- Vertical separator
- 10 band vertical sliders: 70, 180, 320, 600, 1K, 3K, 6K, 12K, 14K, 16K Hz

All slider tracks have yellow-tinted background with tick marks and center line at 0 dB. Olive-yellow thumbs. Green fill from center in direction of gain.

### Playlist Section (≈275 × 232 px, resizable height)

Title bar: "WAMP PLAYLIST" with yellow-orange stripes.

**Track list** (black background):
- Each row: "N. Artist - Title" (green) + right-aligned duration
- Currently playing track: white text
- Selected track: blue (#0000C0) background
- Double-click to play
- Scrollbar on right side: up/down arrows + draggable thumb

**Search bar** (below track list):
- Compact filter-as-you-type field on dark background
- Filters visible tracks in real-time, clearing restores full list

**Bottom bar:**
- Left: ADD, REM, CLR buttons
- Right: track count + total duration on black background (e.g., "7 tracks / 27:45")

## Audio Pipeline

```
AVAudioPlayerNode → AVAudioUnitEQ (10 bands + preamp) → engine.mainMixerNode → output
```

### Supported Formats

MP3, AAC, M4A, FLAC, WAV, AIFF — all native via AVFoundation.

### Playback Modes

| Mode | Behavior |
|---|---|
| Repeat Off | Stop after last track |
| Repeat Track | Re-schedule from frame 0 on completion |
| Repeat Playlist | Jump to track 1 after last track finishes |
| Shuffle | Fisher-Yates random order, no repeats until all tracks played |

Shuffle and repeat modes are independent — shuffle + repeat playlist plays in random order indefinitely.

### Seek

Stop playerNode, `scheduleSegment` from target frame, restart.

### Previous Track

If `currentTime > 3.0` seconds → restart current track. Otherwise → go to previous index (or last track in shuffle history).

### Track Completion

`AVAudioPlayerNode` completion handler posts `Notification.Name.trackDidFinish`. PlaylistManager subscribes and auto-advances based on current repeat/shuffle mode.

### Metadata

Async `asset.load(.commonMetadata)` and `asset.load(.duration)` — NOT deprecated synchronous properties. Factory method `Track.fromURL` handles metadata load failure gracefully — returns track with filename as title.

### Visualization

Real-time spectrum analyzer from `AVAudioEngine` tap on mainMixerNode:
- `installTap(onBus:bufferSize:format:)` with buffer size 1024
- FFT via Accelerate framework (`vDSP_fft_zrip`)
- Maps frequency bins to spectrum bars
- Green-to-yellow gradient bars (`#00C000` → `#E0E000`)

### EQ

10 bands at Winamp standard frequencies: 70, 180, 320, 600, 1K, 3K, 6K, 12K, 14K, 16K Hz.
- Range: ±12 dB per band
- Preamp: ±12 dB, applied as gain multiplier on mainMixerNode
- AVAudioUnitEQ with `.parametric` filter type per band

Presets: Flat, Rock, Pop, Jazz, Classical, Bass Boost, Treble Boost, Vocal, Electronic, Loudness.

AUTO mode: automatically loads matching preset when a new track starts (matches by genre metadata if available).

## App Features

### State Persistence

JSON files in `~/Library/Application Support/WinampMac/`:

| File | Contents |
|---|---|
| `state.json` | Volume, balance, repeat mode, shuffle, EQ on/off, window position, section visibility, last track index, playback position |
| `equalizer.json` | Band gains, preamp, current preset name, auto mode |
| `playlist.json` | Current playlist (file paths + cached metadata) |
| `playlists/*.json` | Named saved playlists |

Auto-save: debounced (0.5s) on any `@Published` change. Full restore on launch.

### System Tray

`NSStatusItem` with custom-drawn music note icon. Menu items:
- Show Player
- Play/Pause
- Next Track
- Previous Track
- (separator)
- Quit

### Menu Bar

- **File:** Open File (Cmd+O), Open Folder (Cmd+Shift+O)
- **Controls:** Play/Pause (Space), Stop (Cmd+.), Next (Cmd+→), Previous (Cmd+←), Repeat (Cmd+R), Shuffle (Cmd+S)
- **View:** Show Player (Cmd+1), Show Equalizer (Cmd+2), Show Playlist (Cmd+3)

### Media Keys

Via `MPRemoteCommandCenter`: play, pause, togglePlayPause, nextTrack, previousTrack, changePlaybackPosition (seek).

### Now Playing

Via `MPNowPlayingInfoCenter`: title, artist, album, artwork, duration, elapsed time, playback rate.

### Drag & Drop

Files and folders from Finder onto playlist area. Recursive `FileManager` enumerator, sorted by filename, filtered by supported audio extensions. Appends to playlist without interrupting current playback.

### File Association

Double-click audio file in Finder or drag to Dock icon → append to current playlist, don't interrupt playback.

### App Lifecycle

`applicationShouldTerminateAfterLastWindowClosed` returns `false`. App keeps running in tray mode. `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront` on launch.

## Implementation Notes

- All custom UI: `NSView` subclasses with `draw(_ dirtyRect:)`, no standard controls
- Window drag: `isMovableByWindowBackground = true`
- Use `NSView.BackgroundStyle.emphasized` (not deprecated `.dark`)
- Playlist: `NSTableView` with custom row views, custom blue selection drawing
- Folder scanning: recursive `FileManager` enumerator, sort by filename, filter by supported extensions
- Track title scrolling: `CADisplayLink` or `Timer`-based horizontal offset animation in LCDDisplay
- EQ response curve: recalculated on any band/preamp change, drawn as SVG-style polyline in `EQResponseView`
