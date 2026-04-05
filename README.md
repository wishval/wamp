<div align="center">

# WinampMac

### It really whips the llama's ass! 🦙

A faithful recreation of the legendary **Winamp 2.x** for macOS — built entirely with Swift and AppKit.

No Electron. No web views. No dependencies. Just pure native macOS.

<!--
Add a screenshot here:
![WinampMac Screenshot](screenshots/preview.png)
-->

[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Features

**Player**
- Classic transport controls — play, pause, stop, previous, next
- Volume and balance sliders with real-time response
- Retro LCD time display with seven-segment digits
- Real-time spectrum analyzer visualization
- Scrolling track title in the classic Winamp style

**10-Band Equalizer**
- Fully adjustable EQ with preamp control
- Live frequency response curve
- Built-in presets (Rock, Pop, Jazz, Classical, and more)
- Toggle on/off without losing settings

**Playlist**
- Drag & drop files directly from Finder
- Keyboard navigation — arrow keys to browse, Return to play
- Search through your library instantly
- Shuffle and repeat modes (off / track / playlist)
- Supports MP3, AAC, M4A, FLAC, WAV, and AIFF

**System Integration**
- Media key support — play/pause, next, previous from your keyboard
- Now Playing integration with macOS Control Center
- System tray menu for quick access
- Always-on-top (pin) window mode
- Full state persistence — picks up right where you left off

## Tech Stack

| | |
|---|---|
| **Language** | Swift 5 |
| **UI Framework** | AppKit (100% programmatic, zero XIBs) |
| **Audio** | AVFoundation + AVAudioEngine |
| **DSP** | Accelerate (FFT for spectrum analysis) |
| **Media Keys** | MediaPlayer framework |
| **State** | Combine + JSON persistence |
| **Dependencies** | None. Zero. Nada. |

## Architecture

```
AppDelegate
├── AudioEngine          PlayerNode → 10-Band EQ → Mixer → Output
├── PlaylistManager      Track list, shuffle, repeat, auto-advance
├── StateManager         JSON persistence with debounced saves
└── MainWindow           275px fixed-width borderless window
    ├── MainPlayerView       LCD display, transport, sliders
    ├── EqualizerView        10-band EQ + response curve
    └── PlaylistView         Scrollable table with drag-drop
```

Views subscribe to model changes via **Combine** publishers — no delegates, no notification spaghetti.

## Getting Started

### Requirements

- macOS 14.0+
- Xcode 15+

### Build & Run

```bash
# Clone the repo
git clone https://github.com/yourusername/WinampMac.git
cd WinampMac

# Build from command line
xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build

# Or just open in Xcode and hit ⌘R
open WinampMac.xcodeproj
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Play / Pause |
| `Return` | Play selected track |
| `↑` `↓` | Navigate playlist |
| `⌘Q` | Quit |
| Media Keys | Play / Pause / Next / Previous |

## Supported Formats

MP3 | AAC | M4A | FLAC | WAV | AIFF

---

<div align="center">

Made with nostalgia and Swift on macOS.

*Winamp is a trademark of Radionomy Group. This project is an independent fan recreation and is not affiliated with or endorsed by the original Winamp.*

</div>
