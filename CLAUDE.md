# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS app built with Xcode. Open `Wamp.xcodeproj` and build/run from Xcode, or use:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build
```

Run the test suite:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test
```

No linter and no CI/CD are configured. Tests cover `Models/`, `CueSheet/`, and a persistence round-trip only — `AudioEngine`, UI views, `HotKeyManager`, and `Skinning/` rendering are deliberately out of scope (see `docs/superpowers/specs/2026-04-12-testing-design.md`). Test fixtures live in `WampTests/Fixtures/` (sample audio + cue files).

## Architecture

Pure Swift/Cocoa (AppKit) macOS audio player replicating classic Winamp 2.x. No SwiftUI, no storyboards, no XIBs — all UI is programmatic. Zero external dependencies; uses only Apple frameworks (AVFoundation, Combine, Accelerate, MediaPlayer).

### Project Structure

```
Wamp/
├── AppDelegate.swift        — nib-less bootstrap (static func main()), owns singletons & window
├── Audio/
│   └── AudioEngine.swift    — AVAudioEngine graph: PlayerNode → 10-band EQ → Mixer → Output
├── CueSheet/
│   ├── CueSheet.swift           — model: tracks, INDEX positions, encoding metadata
│   ├── CueSheetParser.swift     — parses external `.cue` files
│   ├── CueDecoder.swift         — encoding detection (UTF-8, Shift-JIS, CP-1251, CP-1252)
│   ├── FlacCueExtractor.swift   — pulls embedded CUESHEET from FLAC Vorbis comments
│   └── CueResolver.swift        — expands a cue into virtual `Track`s pointing at the same file
├── Models/
│   ├── PlaylistManager.swift — track list, current index, shuffle, repeat, auto-advance
│   ├── StateManager.swift    — JSON persistence to ~/Library/Application Support/Wamp/
│   ├── Track.swift              — audio file model with metadata parsing via AVURLAsset
│   ├── M3UParser.swift          — `.m3u` / `.m3u8` parser (EXTM3U/EXTINF, BOM, CRLF, Latin-1 vs UTF-8)
│   ├── JumpFilter.swift         — pure prefix → word-boundary → substring ranking for Jump-to-File
│   ├── ITunesLibraryXML.swift   — parser for `iTunes Music Library.xml` exports
│   └── AppleMusicLibrarySource.swift — `ITLibrary`-backed Music.app library reader
├── Skinning/
│   ├── SkinManager.swift        — atomic skin lifecycle (load / unload / publish)
│   ├── SkinModel.swift          — parsed skin (sprites, regions, colors, viscolors)
│   ├── SkinParser.swift + helpers — `.wsz` ZIP unpacking, `IniParser`, `RegionParser`,
│   │                                `ViscolorsParser`, `EqGraphColorsParser`, `PlaylistStyleParser`
│   ├── SpriteCatalog.swift      — sprite slicing from `main.bmp`, `cbuttons.bmp`, etc.
│   ├── TextSpriteRenderer.swift — bitmap-font text rendering from `text.bmp` / `nums.bmp`
│   ├── SkinProvider.swift       — protocol + `BuiltInSkin` fallback (no skin loaded)
│   └── WinampClassicSkin.swift  — `SkinProvider` impl backed by a parsed `SkinModel`
├── UI/
│   ├── MainWindow.swift      — fixed-width (275px) borderless window with Double-Size scaling
│   ├── MainPlayerView.swift  — time display, volume/balance sliders, transport controls
│   ├── EqualizerView.swift   — 10-band EQ sliders + presets + EQ response curve
│   ├── PlaylistView.swift    — table with drag-drop, search, keyboard nav, double-click-to-play
│   ├── JumpToFileWindow.swift                — Cmd+J incremental search over the playlist
│   ├── ImportMusicLibraryWindowController.swift — sheet for picking Music.app sources to import
│   ├── WinampTheme.swift     — all design tokens (colors, sizes, fonts)
│   └── Components/
│       ├── TitleBarView.swift    — window title bar with pin/minimize/close buttons
│       ├── TransportBar.swift    — play/pause/stop/prev/next buttons
│       ├── LCDDisplay.swift      — retro LCD time display
│       ├── SevenSegmentView.swift — seven-segment digit renderer
│       ├── SpectrumView.swift    — real-time spectrum analyzer visualization
│       ├── EQResponseView.swift  — EQ frequency response curve
│       ├── PlayStateIndicator.swift — play/pause/stop glyph next to the LCD
│       ├── PlaylistSkinScroller.swift — custom NSScroller drawing the skinned thumb from `pledit.bmp`
│       ├── WinampButton.swift    — themed button component
│       └── WinampSlider.swift    — themed slider component
└── Utils/
    └── HotKeyManager.swift   — media keys (play/pause/next/prev) & Now Playing info
```

### Data Flow

`AppDelegate` owns the core singletons and wires them together (it also keeps `@main` plus an explicit `static func main()` — see Key Patterns):

- **AudioEngine** (`ObservableObject`) — playback, 10-band EQ, spectrum data (32 bins via Accelerate), volume/balance/mute
- **PlaylistManager** (`ObservableObject`) — track list, shuffle, repeat modes (off/track/playlist), auto-advance on track finish
- **StateManager** — debounced saves (500ms), auto-restores on launch: volume, EQ bands/preamp/preset, playlist, window position, repeat mode, always-on-top
- **SkinManager.shared** — loads `.wsz` skins, publishes the active `SkinProvider`; views observe and redraw on skin change

Views bind to models via **Combine** (`@Published` properties + `sink` subscriptions). State changes flow: User action → Model mutation → `@Published` fires → Views update.

### Window Layout

MainWindow stacks three panels vertically in a fixed 275px-wide borderless window:
- Player section: 126px height (title bar, LCD display, transport, volume/balance) — `WinampTheme.mainPlayerHeight`
- Equalizer: 112px height, togglable — `WinampTheme.equalizerHeight`
- Playlist: 232px minimum height (resizable)

View → Double Size (Cmd+Shift+D) scales the whole window via `WinampTheme.scale` — content bounds stay logical, the window's frame is the scaled size.

### Key Patterns

- **Nib-less bootstrap** — `AppDelegate` has an explicit `static func main()` because the default `@main` silently fails without a nib; `NSApp.setActivationPolicy(.regular)` is required
- **State persistence** — `AppState` and `EQState` are `Codable` structs saved as JSON; `StateManager` debounces writes
- **Track metadata** — `Track.fromURL(_:)` is `async` and uses `AVURLAsset` to load metadata (title, artist, album, genre, bitrate, sample rate, channels)
- **Spectrum analyzer** — AudioEngine installs a tap on the audio graph, uses Accelerate FFT for 32-bin spectrum data published via `@Published`
- **System tray** — `NSStatusItem` with menu for quick access
- **HotKeyManager** — handles media keys and publishes Now Playing info to Control Center via `MPNowPlayingInfoCenter`
- **WinampTheme** — centralizes all design tokens; retro palette uses grays, golds, and greens
- **CUE sheets** — external `.cue` next to a FLAC wins over an embedded CUESHEET; `CueResolver` produces virtual `Track`s sharing one underlying file. Gapless transitions between consecutive cue tracks rely on chained `AVAudioPlayerNode.scheduleSegment` calls in `AudioEngine`.
- **Music.app import** — `AppleMusicLibrarySource` uses `iTunesLibrary` (`ITLibrary`); falls back to parsing `~/Music/iTunes/iTunes Music Library.xml` when ITLibrary is unavailable. Streaming-only and missing-file tracks are skipped with counts surfaced in a summary alert.
- **Jump to File** — `JumpFilter` is pure (no UI deps), ranking prefix → word-boundary → substring; targets <16ms over 10k tracks. Window is presented from `AppDelegate` via Cmd+J.
- **Skinning** — `.wsz` is a ZIP of bitmap sprites + INI files. `SkinManager` parses atomically (parse fully off-main, then publish); `SkinProvider` abstracts "no skin" vs "classic skin" so views always have something to draw. `BuiltInSkin` is the fallback when no skin is loaded.

## Conventions

- Commit messages use conventional format: `feat:`, `fix:`, `chore:`, `style:`
- App sandbox is **disabled** (entitlements) to allow filesystem access and media key handling
- Supported audio formats: MP3, AAC, M4A, FLAC, WAV, AIFF, AIF (single source of truth: `Track.supportedExtensions`)
- Supported playlist formats: M3U, M3U8, CUE (external `.cue` and FLAC-embedded CUESHEET)
- All UI components are custom `NSView` subclasses — no Interface Builder usage
- Playlist supports drag-and-drop (files from Finder), keyboard navigation (arrows, Return to play), and search
- Non-goals (Spotify playback, Apple Music streaming, iCloud sync) are documented in `docs/non-goals.md` — read before proposing streaming features
- Changelog is `CHANGELOG.md` (Keep a Changelog format); add an `[Unreleased]` entry per user-visible change

## Workflow

- **Branching** — each task list starts on a `feature/<slug>` branch off `main`. If the user is on `main` when a list begins, create the branch first. Never commit a task list directly to `main`.
- **Commit granularity** — 1 task = 1 commit. Don't batch. The pre-commit hook (`.git/hooks/pre-commit`) handles build verification for Swift changes; doc-only commits skip the build.
- **TDD for Models/** — any change under `Wamp/Models/` follows red → green → commit using the `superpowers:test-driven-development` skill: write the failing test first, implement until green, commit test and code together.
- **Brainstorming** — use `superpowers:brainstorming` only when the task is genuinely ambiguous or requires design exploration. If the user provides a clear task list, skip brainstorming and get to work.
- **Subagents** — use parallel subagents when it genuinely saves time (large independent tasks). For small edits (renaming, color changes, single-file fixes), do the work directly in the main session. Don't create overhead that exceeds the task complexity.
- **End-of-list report** — after every task list, post a short report: (1) what was done, (2) non-obvious decisions taken mid-flight, (3) anything skipped and why. Wait for user approval before moving on. Do not request screenshots; the user provides them when they want visual feedback.
- **Session wrap-up** — when the user invokes `/wrap-session`: confirm the report, commit any pending work, ask for explicit approval, merge the feature branch into `main` with `--no-ff`, write `docs/superpowers/next-session.md`, print the prompt in chat, tell the user they can `/clear`.
