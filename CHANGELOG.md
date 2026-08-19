# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Downloadable DMG builds via GitHub Actions.** Pushing a `v*` tag now
  builds a Release arm64 app, packages it with `scripts/create-dmg.sh`
  and publishes a GitHub Release with `Wamp-<version>-macOS-arm64.dmg`
  attached. Every pull request and push to `main` builds the app and runs
  `WampTests`. The app is ad-hoc signed (not notarized) — release notes
  explain the one-time "Open Anyway" step.

- **App version comes from one place.** `MARKETING_VERSION` in the
  project drives `CFBundleShortVersionString` and the About panel
  (previously hard-coded in two places and out of sync); tagged CI
  builds stamp the version from the tag.

- **Mini-transport buttons in the skinned playlist are now interactive.**
  The five baked buttons (prev / play / pause / stop / next) in
  pledit.bmp's bottom-right corner now respond to clicks and route
  through the same `AudioEngine` + `PlaylistManager` calls as the main
  transport bar — including "load-and-play" when triggered from a
  stopped state. Same role they had in classic Winamp 2.x.

- **EJECT button in the playlist BR corner now opens "Play file…"** —
  the sixth baked button (the "▲" sprite) routes to the same
  `NSOpenPanel` as `File ▸ Open File…` / Cmd+O.

### Fixed

- **Loaded skin no longer forgotten after changing volume and quitting.**
  Debounced state saves rebuilt `state.json` from defaults, wiping
  `skinPath` (and window position fields) on every volume/EQ change.
  Saves now start from the persisted state.

- **UTF-8 `.m3u` playlists with non-ASCII paths now load.** Decoding
  tried Latin-1 first for `.m3u` — which succeeds for any bytes — so
  UTF-8 content turned into mojibake and tracks went missing. Strict
  UTF-8 is now tried first, then CP-1252, then Latin-1. Unencoded
  `file://` URLs (with spaces) resolve, and `http(s)://` stream entries
  are skipped instead of becoming bogus local paths.

- **Malformed CUE/skin files can no longer crash the app.** Huge minute
  values in `INDEX` timecodes and hostile `NumPoints` in a skin's
  `region.txt` hit integer-overflow traps; both now fail soft. CUE
  parse errors also report correct line numbers in CRLF files and point
  at the offending TRACK line.

- **Damaged or oversized skin archives load instead of failing.** One
  corrupt entry (bad CRC) aborted the whole `.wsz`; now it's skipped.
  Decompression is capped (32 MB/entry, 96 MB total) against zip bombs,
  and partially out-of-bounds sprites fall back to built-in drawing
  instead of stretching garbage.

- **Space works in the playlist search and Jump-to-File fields.** The
  Play/Pause menu item claimed bare Space as its key equivalent, which
  AppKit matches before text fields see the key — toggling playback
  mid-typing. Space still toggles playback when no text field is active.

- **Gapless CUE playback bookkeeping.** Seeking within a cue track left
  a stale queued segment record, derailing auto-advance (tracks were
  skipped while the wrong title showed); the elapsed-time display
  overcounted by a full track after every gapless transition; pausing,
  seeking, then resuming played past the cue track's end to EOF; and
  repeat-one on a cue track replayed the entire album file from 0:00.

- **EQ preamp survives volume and mute changes.** Volume/mute writes to
  the mixer dropped the preamp factor until the preamp slider was
  touched again.

- **Playlist edits while playing stay coherent.** Removing the playing
  track now hands playback to the track that slid into its slot (or
  stops at the end of the list) instead of leaving audio playing a
  removed file with the wrong row highlighted and a track skipped on
  advance. Clearing the playlist stops playback. Shuffle follows the
  exact playing entry (not the first duplicate of the same file), and a
  FLAC+cue inside a mixed batch no longer jumps ahead of files listed
  before it.

- **CUE sheets with absolute Windows/Unix `FILE` paths resolve** by
  falling back to the basename next to the `.cue`, matching
  Winamp/foobar2000 behavior.

- **Right-click in a filtered playlist targets the clicked row.** The
  context menu indexed the unfiltered model, so with an active search
  it acted on a different track. Jump-to-File likewise re-resolves its
  selection against the live playlist, so reordering/deleting tracks
  while the panel is open can't play the wrong entry.

- **Opening "Import from Music Library…" twice no longer wedges the
  sheet permanently;** the View-menu checkmarks for Show Equalizer /
  Show Playlist now track the actual panel state; the skinned playlist
  footer count/duration refreshes when tracks change.

- **Small fixes:** unskinned time display clamps at 99 minutes instead
  of dropping the leading digit past 100; double-click reset-to-center
  applies only to balance/EQ sliders (not seek/volume); the spectrum
  analyzer works after session restore and guards against tiny FFT
  buffers; `viscolor.txt` files with leading comments no longer shift
  the palette.

- **Recalibrate playlist mini-transport hit-rects to Webamp's 10×10
  spec.** The first wire-up used 22×18 rects which overlapped each
  other (clicking visible PLAY fired PREV, etc.) and missed the
  leftmost ~2 px of PREV outright. Rects now match
  `.playlist-action-buttons` from `webamp/css/playlist-window.css`
  verbatim — clicks land on the button under the cursor, including
  the previously-dead edges.



- **CUE sheets with CRLF line endings now parse correctly.** EAC and
  other Windows tools write CUEs with `\r\n` terminators. Swift treats
  `\r\n` as a single extended grapheme cluster, so a Character-level
  newline split never matched and the entire file collapsed into one
  "line", triggering `noTracks`. The parser now splits on Unicode
  scalars instead, so each `\r` and `\n` is treated independently.

- **Dropping a `.cue` (or `.m3u`/`.m3u8`) onto playlist rows now works.**
  The table view's drop handler routed external files through
  `PlaylistManager.addURLs` directly, which filters by
  `Track.supportedExtensions` (audio only) and silently dropped cue and
  m3u files. Drops on the empty area of the playlist already worked
  because they went through `AppDelegate.handleOpenURLs`. Both paths
  now share that single routing entry point, so cue sheets and m3u
  playlists are accepted regardless of where on the playlist the user
  releases them.

- **Skinned playlist's bottom mini-transport area no longer covers skin
  artwork.** The 97×13 rectangle painted over the mini-player buttons
  baked into pledit.bmp's bottom-right corner sprite has been removed.
  Any solid fill — black or pledit `Normal=` — clipped surrounding skin
  artwork on many skins, leaving a visible patch below the running-time
  LCD. The mini buttons are now shown as the artist drew them; they
  remain non-interactive (main-window transport is still the single
  source of truth), but the strip blends correctly with every skin.
  Unskinned mode is unchanged.

- **Skinned playlist now uses the skin's `pledit.txt` colors.** The row
  background and selection highlight were hardcoded to black and Wamp's
  built-in blue, hiding the `normalbg` and `selectedbg` values from the
  loaded skin. `WinampRowView` now reads `WinampTheme.provider.playlistStyle`
  when a skin is active, so Bento-style brown rows and skin-defined
  selection colors render correctly. Unskinned mode is unchanged.

### Changed

- **Multi-select in the playlist.** Standard macOS selection now works:
  Shift-click extends a contiguous range, Cmd-click toggles individual
  rows, and Cmd+A selects every track. Backspace removes the entire
  selection at once. Double-click-to-play is unaffected.

- **Angular playlist scroller in unskinned mode.** The native AppKit
  `.legacy` scrollbar's rounded corners clashed with the rest of Wamp's
  pixel-perfect chrome. A custom `AngularLegacyScroller` now draws a flat
  rectangular knob with a 1-px chiseled border using the existing button
  palette, so the scrollbar matches the frame. Skinned mode is unchanged —
  the sprite-based `PlaylistSkinScroller` overlay still draws on top.

- **Default Always-on-Top is now OFF for fresh installs.** Previous default
  pinned the player above other apps on first launch, which most users find
  intrusive. Existing users keep their last-session choice — only the
  initial default changed.

- **SF Symbol icons in the menu bar and corner popup.** Every menu item now
  carries a contextual SF Symbol — `playpause.fill` next to Play/Pause,
  `magnifyingglass` next to Jump to File, and so on. Faster visual scanning,
  consistent with macOS native apps.

- **Title-bar corner menu mirrors the menu bar.** The popup that appears when
  you click the top-left corner of the player is now built from the same
  factory as the menu bar, so it always carries the full action set —
  including Jump to File…, Import from Music Library…, and Select All.
  Previously the two menus were hand-rolled separately and drifted apart.

### Added

- **Import from Music Library** — new File → Import from Music Library…
  menu item opens a sheet listing "All Songs" plus your user and smart
  playlists from Music.app. Check the sources to import, pick "New
  playlist" or "Append to current", and Wamp pulls in every local track
  it can see. Streaming-only tracks (not downloaded) and entries whose
  files have been removed are skipped with counts in the summary
  alert. Backed by the `iTunesLibrary` framework; falls back to parsing
  `~/Music/iTunes/iTunes Music Library.xml` if it's been enabled. First
  use triggers the macOS permission prompt; a denied state offers a
  direct link to Privacy & Security → Media & Apple Music.

- **M3U / M3U8 playlists** — drop a `.m3u` or `.m3u8` on the player, open
  one via File → Open, or double-click from Finder to import its tracks.
  Present files are appended to the current playlist; missing entries are
  counted and surfaced in a summary alert so dead references don't silently
  disappear. Parser handles `#EXTM3U` / `#EXTINF` metadata, mixed
  CRLF/LF/CR line endings, UTF-8 BOM, and the Latin-1-vs-UTF-8 extension
  convention (`.m3u` → Latin-1, `.m3u8` → UTF-8).

- **Non-goals documented** — `docs/non-goals.md` explains why Wamp does
  not (and will not) stream Spotify or Apple Music catalog tracks: both
  route audio through a system-managed graph that bypasses our DSP, so
  EQ and spectrum wouldn't apply.

- **CUE sheet support** — drop a `.cue` on the player, or open a FLAC with an
  embedded `CUESHEET` Vorbis comment, to split one long audio file into
  individual virtual tracks in the playlist. External `.cue` next to a FLAC
  wins over an embedded CUESHEET. Playback transitions between consecutive
  cue tracks on the same file are gapless via chained `scheduleSegment` calls.
  Encoding detection handles UTF-8, Shift-JIS, CP-1251, and CP-1252 cues.
  Right-click a cue track → "Reveal Source File in Finder".
  ([feat/cue-sheets](docs/superpowers/plans/2026-04-17-cue-sheets.md))
- **Jump to file** — Cmd+J or Ctrl+J opens an incremental search dialog over
  the current playlist. Matches are ranked by prefix → word boundary →
  substring, with the currently-playing track pre-selected on open. Enter
  plays the selection, Esc closes. Targets <16ms response on 10k-track
  playlists. ([feat/jump-to-file](docs/superpowers/plans/2026-04-17-jump-to-file.md))
