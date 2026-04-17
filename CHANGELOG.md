# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
