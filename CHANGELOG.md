# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Jump to file** — Cmd+J or Ctrl+J opens an incremental search dialog over
  the current playlist. Matches are ranked by prefix → word boundary →
  substring, with the currently-playing track pre-selected on open. Enter
  plays the selection, Esc closes. Targets <16ms response on 10k-track
  playlists. ([feat/jump-to-file](docs/superpowers/plans/2026-04-17-jump-to-file.md))
