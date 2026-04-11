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

No linter and no CI/CD are configured. Tests cover `Models/` and a persistence round-trip only — `AudioEngine`, UI views, and `HotKeyManager` are deliberately out of scope (see `docs/superpowers/specs/2026-04-12-testing-design.md`).

## Architecture

Pure Swift/Cocoa (AppKit) macOS audio player replicating classic Winamp 2.x. No SwiftUI, no storyboards, no XIBs — all UI is programmatic. Zero external dependencies; uses only Apple frameworks (AVFoundation, Combine, Accelerate, MediaPlayer).

### Project Structure

```
Wamp/
├── AppDelegate.swift        — nib-less bootstrap (static func main()), owns singletons & window
├── Audio/
│   └── AudioEngine.swift    — AVAudioEngine graph: PlayerNode → 10-band EQ → Mixer → Output
├── Models/
│   ├── PlaylistManager.swift — track list, current index, shuffle, repeat, auto-advance
│   ├── StateManager.swift    — JSON persistence to ~/Library/Application Support/Wamp/
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

## Workflow

- **Multi-task requests (2+ items)** — start with `superpowers:brainstorming`. Save the resulting plan under `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` before writing code.
- **Branching** — each task list starts on a `feature/<slug>` branch off `main`. If the user is on `main` when a list begins, create the branch first. Never commit a task list directly to `main`.
- **Commit granularity** — 1 task = 1 commit. Don't batch. The pre-commit hook (`.git/hooks/pre-commit`) handles build verification for Swift changes; doc-only commits skip the build.
- **TDD for Models/** — any change under `Wamp/Models/` follows red → green → commit using the `superpowers:test-driven-development` skill: write the failing test first, implement until green, commit test and code together.
- **Test merge gate** — `/wrap-session` runs `xcodebuild ... test` before merging a feature branch. Red tests abort the merge; the session stays open until the suite is green.
- **Subagent policy** — dispatch independent tasks to parallel subagents (opus for architectural/complex work, sonnet for mechanical edits). Sequential or single tasks stay in the main session. Code exploration and search always go to the `Explore` subagent.
- **Opus reviews sonnet** — when a sonnet subagent returns, the main (opus) session reviews its diff before marking the task complete. If issues are found, fix them inline in the main session rather than re-dispatching to sonnet.
- **End-of-list report** — after every task list, post a short report: (1) what was done, (2) non-obvious decisions taken mid-flight, (3) anything skipped and why. Wait for user approval before moving on. Do not request screenshots; the user provides them when they want visual feedback.
- **Session wrap-up** — when the user invokes `/wrap-session`: confirm the report, commit any pending work, ask for explicit approval, merge the feature branch into `main` with `--no-ff`, write `docs/superpowers/next-session.md` with a starter prompt, print the same prompt in chat, and tell the user they can now `/clear`.
