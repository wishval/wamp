# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a macOS app built with Xcode. Open `WinampMac.xcodeproj` and build/run from Xcode, or use:

```bash
xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build
```

There are no tests, no linter, and no CI/CD configured.

## Architecture

Pure Swift/Cocoa (AppKit) macOS audio player replicating classic Winamp 2.x. No SwiftUI, no storyboards, no XIBs — all UI is programmatic. Zero external dependencies; uses only Apple frameworks (AVFoundation, Combine, Accelerate, MediaPlayer).

### Data Flow

`AppDelegate` owns the three core singletons and the window:

```
AppDelegate
├── AudioEngine      — AVAudioEngine graph: PlayerNode → 10-band EQ → Mixer → Output
├── PlaylistManager  — track list, current index, shuffle, repeat, auto-advance
├── StateManager     — JSON persistence to ~/Library/Application Support/WinampMac/
└── MainWindow       — fixed-width (275px) borderless window
    ├── MainPlayerView   — time display, volume/balance sliders, transport controls
    ├── EqualizerView    — 10-band EQ sliders + presets
    └── PlaylistView     — table with drag-drop, search, double-click-to-play
```

Views bind to models via **Combine** (`@Published` properties + `sink` subscriptions). State changes flow: User action → Model mutation → `@Published` fires → Views update.

### Key Patterns

- **StateManager** debounces saves (500ms) and auto-restores on launch — volume, EQ, playlist, window position, repeat mode
- **AudioEngine** provides real-time spectrum data (32 bins via Accelerate) through a tap on the audio graph
- **HotKeyManager** handles media keys (play/pause/next/prev) and publishes Now Playing info to Control Center
- **WinampTheme** centralizes all design tokens (colors, sizes, fonts) — the retro palette uses grays, golds, and greens

### Window Layout

MainWindow stacks three panels vertically in a fixed 275px-wide borderless window:
- Player section: 148px height
- Equalizer: 130px height (togglable)
- Playlist: 232px minimum height (resizable)

## Conventions

- Commit messages use conventional format: `feat:`, `fix:`, `chore:`
- App sandbox is **disabled** (entitlements) to allow filesystem access and media key handling
- Supported audio formats: MP3, AAC, M4A, FLAC, WAV, AIFF
