<div align="center">

# 🦙 Wamp

### Classic Winamp 2.x, reborn as a native macOS app

No Electron. No web views. Just Swift, AppKit, and nostalgia.

<br/>

<img width="420" alt="Wamp playing in Double Size — then base-2.91 and Blue Plasma skins load live, and Cmd+J jumps to a track" src="docs/media/hero.gif" />

<br/>
<br/>

[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-26.3+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![UI](https://img.shields.io/badge/AppKit-100%25_programmatic-1d7dfa)](Wamp/UI)
[![Dependencies](https://img.shields.io/badge/dependencies-1_(zip_reader)-2ea44f)](#tech-stack)

</div>

---

## ✨ Highlights

- 🎨 **Real Winamp skins** — load any classic `.wsz` skin and the entire app reskins: sprites, bitmap fonts, playlist colors, visualizer palette
- 🔊 **Gapless CUE playback** — one FLAC + `.cue` becomes individual tracks with sample-accurate, gapless transitions
- 🎚 **10-band equalizer** with preamp, presets, and a live frequency-response curve
- 📊 **Real-time spectrum analyzer** — 32-bin FFT via Accelerate, skinnable via `viscolor.txt`
- ⚡ **Jump to File** — incremental search over 10k-track playlists in under 16 ms
- 🍎 **First-class macOS citizen** — media keys, Control Center "Now Playing", menu bar tray, full state restore

## 🎵 Player

- Classic transport — play, pause, stop, previous, next, seek
- Volume and balance sliders with real-time response
- Retro LCD time display with seven-segment digits and scrolling track title
- Double Size mode (`⌘⇧D`) — the whole window scales 2×, pixel-perfect
- Always-on-top pin (`⌘⇧T`) and a minimize-to-tray menu

## 🎨 Skins

Wamp parses the original Winamp 2.x skin format — a `.wsz` archive of bitmap
sprites and INI files — and renders it faithfully:

- `main.bmp`, `cbuttons.bmp`, `eqmain.bmp`, `pledit.bmp` sprite sheets
- Bitmap fonts from `text.bmp` / `nums.bmp` for the LCD and titles
- Playlist colors from `pledit.txt`, visualizer palette from `viscolor.txt`
- Interactive mini-transport baked into the skinned playlist corner — just like 1999
- Hardened loader: corrupt archive entries are skipped, decompression is capped
  against zip bombs, malformed `region.txt` fails soft
- Skins load atomically off the main thread; **Unload Skin** returns to the
  built-in look instantly

A few classics to try live in [`skins/`](skins): *base-2.91*, *Blue Plasma*,
*OS8 AMP — Aquamarine*, *Radar Amp*.

<div align="center">

<!-- PLACEHOLDER(skins-grid): 2×2 grid of screenshots — the same player wearing
     each of the four bundled skins (base-2.91, Blue Plasma, OS8 AMP Aquamarine,
     Radar_Amp). Equal sizes, ~400px wide each, captioned with the skin name. -->
> 🖼️ *Skins showcase coming soon — same player, four very different outfits.*

</div>

## 📜 Playlist

- Drag & drop files, folders, `.m3u`/`.m3u8` and `.cue` straight from Finder
- Multi-select like a real Mac app — Shift-click ranges, Cmd-click toggles, `⌘A`, Backspace removes
- Instant search box + **Jump to File** (`⌘J`) with prefix → word-boundary → substring ranking
- Shuffle and repeat (off / track / playlist) with auto-advance
- **Import from Music Library…** — pulls local tracks and playlists from Music.app
  (via `ITLibrary`, with an `iTunes Music Library.xml` fallback); streaming-only and
  missing files are skipped and counted
- Skinned scrollbar, skin-correct row colors, live track-count/duration footer

<!-- PLACEHOLDER(jump-gif): short GIF — Cmd+J opens Jump to File over a large
     playlist, a few characters are typed, results re-rank instantly,
     Enter plays the match. ~6s. -->

## 💿 CUE sheets, done properly

Drop a `.cue` next to a FLAC (or open a FLAC with an embedded `CUESHEET`
Vorbis comment) and the album splits into individual virtual tracks:

- Gapless transitions between consecutive tracks via chained `scheduleSegment` calls
- External `.cue` wins over embedded CUESHEET
- Encoding detection: UTF-8, Shift-JIS, CP-1251, CP-1252
- Absolute Windows/Unix `FILE` paths resolve by basename — same behavior as foobar2000
- CRLF files, hostile timecodes, and malformed input all fail soft, never crash

## ⌨️ Keyboard shortcuts

| Playback | | View | |
|---|---|---|---|
| `Space` | Play / Pause | `⌘1` | Show Player |
| `⌘.` | Stop | `⌘2` | Toggle Equalizer |
| `⌘→` / `⌘←` | Next / Previous | `⌘3` | Toggle Playlist |
| `⌘R` | Repeat | `⌘⇧D` | Double Size |
| `⌘S` | Shuffle | `⌘⇧T` | Always on Top |
| `Return` | Play selected track | `⌘⇧S` | Load Skin… |
| `↑` `↓` | Navigate playlist | `⌘O` / `⌘⇧O` | Open File / Folder |
| `⌘J` | Jump to File… | `⌘A` | Select All |

Plus hardware **media keys** (play/pause, next, previous) and the macOS
**Now Playing** widget in Control Center.

## 📦 Supported formats

| Audio | Playlists |
|---|---|
| MP3 · AAC · M4A · FLAC · WAV · AIFF | M3U · M3U8 · CUE (external & FLAC-embedded) |

## 🚀 Getting started

### Download

Grab the latest `Wamp-<version>-macOS-arm64.dmg` from
[**Releases**](https://github.com/wishval/wamp/releases), open it and drag
Wamp to Applications. Requires macOS 26.3+ on Apple Silicon.

The app is ad-hoc signed, not notarized, so the first launch is blocked with
*"Apple could not verify Wamp is free of malware"*. Click **Done**, then go to
**System Settings → Privacy & Security** and click **Open Anyway** — once.
Terminal alternative:

```bash
xattr -dr com.apple.quarantine /Applications/Wamp.app
```

### Build from source

**Requirements:** macOS 26.3+, Xcode 26+

```bash
git clone https://github.com/wishval/wamp.git
cd wamp

# Build
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build

# Or just open in Xcode and hit ⌘R
open Wamp.xcodeproj
```

Run the tests (they cover the models, CUE parsing, and persistence):

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test
```

### Cutting a release

CI ([`.github/workflows/build.yml`](.github/workflows/build.yml)) builds and
tests every PR and push to `main`. To publish a DMG, push a version tag:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

The `release` job stamps the version from the tag, builds Release for arm64,
runs `scripts/create-dmg.sh`, and creates a GitHub Release with the DMG
attached. To package locally: build Release into `.build/DerivedData`, then
`scripts/create-dmg.sh <version>`.

## 🛠 Tech stack

| | |
|---|---|
| **Language** | Swift 5 |
| **UI** | AppKit — 100% programmatic, no storyboards, no XIBs |
| **Audio** | AVFoundation / `AVAudioEngine` |
| **DSP** | Accelerate (vDSP FFT for the spectrum analyzer) |
| **Media keys** | MediaPlayer (`MPNowPlayingInfoCenter`) |
| **State** | Combine + debounced JSON persistence |
| **Dependencies** | One: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) to unpack `.wsz` skins. Everything else is Apple frameworks. |

## 🏗 Architecture

```
AppDelegate  (nib-less bootstrap, owns the singletons)
├── AudioEngine        PlayerNode → 10-band EQ → Mixer → Output, FFT tap
├── PlaylistManager    track list, shuffle, repeat, auto-advance
├── StateManager       debounced JSON persistence, restores on launch
├── SkinManager        atomic .wsz load → publishes a SkinProvider
│   └── SkinModel      sprites, regions, colors, bitmap fonts
├── CueSheet           parser + encoding detection + FLAC extractor
│   └── CueResolver    expands a cue into virtual Tracks
└── MainWindow         275px-wide borderless stack
    ├── MainPlayerView     LCD, transport, sliders, spectrum
    ├── EqualizerView      10 bands + presets + response curve
    └── PlaylistView       drag-drop, search, keyboard nav
```

Views bind to models through **Combine** — `@Published` fires, views redraw.
No delegates, no notification spaghetti.

## 🙅 Non-goals

Wamp is a **local** player. It will not stream Spotify or Apple Music catalog
tracks — both route audio through a system-managed graph that bypasses our DSP,
so the EQ and spectrum analyzer would be lying to you. Details in
[docs/non-goals.md](docs/non-goals.md).

---

<div align="center">

Made with nostalgia and Swift on macOS.

*Inspired by Winamp 2.x. An independent project, not affiliated with or
endorsed by the original Winamp authors. Skins in `skins/` belong to their
original artists.*

🦙

</div>
