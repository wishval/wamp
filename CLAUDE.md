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

### Project Structure

```
WinampMac/
├── AppDelegate.swift        — nib-less bootstrap (static func main()), owns singletons & window
├── Audio/
│   └── AudioEngine.swift    — AVAudioEngine graph: PlayerNode → 10-band EQ → Mixer → Output
├── Models/
│   ├── PlaylistManager.swift — track list, current index, shuffle, repeat, auto-advance
│   ├── StateManager.swift    — JSON persistence to ~/Library/Application Support/WinampMac/
│   └── Track.swift           — audio file model with metadata parsing via AVURLAsset
├── UI/
│   ├── MainWindow.swift      — fixed-width (275px) borderless window
│   ├── MainPlayerView.swift  — time display, volume/balance sliders, transport controls
│   ├── EqualizerView.swift   — 10-band EQ sliders + presets + EQ response curve
│   ├── PlaylistView.swift    — table with drag-drop, search, keyboard nav, double-click-to-play
│   ├── WinampTheme.swift     — all design tokens (colors, sizes, fonts)
│   └── Components/
│       ├── TitleBarView.swift    — window title bar with pin/minimize/close buttons
│       ├── TransportBar.swift    — play/pause/stop/prev/next buttons
│       ├── LCDDisplay.swift      — retro LCD time display
│       ├── SevenSegmentView.swift — seven-segment digit renderer
│       ├── SpectrumView.swift    — real-time spectrum analyzer visualization
│       ├── EQResponseView.swift  — EQ frequency response curve
│       ├── WinampButton.swift    — themed button component
│       └── WinampSlider.swift    — themed slider component
└── Utils/
    └── HotKeyManager.swift   — media keys (play/pause/next/prev) & Now Playing info
```

### Data Flow

`AppDelegate` owns the core singletons and wires them together:

- **AudioEngine** (`ObservableObject`) — playback, 10-band EQ, spectrum data (32 bins via Accelerate), volume/balance/mute
- **PlaylistManager** (`ObservableObject`) — track list, shuffle, repeat modes (off/track/playlist), auto-advance on track finish
- **StateManager** — debounced saves (500ms), auto-restores on launch: volume, EQ bands/preamp/preset, playlist, window position, repeat mode, always-on-top

Views bind to models via **Combine** (`@Published` properties + `sink` subscriptions). State changes flow: User action → Model mutation → `@Published` fires → Views update.

### Window Layout

MainWindow stacks three panels vertically in a fixed 275px-wide borderless window:
- Player section: 148px height (title bar, LCD display, transport, volume/balance)
- Equalizer: 130px height (togglable)
- Playlist: 232px minimum height (resizable)

### Key Patterns

- **Nib-less bootstrap** — `AppDelegate` has an explicit `static func main()` because the default `@main` silently fails without a nib; `NSApp.setActivationPolicy(.regular)` is required
- **State persistence** — `AppState` and `EQState` are `Codable` structs saved as JSON; `StateManager` debounces writes
- **Track metadata** — `Track.fromURL(_:)` is `async` and uses `AVURLAsset` to load metadata (title, artist, album, genre, bitrate, sample rate, channels)
- **Spectrum analyzer** — AudioEngine installs a tap on the audio graph, uses Accelerate FFT for 32-bin spectrum data published via `@Published`
- **System tray** — `NSStatusItem` with menu for quick access
- **HotKeyManager** — handles media keys and publishes Now Playing info to Control Center via `MPNowPlayingInfoCenter`
- **WinampTheme** — centralizes all design tokens; retro palette uses grays, golds, and greens

## Conventions

- Commit messages use conventional format: `feat:`, `fix:`, `chore:`, `style:`
- App sandbox is **disabled** (entitlements) to allow filesystem access and media key handling
- Supported audio formats: MP3, AAC, M4A, FLAC, WAV, AIFF, AIF
- All UI components are custom `NSView` subclasses — no Interface Builder usage
- Playlist supports drag-and-drop (files from Finder), keyboard navigation (arrows, Return to play), and search
