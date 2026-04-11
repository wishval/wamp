# Testing Strategy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a deterministic Swift Testing suite for Wamp covering `PlaylistManager`, `StateManager`, `Track`, and a persistence round-trip, and integrate execution into the existing TDD + `/wrap-session` workflow.

**Architecture:** New `WampTests` unit-test target inside `Wamp.xcodeproj`, using Swift Testing (`import Testing`). `@testable import Wamp`. Tests target models only — no AudioEngine, no UI. A single `.m4a` fixture is committed to `WampTests/Fixtures/` and generated once via a one-off Swift script. One small production-code change: `StateManager` gains a designated initializer accepting a custom directory so tests can run in `FileManager.default.temporaryDirectory` without touching `~/Library/Application Support/Wamp/`.

**Tech Stack:** Swift 6 / Xcode 26, Swift Testing framework, AppKit, AVFoundation, Combine, `xcodebuild` for test runs.

**Spec:** `docs/superpowers/specs/2026-04-12-testing-design.md`

---

## File Structure

**Created:**
- `WampTests/Models/PlaylistManagerTests.swift`
- `WampTests/Models/StateManagerTests.swift`
- `WampTests/Models/TrackTests.swift`
- `WampTests/Integration/PersistenceRoundTripTests.swift`
- `WampTests/Fixtures/sample.m4a` (binary, ~30 KB)
- `WampTests/Fixtures/generate-sample.swift` (one-off generator, not compiled by the target)

**Modified:**
- `Wamp/Models/StateManager.swift` — add `init(directory:)` designated init; add `saveEQState(_ state: EQState)` overload
- `Wamp.xcodeproj/project.pbxproj` — new `WampTests` unit-test target (done via Xcode UI)
- `CLAUDE.md` — new `xcodebuild test` command in Build & Run; new Workflow bullets
- `docs/superpowers/wrap-session.md` — add test run as merge gate
- `.claude/commands/wrap-session.*` — mirror merge-gate step (if slash command file exists)

---

### Task 1: Create WampTests target in Xcode

**Files:**
- Modify: `Wamp.xcodeproj/project.pbxproj` (via Xcode UI)

This is a manual user step — Xcode target creation via raw `pbxproj` editing is error-prone and unnecessary. Claude should pause and ask the user to perform it.

- [ ] **Step 1: Ask the user to create the target in Xcode**

Claude prints instructions and waits:

```
Please open Wamp.xcodeproj in Xcode and do the following:

1. File → New → Target…
2. Choose macOS → Unit Testing Bundle → Next
3. Product Name: WampTests
4. Language: Swift
5. Testing System: Swift Testing
6. Target to be Tested: Wamp
7. Finish.
8. Select the WampTests target → Build Phases → Compile Sources:
   confirm only the placeholder test file Xcode created is present.
9. Close Xcode.

Reply "done" when finished.
```

- [ ] **Step 2: Verify the target exists**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -list | grep -A 20 Targets
```
Expected: output includes `WampTests`.

- [ ] **Step 3: Delete the Xcode-generated placeholder test file**

Find and remove the placeholder:
```bash
find WampTests -name '*.swift' -not -path '*/Fixtures/*'
```
Delete any file Xcode created (typically `WampTests/WampTests.swift`). Remove it from the project via Xcode (Right-click → Delete → Move to Trash) **before** this step if it was added to the Compile Sources phase. If the file is only on disk (not in pbxproj), `rm` is enough.

Alternatively, keep it empty by overwriting with:
```swift
import Testing
```

- [ ] **Step 4: Run the empty test bundle to confirm it builds**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` (zero tests executed is OK).

- [ ] **Step 5: Commit**

```bash
git add Wamp.xcodeproj/project.pbxproj WampTests/
git commit -m "chore: add WampTests target (Swift Testing)"
```

---

### Task 2: Add `StateManager(directory:)` initializer

**Files:**
- Modify: `Wamp/Models/StateManager.swift:26-35`

Currently `StateManager.init()` hard-codes `appSupportDir` to `~/Library/Application Support/Wamp/`. We extract the default path as a static helper and add an initializer accepting an override directory. Production callers (e.g., `AppDelegate`) keep using the parameterless init which now forwards to the new one.

- [ ] **Step 1: Replace the initializer**

Replace lines 26–35 of `Wamp/Models/StateManager.swift`:

```swift
class StateManager {
    private let appSupportDir: URL
    private var cancellables = Set<AnyCancellable>()
    private var saveWorkItem: DispatchWorkItem?

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Wamp")
    }

    init(directory: URL = StateManager.defaultDirectory) {
        appSupportDir = directory
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }
```

- [ ] **Step 2: Build to confirm the change compiles**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Wamp/Models/StateManager.swift
git commit -m "feat: inject StateManager directory for testability"
```

---

### Task 3: Add pure-state `saveEQState(_:)` overload

**Files:**
- Modify: `Wamp/Models/StateManager.swift` (after line 81)

The existing `saveEQState(audioEngine:presetName:autoMode:)` pulls values off an `AudioEngine`, which we don't want to construct in tests. Add an overload that accepts a pre-built `EQState`.

- [ ] **Step 1: Add the overload**

Insert after the existing `saveEQState(audioEngine:...)` method (around line 81):

```swift
    func saveEQState(_ state: EQState) {
        write(state, to: "equalizer.json")
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Wamp/Models/StateManager.swift
git commit -m "feat: add pure-state saveEQState overload"
```

---

### Task 4: Generate and commit `sample.m4a` fixture

**Files:**
- Create: `WampTests/Fixtures/generate-sample.swift`
- Create: `WampTests/Fixtures/sample.m4a` (binary, committed)

The fixture is a ~0.5 sec silent AAC-encoded `.m4a` with known metadata tags. Generation uses `AVAssetWriter` via a one-off script; the resulting binary is committed. The script stays in the repo as documentation of how the file was produced.

- [ ] **Step 1: Write the generator script**

Create `WampTests/Fixtures/generate-sample.swift`:

```swift
#!/usr/bin/env swift
// One-off: regenerates WampTests/Fixtures/sample.m4a.
// Run: swift WampTests/Fixtures/generate-sample.swift
import Foundation
import AVFoundation

let outURL = URL(fileURLWithPath: "WampTests/Fixtures/sample.m4a")
try? FileManager.default.removeItem(at: outURL)

let writer = try AVAssetWriter(outputURL: outURL, fileType: .m4a)

let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 44_100,
    AVNumberOfChannelsKey: 2,
    AVEncoderBitRateKey: 64_000
]
let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
input.expectsMediaDataInRealTime = false
writer.add(input)

func meta(_ key: AVMetadataKey, _ value: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = .common
    item.key = key as NSString
    item.value = value as NSString
    return item
}
writer.metadata = [
    meta(.commonKeyTitle, "Wamp Fixture Title"),
    meta(.commonKeyArtist, "Wamp Fixture Artist"),
    meta(.commonKeyAlbumName, "Wamp Fixture Album"),
    meta(.commonKeyType, "Electronic")
]

writer.startWriting()
writer.startSession(atSourceTime: .zero)

let sampleRate: Double = 44_100
let durationSeconds: Double = 0.5
let totalFrames = Int(sampleRate * durationSeconds)
let framesPerBuffer = 1024

let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
var written = 0
while written < totalFrames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
    let frames = min(framesPerBuffer, totalFrames - written)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    // Silence: leave zero-filled.
    guard let sampleBuffer = buffer.toCMSampleBuffer(presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(sampleRate))) else {
        fatalError("sample buffer conversion failed")
    }
    input.append(sampleBuffer)
    written += frames
}
input.markAsFinished()

let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("Wrote: \(outURL.path) — status=\(writer.status.rawValue)")

// Helper: AVAudioPCMBuffer → CMSampleBuffer
extension AVAudioPCMBuffer {
    func toCMSampleBuffer(presentationTimeStamp pts: CMTime) -> CMSampleBuffer? {
        var asbd = self.format.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(self.format.sampleRate)),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                   dataBuffer: nil,
                                   dataReady: false,
                                   makeDataReadyCallback: nil,
                                   refcon: nil,
                                   formatDescription: formatDescription,
                                   sampleCount: CMItemCount(self.frameLength),
                                   sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0,
                                   sampleSizeArray: nil,
                                   sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: self.audioBufferList) == noErr else { return nil }
        return sampleBuffer
    }
}
```

- [ ] **Step 2: Run the generator**

Run:
```bash
swift WampTests/Fixtures/generate-sample.swift
```
Expected: stdout ends with `status=2` (`AVAssetWriterStatusCompleted`), file `WampTests/Fixtures/sample.m4a` exists.

- [ ] **Step 3: Verify the fixture**

Run:
```bash
ls -lh WampTests/Fixtures/sample.m4a && \
  afinfo WampTests/Fixtures/sample.m4a | grep -E 'format|duration|channels|bit rate|Title|Artist|Album'
```
Expected: duration ~0.5s, 2 channels, AAC, and metadata shows `Title: Wamp Fixture Title`, `Artist: Wamp Fixture Artist`, `Album: Wamp Fixture Album`.

If metadata tags are missing (AVAssetWriter sometimes ignores `commonKey` on m4a), stop and switch to `.iTunesMetadataKeySongName` / `.iTunesMetadataKeyArtist` / `.iTunesMetadataKeyAlbum` / `.iTunesMetadataKeyUserGenre` with `keySpace = .iTunes`, re-run Step 2, re-verify.

- [ ] **Step 4: Add fixture to WampTests target resources**

In Xcode: drag `WampTests/Fixtures/sample.m4a` into the Project navigator under the `WampTests` group → add to the `WampTests` target → under Build Phases → Copy Bundle Resources, confirm `sample.m4a` is listed.

- [ ] **Step 5: Commit**

```bash
git add WampTests/Fixtures/generate-sample.swift WampTests/Fixtures/sample.m4a Wamp.xcodeproj/project.pbxproj
git commit -m "test: add sample.m4a fixture with known metadata tags"
```

---

### Task 5: Write `PlaylistManagerTests`

**Files:**
- Create: `WampTests/Models/PlaylistManagerTests.swift`

Tests use hand-built `Track` values (via the struct's plain initializer) — no audio engine, no fixture. They cover: add/remove index adjustment, clear, move, navigation via `playNext` / `playPrevious` (without an audio engine, `currentIndex` still advances), and `advanceToNext` triggered via `NotificationCenter`.

- [ ] **Step 1: Write all failing tests at once**

Create `WampTests/Models/PlaylistManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("PlaylistManager")
struct PlaylistManagerTests {

    private func makeTrack(_ name: String, duration: TimeInterval = 10) -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/\(name).m4a"),
            title: name,
            artist: "A",
            album: "Alb",
            duration: duration
        )
    }

    @Test func addTracks_appends() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b")])
        #expect(pm.tracks.count == 2)
        #expect(pm.currentIndex == -1)
    }

    @Test func removeTrack_beforeCurrent_decrementsIndex() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 2
        pm.removeTrack(at: 0)
        #expect(pm.tracks.count == 2)
        #expect(pm.currentIndex == 1)
    }

    @Test func removeTrack_atCurrent_clampsIndex() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 2
        pm.removeTrack(at: 2)
        #expect(pm.currentIndex == 1)
    }

    @Test func removeTrack_lastRemaining_setsIndexMinusOne() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a")])
        pm.currentIndex = 0
        pm.removeTrack(at: 0)
        #expect(pm.tracks.isEmpty)
        #expect(pm.currentIndex == -1)
    }

    @Test func removeTrack_afterCurrent_leavesIndex() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 0
        pm.removeTrack(at: 2)
        #expect(pm.currentIndex == 0)
    }

    @Test func clearPlaylist_resets() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b")])
        pm.currentIndex = 1
        pm.clearPlaylist()
        #expect(pm.tracks.isEmpty)
        #expect(pm.currentIndex == -1)
    }

    @Test func moveTracks_preservesCurrentTrack() {
        let pm = PlaylistManager()
        let tracks = [makeTrack("a"), makeTrack("b"), makeTrack("c")]
        pm.addTracks(tracks)
        pm.currentIndex = 1  // "b"
        pm.moveTracks(from: IndexSet(integer: 0), to: 3)
        #expect(pm.tracks.map(\.title) == ["b", "c", "a"])
        #expect(pm.currentIndex == 0)
    }

    @Test func shuffleTracks_preservesCurrentTrackAndCount() {
        let pm = PlaylistManager()
        let tracks = (0..<20).map { makeTrack("t\($0)") }
        pm.addTracks(tracks)
        pm.currentIndex = 5
        let currentBefore = pm.tracks[pm.currentIndex]
        pm.shuffleTracks()
        #expect(pm.tracks.count == 20)
        #expect(Set(pm.tracks.map(\.url)) == Set(tracks.map(\.url)))
        #expect(pm.tracks[pm.currentIndex].url == currentBefore.url)
    }

    @Test func totalDuration_sumsAcrossTracks() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a", duration: 60), makeTrack("b", duration: 90)])
        #expect(pm.totalDuration == 150)
    }

    @Test func filteredTracks_searchQueryMatchesTitle() {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("Alpha"), makeTrack("Beta"), makeTrack("alphabet")])
        pm.searchQuery = "alpha"
        #expect(pm.filteredTracks.count == 2)
    }

    @Test func advanceToNext_viaNotification_advancesIndex() async {
        let pm = PlaylistManager()
        pm.addTracks([makeTrack("a"), makeTrack("b"), makeTrack("c")])
        pm.currentIndex = 0
        NotificationCenter.default.post(name: .trackDidFinish, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000) // let the main-queue sink run
        #expect(pm.currentIndex == 1)
    }
}
```

- [ ] **Step 2: Confirm `Notification.Name.trackDidFinish` exists**

Run:
```bash
```
Use Grep:
```
pattern: trackDidFinish
```
Expected: declaration somewhere in `Wamp/Audio/AudioEngine.swift` or similar. If missing, tests will fail to compile — stop and investigate before proceeding.

- [ ] **Step 3: Run the suite and expect PASS**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' \
  -only-testing:WampTests/PlaylistManager test 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`, 11 tests executed.

If any test fails because `PlaylistManager.init()` spins up a main-actor Combine subscriber and the notification-based test races, increase the sleep to `200_000_000` ns (200 ms). Do not add polling loops.

- [ ] **Step 4: Commit**

```bash
git add WampTests/Models/PlaylistManagerTests.swift
git commit -m "test: cover PlaylistManager add/remove/move/navigation"
```

---

### Task 6: Write `StateManagerTests`

**Files:**
- Create: `WampTests/Models/StateManagerTests.swift`

Tests construct `StateManager(directory:)` against a fresh `tmp/UUID` directory and verify round-trips for `AppState`, `EQState`, and the playlist. Corrupt-JSON fallback is also covered.

- [ ] **Step 1: Write all tests**

Create `WampTests/Models/StateManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import Wamp

@Suite("StateManager")
struct StateManagerTests {

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WampTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func appState_roundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        var state = AppState()
        state.volume = 0.42
        state.balance = -0.25
        state.repeatMode = 2
        state.eqEnabled = false
        state.showEqualizer = false
        state.showPlaylist = true
        state.windowX = 300
        state.windowY = 420
        state.alwaysOnTop = false
        state.lastTrackIndex = 7
        state.lastPlaybackPosition = 123.5
        state.skinPath = "/tmp/some-skin"

        let writer = StateManager(directory: dir)
        writer.saveAppState(state)

        let reader = StateManager(directory: dir)
        let loaded = reader.loadAppState()

        #expect(loaded.volume == 0.42)
        #expect(loaded.balance == -0.25)
        #expect(loaded.repeatMode == 2)
        #expect(loaded.eqEnabled == false)
        #expect(loaded.showEqualizer == false)
        #expect(loaded.showPlaylist == true)
        #expect(loaded.windowX == 300)
        #expect(loaded.windowY == 420)
        #expect(loaded.alwaysOnTop == false)
        #expect(loaded.lastTrackIndex == 7)
        #expect(loaded.lastPlaybackPosition == 123.5)
        #expect(loaded.skinPath == "/tmp/some-skin")
    }

    @Test func loadAppState_missingFile_returnsDefaults() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let sm = StateManager(directory: dir)
        let loaded = sm.loadAppState()
        #expect(loaded.volume == 0.75)
        #expect(loaded.lastTrackIndex == -1)
    }

    @Test func loadAppState_corruptFile_returnsDefaults() throws {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let corrupt = dir.appendingPathComponent("state.json")
        try "not valid json".write(to: corrupt, atomically: true, encoding: .utf8)

        let sm = StateManager(directory: dir)
        let loaded = sm.loadAppState()
        #expect(loaded.volume == 0.75)  // default
    }

    @Test func eqState_roundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let eq = EQState(
            bands: [-6, -3, 0, 3, 6, 6, 3, 0, -3, -6],
            preampGain: 4.5,
            presetName: "Rock",
            autoMode: true
        )
        StateManager(directory: dir).saveEQState(eq)

        let loaded = StateManager(directory: dir).loadEQState()
        #expect(loaded.bands == [-6, -3, 0, 3, 6, 6, 3, 0, -3, -6])
        #expect(loaded.preampGain == 4.5)
        #expect(loaded.presetName == "Rock")
        #expect(loaded.autoMode == true)
    }

    @Test func loadEQState_missingFile_returnsDefaults() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let loaded = StateManager(directory: dir).loadEQState()
        #expect(loaded.bands == Array(repeating: Float(0), count: 10))
        #expect(loaded.preampGain == 0)
        #expect(loaded.presetName == "Flat")
    }

    @Test func saveAndLoadPlaylist_roundTrip() {
        let dir = makeTempDirectory()
        defer { cleanup(dir) }

        let sm = StateManager(directory: dir)
        // Write directly via the private `write` path exercised through the
        // public surface: savePlaylist(playlistManager:) takes the live manager,
        // so instead we encode via a PlaylistManager-like path using JSONEncoder
        // — but StateManager owns the filename, so we go through the real API.
        // Easiest: put two real Tracks into a PlaylistManager and call savePlaylist.
        let pm = PlaylistManager()
        pm.addTracks([
            Track(url: URL(fileURLWithPath: "/tmp/one.m4a"), title: "One", artist: "A", album: "X", duration: 10),
            Track(url: URL(fileURLWithPath: "/tmp/two.m4a"), title: "Two", artist: "B", album: "Y", duration: 20),
        ])
        sm.savePlaylist(playlistManager: pm)

        let loaded = sm.loadSavedPlaylist()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.title) == ["One", "Two"])
        #expect(loaded.map(\.duration) == [10, 20])
    }
}
```

- [ ] **Step 2: Run and expect PASS**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' \
  -only-testing:WampTests/StateManager test 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`, 6 tests executed.

If `PlaylistManager` initialization in the playlist round-trip test requires `@MainActor`, mark that individual `@Test` with `@MainActor func` and re-run.

- [ ] **Step 3: Commit**

```bash
git add WampTests/Models/StateManagerTests.swift
git commit -m "test: cover StateManager round-trip and fallback paths"
```

---

### Task 7: Write `TrackTests` using the fixture

**Files:**
- Create: `WampTests/Models/TrackTests.swift`

Tests load the committed `sample.m4a` via `Bundle.module` / `Bundle(for:)` and assert on the parsed metadata. Since `WampTests` is a unit-test bundle built by Xcode (not SPM), fixtures are located via `Bundle(for: FixtureAnchor.self)` using an anchor class. Swift Testing suites can be structs, so we use a throwaway `final class FixtureAnchor {}` inside the file.

- [ ] **Step 1: Write the tests**

Create `WampTests/Models/TrackTests.swift`:

```swift
import Testing
import Foundation
@testable import Wamp

private final class FixtureAnchor {}

@MainActor
@Suite("Track")
struct TrackTests {

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: "sample", withExtension: "m4a") else {
            Issue.record("sample.m4a missing from WampTests bundle resources")
            throw CancellationError()
        }
        return url
    }

    @Test func fromURL_parsesMetadataTags() async throws {
        let url = try fixtureURL()
        let track = await Track.fromURL(url)
        #expect(track.title == "Wamp Fixture Title")
        #expect(track.artist == "Wamp Fixture Artist")
        #expect(track.album == "Wamp Fixture Album")
    }

    @Test func fromURL_parsesAudioFormat() async throws {
        let url = try fixtureURL()
        let track = await Track.fromURL(url)
        #expect(track.channels == 2)
        #expect(track.sampleRate == 44_100)
        #expect(track.duration > 0.3)
        #expect(track.duration < 0.8)
    }

    @Test func fromURL_unreadableFile_fallsBackToFilename() async {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).m4a")
        let track = await Track.fromURL(bogus)
        #expect(track.title == bogus.deletingPathExtension().lastPathComponent)
        #expect(track.duration == 0)
    }

    @Test func displayTitle_formatsArtistAndTitle() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Band", album: "", duration: 0)
        #expect(track.displayTitle == "Band - Song")
    }

    @Test func displayTitle_withoutArtist_returnsTitleOnly() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "Song", artist: "Unknown Artist", album: "", duration: 0)
        #expect(track.displayTitle == "Song")
    }

    @Test func formattedDuration_minutesAndSeconds() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/x.m4a"),
                          title: "", artist: "", album: "", duration: 125)
        #expect(track.formattedDuration == "2:05")
    }
}
```

- [ ] **Step 2: Run and expect PASS**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' \
  -only-testing:WampTests/Track test 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`, 6 tests executed.

If the metadata-tag test fails because AVAssetWriter stored tags under a different keyspace, either:
- adjust Task 4 step 1 to use `.iTunes` keyspace and regenerate the fixture, OR
- adjust the test expectations here only if the actual parsed values are still deterministic and meaningful.

Do not soften the assertion to "is non-empty".

- [ ] **Step 3: Commit**

```bash
git add WampTests/Models/TrackTests.swift
git commit -m "test: cover Track.fromURL metadata and audio format parsing"
```

---

### Task 8: Persistence round-trip integration test

**Files:**
- Create: `WampTests/Integration/PersistenceRoundTripTests.swift`

One end-to-end test: populate a `PlaylistManager`, configure an `AppState` + `EQState`, save them through a `StateManager(directory:)`, construct a new `StateManager` from the same directory, and assert every field comes back.

- [ ] **Step 1: Write the test**

Create `WampTests/Integration/PersistenceRoundTripTests.swift`:

```swift
import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("Persistence round-trip")
struct PersistenceRoundTripTests {

    @Test func fullSessionRestoresAfterReload() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WampRoundTrip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Session A: set up state and save.
        let pmA = PlaylistManager()
        pmA.addTracks([
            Track(url: URL(fileURLWithPath: "/tmp/song1.m4a"), title: "Song 1", artist: "Band", album: "Alb", duration: 180),
            Track(url: URL(fileURLWithPath: "/tmp/song2.m4a"), title: "Song 2", artist: "Band", album: "Alb", duration: 240),
        ])
        pmA.currentIndex = 1

        var appState = AppState()
        appState.volume = 0.3
        appState.repeatMode = 1
        appState.lastTrackIndex = pmA.currentIndex
        appState.lastPlaybackPosition = 42

        let eqState = EQState(
            bands: [1, 2, 3, 4, 5, -5, -4, -3, -2, -1],
            preampGain: 2.0,
            presetName: "Custom",
            autoMode: false
        )

        let smA = StateManager(directory: dir)
        smA.saveAppState(appState)
        smA.saveEQState(eqState)
        smA.savePlaylist(playlistManager: pmA)

        // Session B: fresh StateManager, verify.
        let smB = StateManager(directory: dir)
        let loadedApp = smB.loadAppState()
        let loadedEQ = smB.loadEQState()
        let loadedTracks = smB.loadSavedPlaylist()

        #expect(loadedApp.volume == 0.3)
        #expect(loadedApp.repeatMode == 1)
        #expect(loadedApp.lastTrackIndex == 1)
        #expect(loadedApp.lastPlaybackPosition == 42)

        #expect(loadedEQ.bands == [1, 2, 3, 4, 5, -5, -4, -3, -2, -1])
        #expect(loadedEQ.preampGain == 2.0)
        #expect(loadedEQ.presetName == "Custom")

        #expect(loadedTracks.count == 2)
        #expect(loadedTracks.map(\.title) == ["Song 1", "Song 2"])
        #expect(loadedTracks[1].duration == 240)
    }
}
```

- [ ] **Step 2: Run and expect PASS**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' \
  -only-testing:WampTests/Persistence_round_trip test 2>&1 | tail -40
```
(Note the suite name uses underscores because Swift Testing sanitizes spaces.)

Expected: `** TEST SUCCEEDED **`, 1 test executed.

- [ ] **Step 3: Run the full suite**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 24 tests executed (11 + 6 + 6 + 1).

- [ ] **Step 4: Commit**

```bash
git add WampTests/Integration/PersistenceRoundTripTests.swift
git commit -m "test: add persistence round-trip integration test"
```

---

### Task 9: Update `CLAUDE.md` with test command and workflow rules

**Files:**
- Modify: `CLAUDE.md` — `## Build & Run` section and `## Workflow` section

- [ ] **Step 1: Update `## Build & Run`**

Find in `CLAUDE.md`:

```markdown
This is a macOS app built with Xcode. Open `Wamp.xcodeproj` and build/run from Xcode, or use:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build
```

There are no tests, no linter, and no CI/CD configured.
```

Replace with:

```markdown
This is a macOS app built with Xcode. Open `Wamp.xcodeproj` and build/run from Xcode, or use:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build
```

Run the test suite:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test
```

No linter and no CI/CD are configured. Tests cover `Models/` and a persistence round-trip only — `AudioEngine`, UI views, and `HotKeyManager` are deliberately out of scope (see `docs/superpowers/specs/2026-04-12-testing-design.md`).
```

- [ ] **Step 2: Add Workflow bullets**

Find the `## Workflow` section and add these two bullets to the existing list:

```markdown
- **TDD for Models/** — any change under `Wamp/Models/` follows red → green → commit using the `superpowers:test-driven-development` skill: write the failing test first, implement until green, commit test and code together.
- **Test merge gate** — `/wrap-session` runs `xcodebuild ... test` before merging a feature branch. Red tests abort the merge; the session stays open until the suite is green.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document test command and TDD workflow in CLAUDE.md"
```

---

### Task 10: Wire test run into `/wrap-session`

**Files:**
- Modify: `docs/superpowers/wrap-session.md`
- Modify: `.claude/commands/wrap-session.*` if present

- [ ] **Step 1: Read the current wrap-session doc**

Read `docs/superpowers/wrap-session.md` to locate the pre-merge section.

- [ ] **Step 2: Add the test gate**

Before the `git merge --no-ff` step, insert:

```markdown
### Run tests before merge

Before merging, run the full test suite:

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test
```

If the run ends with `** TEST SUCCEEDED **`, proceed to the merge.
If the run fails, **abort `/wrap-session`**, keep the feature branch checked out, report the failing tests to the user, and do not merge. The session stays open until the suite is green.
```

- [ ] **Step 3: Mirror in the slash command if applicable**

Run:
```bash
ls .claude/commands/ 2>/dev/null
```
If `wrap-session.*` exists there, open it and add the same "Run tests before merge" step in the appropriate position. If it does not exist, skip.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/wrap-session.md .claude/commands/wrap-session.* 2>/dev/null || git add docs/superpowers/wrap-session.md
git commit -m "docs: add test merge gate to /wrap-session"
```

---

## Final Verification

- [ ] Run the full suite once more:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **`, 24 tests, < 15 seconds wall time.

- [ ] Run the suite a second time to confirm determinism:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -5
```
Same result.

- [ ] Confirm `~/Library/Application Support/Wamp/` was NOT touched by any test run (check modification times).

- [ ] Post end-of-list report per `CLAUDE.md` Workflow rules and wait for user approval before `/wrap-session`.
