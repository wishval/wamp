# Testing Strategy — Design

**Date:** 2026-04-12
**Status:** Approved, ready for implementation plan

## Goal

Introduce a fast, deterministic test suite for Wamp that covers the valuable non-UI logic (models, persistence, metadata parsing) and integrate test execution into the existing development workflow without slowing down the per-commit loop.

## Scope

### In scope

- **`PlaylistManager`** — add/remove, `currentIndex` invariants after removal, shuffle (deterministic via injected RNG/seed), repeat modes (`off` / `track` / `playlist`) in `advance()`, auto-advance on track-finish, edge cases (empty playlist, single track).
- **`StateManager`** — `AppState` / `EQState` encode → decode round-trip equality, debounce behavior under a zero-interval test configuration, missing-file bootstrap, graceful fallback on corrupt JSON.
- **`Track`** — `Track.fromURL(_:)` returns correct `title` / `artist` / `album` / `duration` / `channels` / `sampleRate` from a fixture `.m4a`; unrecognized URL yields the expected failure mode.
- **Persistence round-trip integration** — single test that drives `PlaylistManager` + `StateManager(directory:)` through save → reload and asserts full state restoration.

### Out of scope (deliberate)

- `AudioEngine` — real `AVAudioEngine` + Accelerate FFT is flaky in CI; low ROI until a concrete bug appears.
- `NSView` / UI components — programmatic AppKit; snapshot tests produce noise, not signal.
- `HotKeyManager` — system media keys and `MPNowPlayingInfoCenter` are not cleanly isolatable.
- `AppDelegate` bootstrap — covered by launching the app manually.

Re-entry into these areas is allowed only when a specific bug surfaces that a test could have caught.

## Architecture

New Xcode unit-test target `WampTests` inside `Wamp.xcodeproj`, linked against the `Wamp` target via `@testable import Wamp`. Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`), requires Xcode 16+ — confirmed on Xcode 26.

### Directory layout

```
WampTests/
├── Models/
│   ├── PlaylistManagerTests.swift
│   ├── StateManagerTests.swift
│   └── TrackTests.swift
├── Integration/
│   └── PersistenceRoundTripTests.swift
└── Fixtures/
    └── sample.m4a          ← ~30 KB, known tags
```

### Run command

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp \
  -destination 'platform=macOS' test
```

## Production code changes

Minimal, targeted changes — no DI container, no protocol layering:

- **`StateManager`** gains an initializer accepting a directory:
  ```swift
  init(directory: URL = StateManager.defaultDirectory)
  ```
  where `defaultDirectory` is the current `~/Library/Application Support/Wamp/` path. Production callers (e.g., `AppDelegate`) keep using the default; tests pass `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`, created in test `setUp` and removed in `tearDown`.

- **`PlaylistManager` shuffle** — if the current implementation uses a non-injected RNG, expose a seed or `RandomNumberGenerator` parameter so shuffle can be asserted deterministically. Otherwise no change.

No other production code touches are required. `Track` and the rest of `PlaylistManager` are already testable as-is.

## Fixtures

One committed `.m4a` file (~30 KB, ≤1 sec of silence) with pre-written ID3/iTunes tags (`title`, `artist`, `album`, `genre`) located at `WampTests/Fixtures/sample.m4a`. The tag values are documented in `TrackTests.swift` as constants and asserted against. Generation steps for the fixture are documented in the implementation plan; the file itself is checked into git.

## Workflow integration

### TDD for models (per `superpowers:test-driven-development`)

Any new task in an implementation plan that changes logic under `Wamp/Models/` follows the red → green → commit cycle:
1. Write a failing test for the new behavior.
2. Implement until the test is green.
3. Commit test + code together (still "one task = one commit").

### Pre-commit hook — unchanged

`.git/hooks/pre-commit` continues to run `xcodebuild build` only. Tests are NOT added to the hook:
- tests would slow down every commit significantly,
- a slow hook creates pressure to bypass it,
- the merge-gate below is the right place to enforce green main.

### `/wrap-session` becomes the merge gate

`/wrap-session` runs `xcodebuild -scheme Wamp -destination 'platform=macOS' test` before performing the `git merge --no-ff` into `main`:
- red → merge is aborted, session stays open, the user is asked to fix.
- green → merge proceeds as today.

This guarantees `main` is always green while allowing feature branches to be temporarily red during an active TDD cycle.

### Documentation updates

- `CLAUDE.md` → `## Build & Run`: add the `xcodebuild test` command.
- `CLAUDE.md` → `## Workflow`: add sub-bullets for the TDD rule on `Models/` and the `/wrap-session` merge gate.
- `docs/superpowers/wrap-session.md` (and the corresponding slash command in `.claude/commands/`): add a "run tests before merge" step with fail-closed behavior.

## Non-goals

- No CI/CD setup. The test suite is local-only for now; CI can be added later without changing test code.
- No coverage reports / coverage gates.
- No mutation testing, property-based testing, or snapshot frameworks.
- No third-party test dependencies.

## Success criteria

- `xcodebuild ... test` runs green locally in under ~10 seconds.
- Tests are deterministic: zero flakiness across 10 consecutive runs.
- A deliberately introduced bug in `PlaylistManager.advance()` or `StateManager` round-trip is caught by the suite.
- `/wrap-session` refuses to merge a red branch.
