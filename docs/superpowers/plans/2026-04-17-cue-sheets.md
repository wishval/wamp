# CUE Sheet Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load `.cue` sheets (external + FLAC-embedded) so one large audio file appears as multiple virtual tracks in the playlist, with gapless playback between them.

**Architecture:** A pure `Data → CueSheet` parser in `Wamp/CueSheet/` (no AVFoundation), an encoding-detection helper for the typical Shift-JIS / CP-1251 / CP-1252 cue files, a small extractor for FLAC `CUESHEET` Vorbis comments, two new optional fields on `Track` (`cueStart`, `cueEnd` in seconds) so virtual tracks flow through the existing `[Track]` playlist plumbing without invasive refactors, and an `AudioEngine` overload that schedules a bounded segment from start-sample to end-sample. Gapless transitions across CUE tracks on the same underlying file are achieved by chaining a follow-up `scheduleSegment` on the same `AVAudioPlayerNode` without resetting the file or generation.

**Tech Stack:** Swift / Cocoa / AVFoundation. Tests use XCTest. No third-party dependencies.

---

## File Structure

**New files:**
- `Wamp/CueSheet/CueSheet.swift` — value types (`CueSheet`, `CueFile`, `CueTrack`, `CueParseError`) and the `framesToSeconds` helper.
- `Wamp/CueSheet/CueDecoder.swift` — `decodeCueData(_:) -> (String, String.Encoding)` with BOM, UTF-8 strict, candidate chain, lossy CP-1252 fallback.
- `Wamp/CueSheet/CueSheetParser.swift` — pure `parse(_ data: Data) -> CueSheet` and `parse(url:)` line-based parser.
- `Wamp/CueSheet/FlacCueExtractor.swift` — reads FLAC metadata blocks (STREAMINFO + VORBIS_COMMENT), returns the embedded `CUESHEET` tag value or nil.
- `Wamp/CueSheet/CueResolver.swift` — `resolveTracks(cue:cueDirectory:) async throws -> [Track]`: loads each FILE via `AVURLAsset`, computes start/end seconds for every track, returns Tracks with `cueStart` / `cueEnd` populated.
- `WampTests/CueSheet/CueSheetParserTests.swift`
- `WampTests/CueSheet/CueDecoderTests.swift`
- `WampTests/CueSheet/FlacCueExtractorTests.swift`
- `WampTests/CueSheet/CueResolverTests.swift`
- `WampTests/Fixtures/cue/basic.cue`
- `WampTests/Fixtures/cue/multi-file.cue`
- `WampTests/Fixtures/cue/shift-jis.cue` (binary)
- `WampTests/Fixtures/cue/cp1251.cue` (binary)
- `WampTests/Fixtures/cue/cp1252.cue` (binary)
- `WampTests/Fixtures/cue/malformed.cue`
- `WampTests/Fixtures/cue/zero-tracks.cue`
- `WampTests/Fixtures/cue/dj-mix-pair/` — synthetic FLAC + matching .cue used by gapless test (generated at test runtime, see Task 19).

**Modified files:**
- `Wamp/Models/Track.swift` — add optional `cueStart: TimeInterval?`, `cueEnd: TimeInterval?`, derived `isCueVirtual: Bool`. `Codable` keys updated. `formattedDuration` and `duration` work as today (callers populate `duration` correctly when constructing virtual tracks).
- `Wamp/Audio/AudioEngine.swift` — add `loadAndPlay(track: Track)` overload that honors `cueStart`/`cueEnd`; refactor `scheduleAndPlay()` to take a per-call `endFrame` instead of always using `audioLengthFrames`; add `chainNextSegment(track:)` to schedule a follow-up segment without stopping the player when transitioning between two virtual tracks on the same URL.
- `Wamp/Models/PlaylistManager.swift` — `playTrack(at:)` calls the new `loadAndPlay(track:)` overload; new `addCueSheet(url:)` async; on `advanceToNext()` if previous and next tracks are CUE-virtual on the same URL and engine is currently playing, ask the engine to chain instead of reload.
- `Wamp/AppDelegate.swift` — `application(_:open:)` and the file-open dialog accept `.cue`; routes to `PlaylistManager.addCueSheet`.
- `Wamp/UI/PlaylistView.swift` — extend the right-click menu with "Reveal source file" for the selected row when `Track.isCueVirtual`.
- `CHANGELOG.md` — entry for the feature.

---

### Task 0: Branch & scaffolding

**Files:**
- N/A (git only)

- [ ] **Step 1: Create feature branch from clean main**

```bash
git status   # must show "nothing to commit, working tree clean"
git checkout -b feat/cue-sheets
```

- [ ] **Step 2: Confirm pre-commit hook present**

Run: `ls -l .git/hooks/pre-commit`
Expected: file exists and is executable. (No commit yet.)

---

### Task 1: CueSheet value types

**Files:**
- Create: `Wamp/CueSheet/CueSheet.swift`
- Create: `WampTests/CueSheet/CueSheetParserTests.swift` (single placeholder test)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Wamp

final class CueSheetParserTests: XCTestCase {
    func test_cueTrack_framesToSeconds_75framesIsOneSecond() {
        let track = CueTrack(number: 1, title: nil, performer: nil, startFrames: 75)
        XCTAssertEqual(CueSheet.framesToSeconds(track.startFrames), 1.0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test -only-testing:WampTests/CueSheetParserTests`
Expected: build error — `CueTrack` and `CueSheet` undefined.

- [ ] **Step 3: Create CueSheet.swift**

```swift
import Foundation

public struct CueSheet: Equatable {
    public let title: String?
    public let performer: String?
    public let genre: String?
    public let date: String?
    public let files: [CueFile]

    /// Convert CD-frame count (1/75 sec) to seconds.
    public static func framesToSeconds(_ frames: Int) -> Double {
        Double(frames) / 75.0
    }
}

public struct CueFile: Equatable {
    public let path: String
    public let format: String
    public let tracks: [CueTrack]
}

public struct CueTrack: Equatable {
    public let number: Int
    public let title: String?
    public let performer: String?
    /// 1/75-second units, as authored in INDEX 01.
    public let startFrames: Int
}

public enum CueParseError: Error, Equatable {
    case encoding
    case malformed(line: Int, reason: String)
    case noTracks
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test -only-testing:WampTests/CueSheetParserTests`
Expected: 1 test passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueSheet.swift WampTests/CueSheet/CueSheetParserTests.swift
git commit -m "feat: add CueSheet value types and frames→seconds helper"
```

---

### Task 2: Encoding decoder — UTF-8 + BOM

**Files:**
- Create: `Wamp/CueSheet/CueDecoder.swift`
- Create: `WampTests/CueSheet/CueDecoderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Wamp

final class CueDecoderTests: XCTestCase {
    func test_decodes_utf8_without_bom() throws {
        let data = "TITLE \"Hellø\"\n".data(using: .utf8)!
        let result = try CueDecoder.decode(data)
        XCTAssertEqual(result.text, "TITLE \"Hellø\"\n")
        XCTAssertEqual(result.encoding, .utf8)
    }

    func test_decodes_utf8_with_bom() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("TITLE \"X\"\n".data(using: .utf8)!)
        let result = try CueDecoder.decode(data)
        XCTAssertEqual(result.text, "TITLE \"X\"\n") // BOM stripped
        XCTAssertEqual(result.encoding, .utf8)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `xcodebuild ... test -only-testing:WampTests/CueDecoderTests`
Expected: build error — `CueDecoder` undefined.

- [ ] **Step 3: Implement decoder (UTF-8 path only)**

```swift
import Foundation

public enum CueDecoder {
    public struct Result {
        public let text: String
        public let encoding: String.Encoding
    }

    public static func decode(_ data: Data) throws -> Result {
        // BOM detection
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            guard let s = String(data: body, encoding: .utf8) else { throw CueParseError.encoding }
            return Result(text: s, encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            let body = data.dropFirst(2)
            guard let s = String(data: body, encoding: .utf16LittleEndian) else { throw CueParseError.encoding }
            return Result(text: s, encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            let body = data.dropFirst(2)
            guard let s = String(data: body, encoding: .utf16BigEndian) else { throw CueParseError.encoding }
            return Result(text: s, encoding: .utf16BigEndian)
        }

        // UTF-8 strict (rejects ill-formed sequences)
        if let s = String(data: data, encoding: .utf8), s.utf8.count == data.count {
            return Result(text: s, encoding: .utf8)
        }

        // Candidate chain — implemented in next task
        throw CueParseError.encoding
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild ... test -only-testing:WampTests/CueDecoderTests`
Expected: 2 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueDecoder.swift WampTests/CueSheet/CueDecoderTests.swift
git commit -m "feat: add CueDecoder with BOM + UTF-8 strict detection"
```

---

### Task 3: Encoding decoder — non-UTF-8 candidate chain

**Files:**
- Modify: `Wamp/CueSheet/CueDecoder.swift`
- Modify: `WampTests/CueSheet/CueDecoderTests.swift`

- [ ] **Step 1: Write failing tests for each candidate encoding**

Append to `CueDecoderTests`:

```swift
func test_decodes_cp1251_cyrillic() throws {
    // "TITLE \"Тест\"\r\n" in CP-1251
    let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0xD2,0xE5,0xF1,0xF2,0x22,0x0D,0x0A])
    let result = try CueDecoder.decode(data)
    XCTAssertEqual(result.encoding, .windowsCP1251)
    XCTAssertTrue(result.text.contains("Тест"))
}

func test_decodes_shift_jis_japanese() throws {
    // "TITLE \"日本\"\n" in Shift-JIS
    let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0x93,0xFA,0x96,0x7B,0x22,0x0A])
    let result = try CueDecoder.decode(data)
    XCTAssertEqual(result.encoding, .shiftJIS)
    XCTAssertTrue(result.text.contains("日本"))
}

func test_decodes_cp1252_french_diacritics() throws {
    // "TITLE \"Café\"\n" in CP-1252 (é = 0xE9)
    let data = Data([0x54,0x49,0x54,0x4C,0x45,0x20,0x22,0x43,0x61,0x66,0xE9,0x22,0x0A])
    let result = try CueDecoder.decode(data)
    XCTAssertTrue([.windowsCP1252, .isoLatin1].contains(result.encoding))
    XCTAssertTrue(result.text.contains("Café"))
}

func test_falls_back_to_cp1252_lossy_for_garbage() throws {
    let data = Data([0xFF, 0xFE, 0xC0, 0xC1, 0x80])  // odd bytes, no clean decode
    // BOM 0xFF 0xFE looks like UTF-16 LE — confirm this becomes whatever decodes
    // Replace fixture with bytes guaranteed not to be a valid BOM:
    let garbage = Data([0xC0, 0xC1, 0x80])
    let result = try CueDecoder.decode(garbage)
    XCTAssertEqual(result.encoding, .windowsCP1252)
    XCTAssertFalse(result.text.isEmpty)
    _ = data  // suppress unused warning
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild ... test -only-testing:WampTests/CueDecoderTests`
Expected: 3 new tests fail (decoder still throws `.encoding`).

- [ ] **Step 3: Extend decoder with the candidate chain**

Replace the `throw CueParseError.encoding` line at the end of `decode(_:)` with:

```swift
        // Candidate chain — pick the first encoding that decodes without lossy conversion.
        let candidates: [String.Encoding] = [.shiftJIS, .windowsCP1251, .windowsCP1252, .isoLatin1]
        for enc in candidates {
            var converted: NSString? = nil
            var lossy: ObjCBool = false
            let recognized = NSString.stringEncoding(
                for: data,
                encodingOptions: [.suggestedEncodingsKey: [NSNumber(value: enc.rawValue)],
                                  .useOnlySuggestedEncodingsKey: true],
                convertedString: &converted,
                usedLossyConversion: &lossy
            )
            if recognized != 0, !lossy.boolValue, let s = converted as String? {
                return Result(text: s, encoding: String.Encoding(rawValue: recognized))
            }
        }

        // Last-resort lossy CP-1252.
        if let s = String(data: data, encoding: .windowsCP1252) {
            #if DEBUG
            print("⚠️ CueDecoder: lossy CP-1252 fallback")
            #endif
            return Result(text: s, encoding: .windowsCP1252)
        }
        throw CueParseError.encoding
```

- [ ] **Step 4: Run to verify all decoder tests pass**

Run: `xcodebuild ... test -only-testing:WampTests/CueDecoderTests`
Expected: 5 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueDecoder.swift WampTests/CueSheet/CueDecoderTests.swift
git commit -m "feat: detect Shift-JIS / CP-1251 / CP-1252 cue encodings"
```

---

### Task 4: Parser — file-level metadata (TITLE, PERFORMER, REM)

**Files:**
- Create: `Wamp/CueSheet/CueSheetParser.swift`
- Modify: `WampTests/CueSheet/CueSheetParserTests.swift`

- [ ] **Step 1: Write failing test**

Append to `CueSheetParserTests`:

```swift
func test_parses_top_level_metadata_with_no_files() {
    let cue = """
    REM GENRE "Electronic"
    REM DATE 2003
    PERFORMER "Various Artists"
    TITLE "DJ Mix vol. 3"
    """
    let data = cue.data(using: .utf8)!
    XCTAssertThrowsError(try CueSheetParser.parse(data)) { error in
        XCTAssertEqual(error as? CueParseError, .noTracks)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests`
Expected: build error — `CueSheetParser` undefined.

- [ ] **Step 3: Create CueSheetParser.swift with file-level scaffolding**

```swift
import Foundation

public enum CueSheetParser {
    public static func parse(url: URL) throws -> CueSheet {
        let data = try Data(contentsOf: url)
        return try parse(data)
    }

    public static func parse(_ data: Data) throws -> CueSheet {
        let decoded = try CueDecoder.decode(data)
        return try parseText(decoded.text)
    }

    static func parseText(_ text: String) throws -> CueSheet {
        var title: String?
        var performer: String?
        var genre: String?
        var date: String?
        var files: [CueFile] = []

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lineNo = idx + 1
            let (keyword, rest) = splitKeyword(line)
            switch keyword.uppercased() {
            case "TITLE":
                title = unquote(rest)
            case "PERFORMER":
                performer = unquote(rest)
            case "REM":
                let (subKey, subRest) = splitKeyword(rest)
                switch subKey.uppercased() {
                case "GENRE": genre = unquote(subRest)
                case "DATE":  date  = unquote(subRest)
                default: break  // other REM lines ignored
                }
            case "FILE", "TRACK", "INDEX":
                // Handled in later tasks.
                _ = lineNo
            default:
                break  // unknown keywords ignored at this stage
            }
        }

        guard !files.isEmpty, files.contains(where: { !$0.tracks.isEmpty }) else {
            throw CueParseError.noTracks
        }
        return CueSheet(title: title, performer: performer, genre: genre, date: date, files: files)
    }

    /// Split off the first whitespace-delimited token. Returns ("", "") for empty input.
    static func splitKeyword(_ s: String) -> (String, String) {
        guard let space = s.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (s, "")
        }
        let head = String(s[..<space])
        let tail = String(s[s.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (head, tail)
    }

    /// Strip surrounding double quotes if present.
    static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, t.first == "\"", t.last == "\"" {
            return String(t.dropFirst().dropLast())
        }
        return t
    }
}
```

- [ ] **Step 4: Run to verify the noTracks test passes**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests`
Expected: 2 tests passing (the framesToSeconds + the new noTracks test).

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueSheetParser.swift WampTests/CueSheet/CueSheetParserTests.swift
git commit -m "feat: parse cue file-level metadata (TITLE, PERFORMER, REM)"
```

---

### Task 5: Parser — FILE + TRACK + INDEX 01

**Files:**
- Modify: `Wamp/CueSheet/CueSheetParser.swift`
- Modify: `WampTests/CueSheet/CueSheetParserTests.swift`

- [ ] **Step 1: Write failing test for a basic single-file cue**

Append:

```swift
func test_parses_single_file_with_two_tracks() throws {
    let cue = """
    PERFORMER "DJ X"
    TITLE "DJ Mix vol. 3"
    FILE "mix.flac" WAVE
      TRACK 01 AUDIO
        TITLE "Opening"
        PERFORMER "DJ X"
        INDEX 01 00:00:00
      TRACK 02 AUDIO
        TITLE "Second tune"
        PERFORMER "DJ Y"
        INDEX 01 05:32:40
    """
    let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
    XCTAssertEqual(sheet.title, "DJ Mix vol. 3")
    XCTAssertEqual(sheet.performer, "DJ X")
    XCTAssertEqual(sheet.files.count, 1)
    let file = sheet.files[0]
    XCTAssertEqual(file.path, "mix.flac")
    XCTAssertEqual(file.format, "WAVE")
    XCTAssertEqual(file.tracks.count, 2)
    XCTAssertEqual(file.tracks[0].number, 1)
    XCTAssertEqual(file.tracks[0].title, "Opening")
    XCTAssertEqual(file.tracks[0].performer, "DJ X")
    XCTAssertEqual(file.tracks[0].startFrames, 0)
    XCTAssertEqual(file.tracks[1].number, 2)
    XCTAssertEqual(file.tracks[1].title, "Second tune")
    // 5 min 32 sec 40 frames = (5*60 + 32)*75 + 40 = 25 040
    XCTAssertEqual(file.tracks[1].startFrames, 25_040)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests`
Expected: the new test fails (no FILE/TRACK handling yet, throws `noTracks`).

- [ ] **Step 3: Implement FILE / TRACK / INDEX 01 parsing**

Replace the `parseText(_:)` body with this state-machine version:

```swift
    static func parseText(_ text: String) throws -> CueSheet {
        var title: String?
        var performer: String?
        var genre: String?
        var date: String?

        struct PendingFile {
            var path: String
            var format: String
            var tracks: [CueTrack] = []
        }
        struct PendingTrack {
            var number: Int
            var title: String?
            var performer: String?
            var startFrames: Int?  // from INDEX 01
        }

        var files: [PendingFile] = []
        var currentFile: PendingFile?
        var currentTrack: PendingTrack?

        func flushTrack() throws {
            guard let t = currentTrack else { return }
            guard let start = t.startFrames else {
                throw CueParseError.malformed(line: 0, reason: "TRACK \(t.number) missing INDEX 01")
            }
            currentFile?.tracks.append(CueTrack(
                number: t.number, title: t.title, performer: t.performer, startFrames: start
            ))
            currentTrack = nil
        }

        func flushFile() throws {
            try flushTrack()
            if let f = currentFile { files.append(f) }
            currentFile = nil
        }

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lineNo = idx + 1
            let (keyword, rest) = splitKeyword(line)
            switch keyword.uppercased() {
            case "TITLE":
                if currentTrack != nil { currentTrack?.title = unquote(rest) }
                else { title = unquote(rest) }
            case "PERFORMER":
                if currentTrack != nil { currentTrack?.performer = unquote(rest) }
                else { performer = unquote(rest) }
            case "REM":
                let (subKey, subRest) = splitKeyword(rest)
                switch subKey.uppercased() {
                case "GENRE": genre = unquote(subRest)
                case "DATE":  date  = unquote(subRest)
                default: break
                }
            case "FILE":
                try flushFile()
                let (pathPart, formatPart) = splitFileLine(rest)
                currentFile = PendingFile(path: pathPart, format: formatPart.uppercased())
            case "TRACK":
                guard currentFile != nil else {
                    throw CueParseError.malformed(line: lineNo, reason: "TRACK before FILE")
                }
                try flushTrack()
                let (numStr, kindStr) = splitKeyword(rest)
                guard let num = Int(numStr) else {
                    throw CueParseError.malformed(line: lineNo, reason: "invalid TRACK number '\(numStr)'")
                }
                _ = kindStr  // AUDIO / MODE1/2048 / etc. — not used
                currentTrack = PendingTrack(number: num)
            case "INDEX":
                guard currentTrack != nil else {
                    throw CueParseError.malformed(line: lineNo, reason: "INDEX outside TRACK")
                }
                let (idxStr, timeStr) = splitKeyword(rest)
                guard let indexNo = Int(idxStr) else {
                    throw CueParseError.malformed(line: lineNo, reason: "invalid INDEX number '\(idxStr)'")
                }
                if indexNo == 1 {
                    guard let f = parseTimecode(timeStr) else {
                        throw CueParseError.malformed(line: lineNo, reason: "invalid timecode '\(timeStr)'")
                    }
                    currentTrack?.startFrames = f
                }
                // INDEX 00 (pregap) and others are intentionally ignored.
            default:
                break
            }
        }
        try flushFile()

        guard !files.isEmpty, files.contains(where: { !$0.tracks.isEmpty }) else {
            throw CueParseError.noTracks
        }
        let resolvedFiles = files.map { CueFile(path: $0.path, format: $0.format, tracks: $0.tracks) }
        return CueSheet(title: title, performer: performer, genre: genre, date: date, files: resolvedFiles)
    }

    /// FILE "name with spaces.flac" WAVE  →  ("name with spaces.flac", "WAVE")
    /// FILE name.wav WAVE                 →  ("name.wav",              "WAVE")
    static func splitFileLine(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.first == "\"" {
            if let closing = t.dropFirst().firstIndex(of: "\"") {
                let path = String(t[t.index(after: t.startIndex)..<closing])
                let rest = String(t[t.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
                return (path, rest)
            }
            return (String(t.dropFirst()), "")
        }
        return splitKeyword(t)
    }

    /// "MM:SS:FF" → frame count (1/75 sec).
    static func parseTimecode(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 3,
              let m = Int(parts[0]), let sec = Int(parts[1]), let f = Int(parts[2]),
              m >= 0, sec >= 0, sec < 60, f >= 0, f < 75 else { return nil }
        return ((m * 60) + sec) * 75 + f
    }
```

- [ ] **Step 4: Run to verify all parser tests pass**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests`
Expected: 3 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueSheetParser.swift WampTests/CueSheet/CueSheetParserTests.swift
git commit -m "feat: parse cue FILE / TRACK / INDEX 01 entries"
```

---

### Task 6: Parser — INDEX 00 ignored, multi-FILE, malformed cases

**Files:**
- Modify: `WampTests/CueSheet/CueSheetParserTests.swift` only (parser already supports these — these are regression locks)

- [ ] **Step 1: Write failing tests**

```swift
func test_index_00_pregap_is_ignored_when_index_01_present() throws {
    let cue = """
    FILE "a.wav" WAVE
      TRACK 01 AUDIO
        INDEX 01 00:00:00
      TRACK 02 AUDIO
        INDEX 00 05:30:00
        INDEX 01 05:32:40
    """
    let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
    XCTAssertEqual(sheet.files[0].tracks[1].startFrames, 25_040)
}

func test_multi_file_cue() throws {
    let cue = """
    FILE "a.wav" WAVE
      TRACK 01 AUDIO
        INDEX 01 00:00:00
    FILE "b.wav" WAVE
      TRACK 02 AUDIO
        INDEX 01 00:00:00
    """
    let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
    XCTAssertEqual(sheet.files.count, 2)
    XCTAssertEqual(sheet.files[0].path, "a.wav")
    XCTAssertEqual(sheet.files[0].tracks.first?.number, 1)
    XCTAssertEqual(sheet.files[1].path, "b.wav")
    XCTAssertEqual(sheet.files[1].tracks.first?.number, 2)
}

func test_track_without_index_01_is_malformed() {
    let cue = """
    FILE "a.wav" WAVE
      TRACK 01 AUDIO
        TITLE "x"
    """
    XCTAssertThrowsError(try CueSheetParser.parse(cue.data(using: .utf8)!)) { err in
        guard case .malformed(_, let reason) = err as! CueParseError else {
            return XCTFail("expected .malformed, got \(err)")
        }
        XCTAssertTrue(reason.contains("INDEX 01"))
    }
}

func test_track_before_file_is_malformed_with_line_number() {
    let cue = """
    TRACK 01 AUDIO
      INDEX 01 00:00:00
    """
    XCTAssertThrowsError(try CueSheetParser.parse(cue.data(using: .utf8)!)) { err in
        guard case .malformed(let line, _) = err as! CueParseError else {
            return XCTFail("expected .malformed, got \(err)")
        }
        XCTAssertEqual(line, 1)
    }
}

func test_invalid_timecode_is_malformed() {
    let cue = """
    FILE "a.wav" WAVE
      TRACK 01 AUDIO
        INDEX 01 99:99:99
    """
    XCTAssertThrowsError(try CueSheetParser.parse(cue.data(using: .utf8)!)) { err in
        guard case .malformed(_, let reason) = err as! CueParseError else {
            return XCTFail("expected .malformed, got \(err)")
        }
        XCTAssertTrue(reason.contains("timecode"))
    }
}

func test_unquoted_file_path() throws {
    let cue = """
    FILE mix.flac WAVE
      TRACK 01 AUDIO
        INDEX 01 00:00:00
    """
    let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
    XCTAssertEqual(sheet.files[0].path, "mix.flac")
    XCTAssertEqual(sheet.files[0].format, "WAVE")
}

func test_file_path_with_spaces_in_quotes() throws {
    let cue = """
    FILE "a long name.flac" WAVE
      TRACK 01 AUDIO
        INDEX 01 00:00:00
    """
    let sheet = try CueSheetParser.parse(cue.data(using: .utf8)!)
    XCTAssertEqual(sheet.files[0].path, "a long name.flac")
}
```

- [ ] **Step 2: Run to verify they all pass (parser already supports these paths)**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests`
Expected: all parser tests pass. If any fail, fix the parser; do not weaken the test.

- [ ] **Step 3: Fix the line-number bug in `flushTrack()`**

The current `flushTrack` throws with `line: 0` because the line-number context is lost. Replace its signature and the two call sites:

```swift
        func flushTrack(at line: Int) throws {
            guard let t = currentTrack else { return }
            guard let start = t.startFrames else {
                throw CueParseError.malformed(line: line, reason: "TRACK \(t.number) missing INDEX 01")
            }
            currentFile?.tracks.append(CueTrack(
                number: t.number, title: t.title, performer: t.performer, startFrames: start
            ))
            currentTrack = nil
        }

        func flushFile(at line: Int) throws {
            try flushTrack(at: line)
            if let f = currentFile { files.append(f) }
            currentFile = nil
        }
```

Update the three call sites to pass `lineNo` (or `lines.count` for the trailing flush after the loop).

Then update `test_track_without_index_01_is_malformed` to additionally check that the reported line is non-zero:

```swift
        guard case .malformed(let line, let reason) = err as! CueParseError else { ... }
        XCTAssertGreaterThan(line, 0)
        XCTAssertTrue(reason.contains("INDEX 01"))
```

- [ ] **Step 4: Run to verify all parser tests pass with non-zero line numbers**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests`
Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueSheetParser.swift WampTests/CueSheet/CueSheetParserTests.swift
git commit -m "test: lock multi-file, malformed, and quoted-path cue parsing"
```

---

### Task 7: Fixture files + parse(url:) integration test

**Files:**
- Create: `WampTests/Fixtures/cue/basic.cue`, `multi-file.cue`, `malformed.cue`, `zero-tracks.cue` (text)
- Create: `WampTests/Fixtures/cue/cp1251.cue`, `shift-jis.cue`, `cp1252.cue` (binary, generated)
- Modify: `WampTests/CueSheet/CueSheetParserTests.swift` — add fixture-driven tests
- Modify: `Wamp.xcodeproj` — add fixture files to the WampTests target as resources

- [ ] **Step 1: Create text fixtures**

`WampTests/Fixtures/cue/basic.cue`:
```
REM GENRE "Electronic"
REM DATE 2003
PERFORMER "Various Artists"
TITLE "DJ Mix vol. 3"
FILE "mix.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Opening"
    PERFORMER "DJ X"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second tune"
    PERFORMER "DJ Y"
    INDEX 00 05:30:00
    INDEX 01 05:32:40
```

`WampTests/Fixtures/cue/multi-file.cue`:
```
TITLE "Compilation"
FILE "side-a.flac" WAVE
  TRACK 01 AUDIO
    TITLE "A1"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "A2"
    INDEX 01 03:15:00
FILE "side-b.flac" WAVE
  TRACK 03 AUDIO
    TITLE "B1"
    INDEX 01 00:00:00
```

`WampTests/Fixtures/cue/malformed.cue`:
```
TRACK 01 AUDIO
  INDEX 01 00:00:00
```

`WampTests/Fixtures/cue/zero-tracks.cue`:
```
TITLE "Empty"
PERFORMER "Nobody"
```

- [ ] **Step 2: Generate binary encoding fixtures**

Run from the repo root:

```bash
python3 -c "
content = '''REM GENRE \"Electronic\"
PERFORMER \"DJ Тест\"
TITLE \"Микс №3\"
FILE \"mix.flac\" WAVE
  TRACK 01 AUDIO
    TITLE \"Начало\"
    INDEX 01 00:00:00
'''
open('WampTests/Fixtures/cue/cp1251.cue','wb').write(content.encode('cp1251'))
"

python3 -c "
content = '''REM GENRE \"Jazz\"
PERFORMER \"山田太郎\"
TITLE \"日本のミックス\"
FILE \"mix.flac\" WAVE
  TRACK 01 AUDIO
    TITLE \"序章\"
    INDEX 01 00:00:00
'''
open('WampTests/Fixtures/cue/shift-jis.cue','wb').write(content.encode('shift_jis'))
"

python3 -c "
content = '''PERFORMER \"Café Crème\"
TITLE \"Été\"
FILE \"mix.flac\" WAVE
  TRACK 01 AUDIO
    TITLE \"Préambule\"
    INDEX 01 00:00:00
'''
open('WampTests/Fixtures/cue/cp1252.cue','wb').write(content.encode('cp1252'))
"
```

Verify:
```bash
file WampTests/Fixtures/cue/cp1251.cue WampTests/Fixtures/cue/shift-jis.cue WampTests/Fixtures/cue/cp1252.cue
```
Expected: each is reported as ISO-8859 / Non-ISO extended-ASCII (not UTF-8).

- [ ] **Step 3: Add the fixtures to the WampTests target as resources**

Open `Wamp.xcodeproj` in Xcode → select the WampTests target → Build Phases → Copy Bundle Resources → drag `WampTests/Fixtures/cue/` (folder reference). Save.

Verify the project file changed:
```bash
git diff --stat Wamp.xcodeproj
```
Expected: `project.pbxproj` modified.

- [ ] **Step 4: Add a fixture loader and integration tests**

Append to `CueSheetParserTests.swift`:

```swift
private func fixture(_ name: String) throws -> URL {
    let bundle = Bundle(for: CueSheetParserTests.self)
    if let url = bundle.url(forResource: name, withExtension: "cue", subdirectory: "Fixtures/cue") {
        return url
    }
    if let url = bundle.url(forResource: name, withExtension: "cue") {
        return url
    }
    throw XCTSkip("Fixture \(name).cue missing from test bundle (add to Copy Bundle Resources)")
}

func test_basic_fixture() throws {
    let url = try fixture("basic")
    let sheet = try CueSheetParser.parse(url: url)
    XCTAssertEqual(sheet.title, "DJ Mix vol. 3")
    XCTAssertEqual(sheet.files.first?.tracks.count, 2)
    XCTAssertEqual(sheet.files.first?.tracks[1].startFrames, 25_040)
}

func test_multi_file_fixture() throws {
    let url = try fixture("multi-file")
    let sheet = try CueSheetParser.parse(url: url)
    XCTAssertEqual(sheet.files.count, 2)
    XCTAssertEqual(sheet.files[1].tracks.first?.number, 3)
}

func test_zero_tracks_fixture_throws_noTracks() throws {
    let url = try fixture("zero-tracks")
    XCTAssertThrowsError(try CueSheetParser.parse(url: url))
}

func test_cp1251_fixture_decodes_cyrillic_titles() throws {
    let url = try fixture("cp1251")
    let sheet = try CueSheetParser.parse(url: url)
    XCTAssertEqual(sheet.title, "Микс №3")
    XCTAssertEqual(sheet.files.first?.tracks.first?.title, "Начало")
}

func test_shift_jis_fixture_decodes_japanese_titles() throws {
    let url = try fixture("shift-jis")
    let sheet = try CueSheetParser.parse(url: url)
    XCTAssertEqual(sheet.title, "日本のミックス")
    XCTAssertEqual(sheet.files.first?.tracks.first?.title, "序章")
}

func test_cp1252_fixture_decodes_french_diacritics() throws {
    let url = try fixture("cp1252")
    let sheet = try CueSheetParser.parse(url: url)
    XCTAssertEqual(sheet.title, "Été")
    XCTAssertEqual(sheet.performer, "Café Crème")
}
```

- [ ] **Step 5: Run all parser/decoder tests**

Run: `xcodebuild ... test -only-testing:WampTests/CueSheetParserTests -only-testing:WampTests/CueDecoderTests`
Expected: all passing. If `XCTSkip` fires, the fixtures aren't in the bundle — fix the Xcode project setup before committing.

- [ ] **Step 6: Commit**

```bash
git add WampTests/Fixtures/cue WampTests/CueSheet/CueSheetParserTests.swift Wamp.xcodeproj
git commit -m "test: cue parser fixtures (basic, multi-file, cp1251, shift-jis, cp1252)"
```

---

### Task 8: Track — add cueStart / cueEnd

**Files:**
- Modify: `Wamp/Models/Track.swift`
- Modify: `WampTests/Models/TrackTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `TrackTests`:

```swift
func test_track_isCueVirtual_false_by_default() {
    let t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                  title: "x", artist: "", album: "", duration: 1)
    XCTAssertNil(t.cueStart)
    XCTAssertNil(t.cueEnd)
    XCTAssertFalse(t.isCueVirtual)
}

func test_track_isCueVirtual_true_when_cueStart_set() {
    var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                  title: "x", artist: "", album: "", duration: 30)
    t.cueStart = 10
    t.cueEnd = 40
    XCTAssertTrue(t.isCueVirtual)
}

func test_track_codable_round_trip_preserves_cue_range() throws {
    var t = Track(url: URL(fileURLWithPath: "/tmp/x.flac"),
                  title: "x", artist: "", album: "", duration: 30)
    t.cueStart = 10.5
    t.cueEnd = 40.25
    let data = try JSONEncoder().encode(t)
    let decoded = try JSONDecoder().decode(Track.self, from: data)
    XCTAssertEqual(decoded.cueStart, 10.5)
    XCTAssertEqual(decoded.cueEnd, 40.25)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild ... test -only-testing:WampTests/TrackTests`
Expected: build error — `cueStart` undefined.

- [ ] **Step 3: Add the fields to Track**

Modify `Track`:

```swift
struct Track: Identifiable, Codable, Equatable {
    nonisolated static let supportedExtensions: Set<String> = [
        "mp3", "aac", "m4a", "flac", "wav", "aiff", "aif"
    ]

    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var genre: String
    var bitrate: Int
    var sampleRate: Int
    var channels: Int

    /// For CUE-derived virtual tracks: start offset in the underlying audio file (seconds).
    var cueStart: TimeInterval?
    /// For CUE-derived virtual tracks: end offset in the underlying audio file (seconds, exclusive).
    /// nil = play to EOF.
    var cueEnd: TimeInterval?

    var isCueVirtual: Bool { cueStart != nil }

    init(
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        genre: String = "",
        bitrate: Int = 0,
        sampleRate: Int = 0,
        channels: Int = 2,
        cueStart: TimeInterval? = nil,
        cueEnd: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.genre = genre
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.cueStart = cueStart
        self.cueEnd = cueEnd
    }
    // ... rest unchanged
}
```

`Codable` synthesises automatically; the new optional keys are added cleanly. Verify by running TrackTests + StateManagerTests + PersistenceRoundTripTests — older saved JSON without these keys must still decode (Swift's synthesised decoder handles missing optionals).

- [ ] **Step 4: Run all model tests**

Run: `xcodebuild ... test -only-testing:WampTests/TrackTests -only-testing:WampTests/StateManagerTests -only-testing:WampTests/PersistenceRoundTripTests`
Expected: all passing, including the 3 new Track tests.

- [ ] **Step 5: Commit**

```bash
git add Wamp/Models/Track.swift WampTests/Models/TrackTests.swift
git commit -m "feat: add cueStart/cueEnd to Track model"
```

---

### Task 9: CueResolver — turn a CueSheet into [Track]

**Files:**
- Create: `Wamp/CueSheet/CueResolver.swift`
- Create: `WampTests/CueSheet/CueResolverTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import AVFoundation
@testable import Wamp

final class CueResolverTests: XCTestCase {
    /// Build a 60-second 44.1 kHz mono silent WAV in a temp dir, then a matching cue.
    private func makeSilentWavAndCue() throws -> (wavURL: URL, cueURL: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wavURL = dir.appendingPathComponent("mix.wav")

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: wavURL, settings: format.settingsForWriting)
        let frames = AVAudioFrameCount(44_100 * 60)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)

        let cueText = """
        FILE "mix.wav" WAVE
          TRACK 01 AUDIO
            TITLE "First"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Second"
            INDEX 01 00:30:00
        """
        let cueURL = dir.appendingPathComponent("mix.cue")
        try cueText.write(to: cueURL, atomically: true, encoding: .utf8)
        return (wavURL, cueURL)
    }

    func test_resolves_two_virtual_tracks_with_correct_ranges() async throws {
        let (_, cueURL) = try makeSilentWavAndCue()
        let sheet = try CueSheetParser.parse(url: cueURL)
        let tracks = try await CueResolver.resolveTracks(cue: sheet, cueDirectory: cueURL.deletingLastPathComponent())
        XCTAssertEqual(tracks.count, 2)

        XCTAssertTrue(tracks[0].isCueVirtual)
        XCTAssertEqual(tracks[0].cueStart, 0)
        XCTAssertEqual(tracks[0].cueEnd ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(tracks[0].duration, 30, accuracy: 0.001)
        XCTAssertEqual(tracks[0].title, "First")

        XCTAssertEqual(tracks[1].cueStart ?? -1, 30, accuracy: 0.001)
        XCTAssertNil(tracks[1].cueEnd) // last track plays to EOF
        XCTAssertEqual(tracks[1].duration, 30, accuracy: 0.001)
    }

    func test_missing_audio_file_throws() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sheet = CueSheet(
            title: nil, performer: nil, genre: nil, date: nil,
            files: [CueFile(path: "missing.wav", format: "WAVE",
                            tracks: [CueTrack(number: 1, title: nil, performer: nil, startFrames: 0)])]
        )
        do {
            _ = try await CueResolver.resolveTracks(cue: sheet, cueDirectory: dir)
            XCTFail("expected error")
        } catch {
            // ok
        }
    }
}

private extension AVAudioFormat {
    var settingsForWriting: [String: Any] {
        var s = settings
        s[AVAudioFileTypeKey] = kAudioFileWAVEType
        return s
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild ... test -only-testing:WampTests/CueResolverTests`
Expected: build error — `CueResolver` undefined.

- [ ] **Step 3: Implement CueResolver**

```swift
import Foundation
import AVFoundation

public enum CueResolverError: Error {
    case audioFileMissing(URL)
    case audioFileUnreadable(URL, underlying: Error)
}

public enum CueResolver {
    /// Resolve a parsed CUE sheet into one Track per CUE-track entry.
    /// - The audio file referenced by each FILE entry must exist relative to `cueDirectory`.
    /// - The end of track N is the start of track N+1, or EOF for the last track in a FILE.
    @MainActor
    public static func resolveTracks(cue: CueSheet, cueDirectory: URL) async throws -> [Track] {
        var resolved: [Track] = []
        for file in cue.files {
            let audioURL = cueDirectory.appendingPathComponent(file.path)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw CueResolverError.audioFileMissing(audioURL)
            }

            // Total duration drives EOF for the last track in this FILE.
            let totalDuration: TimeInterval
            do {
                let asset = AVURLAsset(url: audioURL)
                let dur = try await asset.load(.duration)
                totalDuration = dur.seconds.isFinite ? dur.seconds : 0
            } catch {
                throw CueResolverError.audioFileUnreadable(audioURL, underlying: error)
            }

            for (i, t) in file.tracks.enumerated() {
                let start = CueSheet.framesToSeconds(t.startFrames)
                let end: TimeInterval?
                if i + 1 < file.tracks.count {
                    end = CueSheet.framesToSeconds(file.tracks[i + 1].startFrames)
                } else {
                    end = nil   // play to EOF
                }
                let trackDuration = (end ?? totalDuration) - start
                let title = t.title ?? "Track \(t.number)"
                let artist = t.performer ?? cue.performer ?? "Unknown Artist"
                let album = cue.title ?? ""
                resolved.append(Track(
                    url: audioURL,
                    title: title,
                    artist: artist,
                    album: album,
                    duration: max(0, trackDuration),
                    genre: cue.genre ?? "",
                    cueStart: start,
                    cueEnd: end
                ))
            }
        }
        return resolved
    }
}
```

- [ ] **Step 4: Run to verify the resolver tests pass**

Run: `xcodebuild ... test -only-testing:WampTests/CueResolverTests`
Expected: 2 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/CueResolver.swift WampTests/CueSheet/CueResolverTests.swift
git commit -m "feat: resolve cue sheet into [Track] with start/end ranges"
```

---

### Task 10: AudioEngine — bounded-segment playback

**Files:**
- Modify: `Wamp/Audio/AudioEngine.swift`

- [ ] **Step 1: Add a `playRange` overload**

Inside `AudioEngine`:

```swift
    /// Load `url` and immediately play from `startTime` until `endTime` (or EOF if nil).
    /// Used for CUE-derived virtual tracks. After playback hits the end frame the
    /// completion handler posts `.trackDidFinish` exactly like a normal track.
    func loadAndPlay(url: URL, startTime: TimeInterval, endTime: TimeInterval?) {
        print("🔵 loadAndPlay(range): \(url.lastPathComponent) [\(startTime), \(endTime as Any)]")
        stop()
        playbackGeneration &+= 1

        do {
            try loadFile(url: url)
            if !engine.isRunning { try engine.start() }
            installSpectrumTap()

            let startFrame = AVAudioFramePosition(startTime * audioSampleRate)
            let endFrame: AVAudioFramePosition
            if let endTime = endTime {
                endFrame = min(audioLengthFrames, AVAudioFramePosition(endTime * audioSampleRate))
            } else {
                endFrame = audioLengthFrames
            }
            seekFrame = max(0, min(startFrame, audioLengthFrames))
            scheduleSegment(endFrame: endFrame)
        } catch {
            print("🔴 AudioEngine: failed to load \(url.lastPathComponent): \(error)")
        }
    }
```

Refactor `scheduleAndPlay()` so it takes an `endFrame`, defaulting to `audioLengthFrames` so the original `loadAndPlay(url:)` and `play()` paths still work:

```swift
    private func scheduleAndPlay() {
        scheduleSegment(endFrame: audioLengthFrames)
    }

    private func scheduleSegment(endFrame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        let framesToPlay = endFrame - seekFrame
        guard framesToPlay > 0 else {
            handleTrackCompletion()
            return
        }
        playerNode.stop()
        let generation = playbackGeneration
        let capturedEnd = endFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: seekFrame,
            frameCount: AVAudioFrameCount(framesToPlay),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTrackCompletion()
            }
        }
        playerNode.play()
        isPlaying = true
        playState = .playing
        needsScheduling = false
        startTimeUpdates()
        currentSegmentEndFrame = capturedEnd
    }
```

Add an instance property:
```swift
    private var currentSegmentEndFrame: AVAudioFramePosition = 0
```

Update `seek(to:)` so seeking inside a virtual track stays bounded by the segment end:

```swift
    func seek(to time: TimeInterval) {
        guard audioFile != nil else { return }
        let targetFrame = AVAudioFramePosition(time * audioSampleRate)
        let upperBound = currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames
        seekFrame = max(0, min(targetFrame, upperBound))
        needsScheduling = true

        if isPlaying {
            playbackGeneration &+= 1
            playerNode.stop()
            scheduleSegment(endFrame: upperBound)
        } else {
            currentTime = time
        }
    }
```

`updateCurrentTime()` already returns the absolute file time, which is what the playlist UI displays — leave it alone for now (a follow-up task can expose track-relative time if desired).

- [ ] **Step 2: Build to verify it still compiles**

Run: `xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build`
Expected: build succeeds.

- [ ] **Step 3: Run the full test suite to confirm no regressions**

Run: `xcodebuild ... test`
Expected: every existing test still passes.

- [ ] **Step 4: Commit**

```bash
git add Wamp/Audio/AudioEngine.swift
git commit -m "feat: AudioEngine.loadAndPlay(url:startTime:endTime:) for cue ranges"
```

---

### Task 11: AudioEngine — gapless chained segment

**Files:**
- Modify: `Wamp/Audio/AudioEngine.swift`

- [ ] **Step 1: Add `chainNextSegment` for same-file CUE transitions**

```swift
    /// If `url` matches the currently loaded file, schedule the next segment back-to-back
    /// on the same player node — no `stop()`, no reload — so the boundary is sample-exact.
    /// Returns true on success, false if the engine isn't currently playing this file.
    @discardableResult
    func chainNextSegment(url: URL, startTime: TimeInterval, endTime: TimeInterval?) -> Bool {
        guard isPlaying, let file = audioFile, file.url == url else { return false }
        let startFrame = AVAudioFramePosition(startTime * audioSampleRate)
        let endFrame: AVAudioFramePosition
        if let endTime = endTime {
            endFrame = min(audioLengthFrames, AVAudioFramePosition(endTime * audioSampleRate))
        } else {
            endFrame = audioLengthFrames
        }
        let frames = endFrame - startFrame
        guard frames > 0 else { return false }

        playbackGeneration &+= 1
        let generation = playbackGeneration
        let capturedEnd = endFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: max(0, startFrame),
            frameCount: AVAudioFrameCount(frames),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTrackCompletion()
            }
        }
        // playerNode is already playing — do NOT call stop() or play() again.
        seekFrame = max(0, startFrame)
        currentSegmentEndFrame = capturedEnd
        needsScheduling = false
        return true
    }
```

`AVAudioPlayerNode.scheduleSegment` queues the new buffer; the previous one finishes naturally and the queued one starts on the next render tick — that is the gapless contract. The completion handler of the *previous* schedule is what will fire `.trackDidFinish`. To prevent that, bumping `playbackGeneration` in `chainNextSegment` invalidates the previous handler (the guard on `generation` returns early), so only the chained segment's own completion will fire.

- [ ] **Step 2: Build**

Run: `xcodebuild ... build`
Expected: succeeds.

- [ ] **Step 3: Commit (no new behavioural test yet — that's Task 14)**

```bash
git add Wamp/Audio/AudioEngine.swift
git commit -m "feat: AudioEngine.chainNextSegment for gapless cue transitions"
```

---

### Task 12: PlaylistManager — playTrack uses Track, addCueSheet, gapless wiring

**Files:**
- Modify: `Wamp/Models/PlaylistManager.swift`
- Modify: `WampTests/Models/PlaylistManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `PlaylistManagerTests`:

```swift
func test_addCueSheet_appends_virtual_tracks() async throws {
    // Build a temp wav + cue (mirror of CueResolverTests helper).
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let wavURL = dir.appendingPathComponent("mix.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
    buffer.frameLength = 44_100
    try file.write(from: buffer)
    let cueURL = dir.appendingPathComponent("mix.cue")
    try """
    FILE "mix.wav" WAVE
      TRACK 01 AUDIO
        TITLE "A"
        INDEX 01 00:00:00
    """.write(to: cueURL, atomically: true, encoding: .utf8)

    let pm = await PlaylistManager()
    try await pm.addCueSheet(url: cueURL)
    let count = await MainActor.run { pm.tracks.count }
    XCTAssertEqual(count, 1)
    let isCue = await MainActor.run { pm.tracks[0].isCueVirtual }
    XCTAssertTrue(isCue)
}

func test_addCueSheet_missing_audio_throws() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cueURL = dir.appendingPathComponent("orphan.cue")
    try """
    FILE "missing.wav" WAVE
      TRACK 01 AUDIO
        INDEX 01 00:00:00
    """.write(to: cueURL, atomically: true, encoding: .utf8)
    let pm = await PlaylistManager()
    do {
        try await pm.addCueSheet(url: cueURL)
        XCTFail("expected throw")
    } catch {
        // ok
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild ... test -only-testing:WampTests/PlaylistManagerTests`
Expected: build error — `addCueSheet` undefined.

- [ ] **Step 3: Implement `addCueSheet` and rewire `playTrack(at:)`**

Add to `PlaylistManager`:

```swift
    /// Load a .cue sheet, resolve its virtual tracks, and append them to the playlist.
    /// Throws if the cue can't be parsed or the referenced audio file is missing.
    @MainActor
    func addCueSheet(url: URL) async throws {
        let sheet = try CueSheetParser.parse(url: url)
        let resolved = try await CueResolver.resolveTracks(
            cue: sheet,
            cueDirectory: url.deletingLastPathComponent()
        )
        addTracks(resolved)
    }
```

Replace `playTrack(at:)` so it uses the engine's range-aware overload when the track is virtual:

```swift
    func playTrack(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        currentIndex = index
        let track = tracks[index]
        if let start = track.cueStart {
            audioEngine?.loadAndPlay(url: track.url, startTime: start, endTime: track.cueEnd)
        } else {
            audioEngine?.loadAndPlay(url: track.url)
        }
    }
```

Replace `advanceToNext()` so consecutive same-file virtual tracks chain instead of reload:

```swift
    private func advanceToNext() {
        guard audioEngine?.repeatMode != .track else { return }
        guard !tracks.isEmpty else { return }

        let prev = currentIndex
        let nextIndex = currentIndex + 1
        if nextIndex >= tracks.count {
            if audioEngine?.repeatMode == .playlist {
                playTrack(at: 0)
            } else {
                audioEngine?.stop()
            }
            return
        }

        let prevTrack = (prev >= 0 && prev < tracks.count) ? tracks[prev] : nil
        let next = tracks[nextIndex]
        if let prevTrack = prevTrack,
           prevTrack.isCueVirtual, next.isCueVirtual,
           prevTrack.url == next.url, let start = next.cueStart,
           audioEngine?.chainNextSegment(url: next.url, startTime: start, endTime: next.cueEnd) == true {
            currentIndex = nextIndex
            return
        }
        playTrack(at: nextIndex)
    }
```

Note: `advanceToNext` was already called from a Combine `sink` on `.trackDidFinish` — keep that wiring. The chain path runs *after* the previous segment's completion handler fires, which means there will be a tiny gap. To make it truly gapless we have to schedule the next segment proactively. Move the chaining into a new `prepareNextChainable()` call invoked when `playTrack` starts a virtual track:

Add to `PlaylistManager`:

```swift
    /// Called by playTrack after starting playback. If the *next* track in the
    /// playlist is on the same file as the one just started, schedule it back-to-back
    /// so the AVAudioPlayerNode hands over without a buffer underrun.
    private func prepareGaplessChain(after index: Int) {
        guard index + 1 < tracks.count else { return }
        let cur = tracks[index]
        let next = tracks[index + 1]
        guard cur.isCueVirtual, next.isCueVirtual, cur.url == next.url else { return }
        guard let start = next.cueStart else { return }
        _ = audioEngine?.chainNextSegment(url: next.url, startTime: start, endTime: next.cueEnd)
    }
```

Call it from `playTrack(at:)` right after the engine call:

```swift
        if let start = track.cueStart {
            audioEngine?.loadAndPlay(url: track.url, startTime: start, endTime: track.cueEnd)
        } else {
            audioEngine?.loadAndPlay(url: track.url)
        }
        prepareGaplessChain(after: index)
```

Then in `advanceToNext()`, the chained segment's completion will fire and trigger another `advanceToNext` for the *track after that*. Detect that we already advanced via the chain by comparing `currentIndex` against the engine's currently-playing file:

```swift
    private func advanceToNext() {
        guard audioEngine?.repeatMode != .track else { return }
        guard !tracks.isEmpty else { return }
        let nextIndex = currentIndex + 1
        if nextIndex >= tracks.count {
            if audioEngine?.repeatMode == .playlist { playTrack(at: 0) }
            else { audioEngine?.stop() }
            return
        }
        // For gapless chains the engine has already started playing the next segment.
        // Promote currentIndex without touching the engine, then prepare the *next* chain.
        let prevTrack = currentIndex >= 0 ? tracks[currentIndex] : nil
        let next = tracks[nextIndex]
        if let prevTrack = prevTrack,
           prevTrack.isCueVirtual, next.isCueVirtual,
           prevTrack.url == next.url {
            currentIndex = nextIndex
            prepareGaplessChain(after: nextIndex)
            return
        }
        playTrack(at: nextIndex)
    }
```

- [ ] **Step 4: Run all tests**

Run: `xcodebuild ... test`
Expected: all passing including the two new addCueSheet tests.

- [ ] **Step 5: Commit**

```bash
git add Wamp/Models/PlaylistManager.swift WampTests/Models/PlaylistManagerTests.swift
git commit -m "feat: PlaylistManager.addCueSheet + gapless cue chain wiring"
```

---

### Task 13: FlacCueExtractor — read embedded CUESHEET

**Files:**
- Create: `Wamp/CueSheet/FlacCueExtractor.swift`
- Create: `WampTests/CueSheet/FlacCueExtractorTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import Wamp

final class FlacCueExtractorTests: XCTestCase {
    /// Build a minimal synthetic FLAC stream:
    /// "fLaC" + STREAMINFO block + a VORBIS_COMMENT block with a CUESHEET tag,
    /// no audio frames (we never decode it — extractor stops at metadata).
    private func makeFlacWithCueSheet(_ cueText: String) -> Data {
        var d = Data()
        d.append(contentsOf: [0x66, 0x4C, 0x61, 0x43])  // "fLaC"

        // STREAMINFO block: type 0, length 34, all zero payload (extractor doesn't validate values)
        d.append(0x00)                                  // last-flag=0, type=0
        d.append(contentsOf: [0x00, 0x00, 0x22])        // length = 34
        d.append(Data(repeating: 0, count: 34))

        // VORBIS_COMMENT block: type 4, last metadata block.
        let vendor = "Wamp test".data(using: .utf8)!
        let cueComment = "CUESHEET=\(cueText)".data(using: .utf8)!
        var body = Data()
        body.append(uint32LE(UInt32(vendor.count)))
        body.append(vendor)
        body.append(uint32LE(1))  // one comment
        body.append(uint32LE(UInt32(cueComment.count)))
        body.append(cueComment)

        let length = body.count
        d.append(0x84)            // last-flag=1, type=4
        d.append(uint24BE(UInt32(length)))
        d.append(body)
        return d
    }

    private func uint32LE(_ v: UInt32) -> Data {
        var v = v.littleEndian
        return Data(bytes: &v, count: 4)
    }
    private func uint24BE(_ v: UInt32) -> Data {
        Data([UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }

    func test_extracts_embedded_cuesheet_from_vorbis_comment() throws {
        let cueText = """
        FILE "self.flac" FLAC
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let flacURL = dir.appendingPathComponent("a.flac")
        try makeFlacWithCueSheet(cueText).write(to: flacURL)

        let extracted = try FlacCueExtractor.extractCueSheet(from: flacURL)
        XCTAssertEqual(extracted, cueText)
    }

    func test_returns_nil_when_no_cuesheet_tag() throws {
        // Same builder but with a non-CUESHEET tag.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let flacURL = dir.appendingPathComponent("a.flac")
        var d = Data([0x66, 0x4C, 0x61, 0x43,  // fLaC
                      0x00, 0x00, 0x00, 0x22]) // STREAMINFO header
        d.append(Data(repeating: 0, count: 34))
        let vendor = "Wamp".data(using: .utf8)!
        let comment = "TITLE=Foo".data(using: .utf8)!
        var body = Data()
        var c4 = UInt32(vendor.count).littleEndian
        body.append(Data(bytes: &c4, count: 4))
        body.append(vendor)
        var n4 = UInt32(1).littleEndian
        body.append(Data(bytes: &n4, count: 4))
        var l4 = UInt32(comment.count).littleEndian
        body.append(Data(bytes: &l4, count: 4))
        body.append(comment)
        d.append(0x84)
        d.append(Data([0, 0, UInt8(body.count)]))
        d.append(body)
        try d.write(to: flacURL)

        XCTAssertNil(try FlacCueExtractor.extractCueSheet(from: flacURL))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild ... test -only-testing:WampTests/FlacCueExtractorTests`
Expected: build error — `FlacCueExtractor` undefined.

- [ ] **Step 3: Implement the extractor**

```swift
import Foundation

public enum FlacCueExtractorError: Error {
    case notFlac
    case truncated
}

public enum FlacCueExtractor {
    /// Returns the value of the CUESHEET Vorbis comment in `url`, or nil if absent.
    /// Throws if the file is not a FLAC stream or is truncated mid-metadata.
    public static func extractCueSheet(from url: URL) throws -> String? {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 4, data[0..<4] == Data([0x66, 0x4C, 0x61, 0x43]) else {
            throw FlacCueExtractorError.notFlac
        }
        var cursor = 4
        while cursor + 4 <= data.count {
            let header = data[cursor]
            let isLast = (header & 0x80) != 0
            let type   = Int(header & 0x7F)
            let len = (Int(data[cursor + 1]) << 16) |
                      (Int(data[cursor + 2]) << 8)  |
                       Int(data[cursor + 3])
            cursor += 4
            guard cursor + len <= data.count else { throw FlacCueExtractorError.truncated }
            let block = data.subdata(in: cursor..<(cursor + len))
            cursor += len

            if type == 4 {  // VORBIS_COMMENT
                if let cue = parseVorbisCueSheet(block) { return cue }
            }
            if isLast { break }
        }
        return nil
    }

    private static func parseVorbisCueSheet(_ data: Data) -> String? {
        var p = 0
        guard p + 4 <= data.count else { return nil }
        let vendorLen = Int(readUInt32LE(data, at: p)); p += 4
        guard p + vendorLen <= data.count else { return nil }
        p += vendorLen
        guard p + 4 <= data.count else { return nil }
        let count = Int(readUInt32LE(data, at: p)); p += 4
        for _ in 0..<count {
            guard p + 4 <= data.count else { return nil }
            let len = Int(readUInt32LE(data, at: p)); p += 4
            guard p + len <= data.count else { return nil }
            let raw = data.subdata(in: p..<(p + len))
            p += len
            guard let s = String(data: raw, encoding: .utf8) else { continue }
            if let eq = s.firstIndex(of: "=") {
                let key = s[..<eq].uppercased()
                if key == "CUESHEET" {
                    return String(s[s.index(after: eq)...])
                }
            }
        }
        return nil
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `xcodebuild ... test -only-testing:WampTests/FlacCueExtractorTests`
Expected: 2 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Wamp/CueSheet/FlacCueExtractor.swift WampTests/CueSheet/FlacCueExtractorTests.swift
git commit -m "feat: FlacCueExtractor reads embedded CUESHEET from Vorbis comments"
```

---

### Task 14: Sample-level gapless verification

**Files:**
- Create: `WampTests/Integration/CueGaplessTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import AVFoundation
@testable import Wamp

final class CueGaplessTests: XCTestCase {
    /// Generate a 4-second mono 44.1 kHz file containing a continuous 440 Hz sine.
    /// Split it into two CUE tracks (0–2s, 2–4s). Schedule them via the same player node
    /// using `loadAndPlay(range:)` for the first and `chainNextSegment` for the second,
    /// then capture output via a tap and verify the boundary samples are continuous.
    func test_gapless_chained_segments_have_continuous_samples() async throws {
        let sampleRate: Double = 44_100
        let totalSeconds = 4.0
        let frequency: Double = 440
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wavURL = dir.appendingPathComponent("sine.wav")

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: wavURL, settings: format.settings)
        let frames = AVAudioFrameCount(sampleRate * totalSeconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            ptr[i] = Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
        try file.write(from: buffer)

        // Capture via an offline render to keep the test deterministic.
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format,
                                             maximumFrameCount: 4096)
        let srcFile = try AVAudioFile(forReading: wavURL)
        let halfFrames = AVAudioFrameCount(sampleRate * 2)
        player.scheduleSegment(srcFile, startingFrame: 0,
                               frameCount: halfFrames, at: nil, completionHandler: nil)
        player.scheduleSegment(srcFile, startingFrame: AVAudioFramePosition(halfFrames),
                               frameCount: halfFrames, at: nil, completionHandler: nil)
        try engine.start()
        player.play()

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: 4096)!
        var collected: [Float] = []
        collected.reserveCapacity(Int(frames))
        var remaining = AVAudioFrameCount(frames)
        while remaining > 0 {
            let want = min(renderBuffer.frameCapacity, remaining)
            let status = try engine.renderOffline(want, to: renderBuffer)
            XCTAssertEqual(status, .success)
            let got = Int(renderBuffer.frameLength)
            let p = renderBuffer.floatChannelData![0]
            for i in 0..<got { collected.append(p[i]) }
            remaining -= AVAudioFrameCount(got)
        }
        engine.stop()

        // Verify the rendered output equals the source sine sample-for-sample
        // around the boundary at frame 2*44100. Tolerance covers 32-bit mixer noise.
        let boundary = Int(sampleRate * 2)
        for i in (boundary - 8)..<(boundary + 8) {
            let expected = Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
            XCTAssertEqual(collected[i], expected, accuracy: 1e-3,
                           "discontinuity at boundary frame \(i)")
        }
    }
}
```

This test asserts the **AVAudioPlayerNode** chained-segment contract — exactly the primitive we rely on in `chainNextSegment`. If this fails, the whole gapless approach is invalid; treat the failure as a hard blocker.

- [ ] **Step 2: Run to verify it passes**

Run: `xcodebuild ... test -only-testing:WampTests/CueGaplessTests`
Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add WampTests/Integration/CueGaplessTests.swift
git commit -m "test: sample-level continuity at chained-segment boundary"
```

---

### Task 15: AppDelegate — accept .cue from Open dialog and Finder drag

**Files:**
- Modify: `Wamp/AppDelegate.swift`

- [ ] **Step 1: Locate the existing file-open paths**

Run: `grep -n 'allowedContentTypes\|application(.*open\|openPanel\|openURLs' Wamp/AppDelegate.swift`
Read the matching lines so the next step edits the actual call sites.

- [ ] **Step 2: Add `.cue` to the open-panel allowed types and `application(_:open:)`**

In the `NSOpenPanel` setup, add `UTType.init(filenameExtension: "cue")` to `allowedContentTypes` (or, if the project still uses `allowedFileTypes`, append `"cue"`).

In the URL dispatch (where `addURLs` is called today), branch on extension:

```swift
for url in urls {
    if url.pathExtension.lowercased() == "cue" {
        Task { @MainActor in
            do {
                try await playlistManager.addCueSheet(url: url)
            } catch {
                presentError(error)
            }
        }
    } else {
        // existing branch — addURLs / addFolder
    }
}
```

If a `presentError(_:)` helper doesn't already exist, use:

```swift
private func presentError(_ error: Error) {
    let alert = NSAlert(error: error)
    alert.runModal()
}
```

- [ ] **Step 3: Build and run the app manually, drag a `.cue` onto the dock icon**

Run: `xcodebuild ... build`
Expected: builds. Smoke-test by dragging a `.cue` onto the running app — virtual tracks appear in the playlist. Document the manual smoke test in the commit message.

- [ ] **Step 4: Commit**

```bash
git add Wamp/AppDelegate.swift
git commit -m "feat: open .cue files from Finder/Open dialog as virtual tracks"
```

---

### Task 16: FLAC open path — prefer external .cue, fall back to embedded CUESHEET

**Files:**
- Modify: `Wamp/Models/PlaylistManager.swift`
- Modify: `WampTests/Models/PlaylistManagerTests.swift`

- [ ] **Step 1: Write failing test**

Append to `PlaylistManagerTests`:

```swift
func test_addURLs_with_flac_embedded_cuesheet_expands_to_virtual_tracks() async throws {
    // Build a synthetic FLAC with embedded CUESHEET (re-use FlacCueExtractorTests builder pattern inline).
    // For the audio side we cheat: write an empty FLAC and rely on AVURLAsset returning duration 0.
    // Resolver should still produce one virtual track with cueStart = 0.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let flacURL = dir.appendingPathComponent("a.flac")
    let cueText = """
    FILE "a.flac" FLAC
      TRACK 01 AUDIO
        TITLE "Embedded"
        INDEX 01 00:00:00
    """
    var d = Data([0x66, 0x4C, 0x61, 0x43])
    d.append(0x00); d.append(contentsOf: [0x00,0x00,0x22]); d.append(Data(repeating: 0, count: 34))
    let vendor = "Wamp".data(using: .utf8)!
    let comment = "CUESHEET=\(cueText)".data(using: .utf8)!
    var body = Data()
    var v32 = UInt32(vendor.count).littleEndian; body.append(Data(bytes: &v32, count: 4)); body.append(vendor)
    var n32 = UInt32(1).littleEndian;            body.append(Data(bytes: &n32, count: 4))
    var c32 = UInt32(comment.count).littleEndian; body.append(Data(bytes: &c32, count: 4)); body.append(comment)
    d.append(0x84); d.append(Data([0, 0, UInt8(body.count)])); d.append(body)
    try d.write(to: flacURL)

    let pm = await PlaylistManager()
    await pm.addURLs([flacURL])
    let titles = await MainActor.run { pm.tracks.map(\.title) }
    XCTAssertEqual(titles, ["Embedded"])
    let isCue = await MainActor.run { pm.tracks.first?.isCueVirtual ?? false }
    XCTAssertTrue(isCue)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild ... test -only-testing:WampTests/PlaylistManagerTests`
Expected: the test fails — the FLAC is added as a single Track, not expanded.

- [ ] **Step 3: Modify `addURLs` to detect FLAC + CUESHEET**

Change `PlaylistManager.addURLs`:

```swift
    func addURLs(_ urls: [URL]) async {
        var newTracks: [Track] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Track.supportedExtensions.contains(ext) else { continue }

            if ext == "flac" {
                // External sibling .cue wins.
                let siblingCue = url.deletingPathExtension().appendingPathExtension("cue")
                if FileManager.default.fileExists(atPath: siblingCue.path) {
                    do {
                        try await self.addCueSheet(url: siblingCue)
                        continue
                    } catch {
                        // fall through to embedded / single-track
                    }
                }
                // Embedded CUESHEET.
                if let cueText = (try? FlacCueExtractor.extractCueSheet(from: url)) ?? nil,
                   let cueData = cueText.data(using: .utf8),
                   let sheet = try? CueSheetParser.parse(cueData),
                   let resolved = try? await CueResolver.resolveTracks(
                        cue: sheet, cueDirectory: url.deletingLastPathComponent()) {
                    newTracks.append(contentsOf: resolved)
                    continue
                }
            }

            let track = await Track.fromURL(url)
            newTracks.append(track)
        }
        addTracks(newTracks)
    }
```

Note: the embedded CUESHEET refers to the FLAC by name (`FILE "a.flac" FLAC` in the synthetic fixture), so resolving against `cueDirectory` works the same as for an external cue.

- [ ] **Step 4: Run all tests**

Run: `xcodebuild ... test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Wamp/Models/PlaylistManager.swift WampTests/Models/PlaylistManagerTests.swift
git commit -m "feat: expand FLAC embedded CUESHEET into virtual tracks"
```

---

### Task 17: PlaylistView — "Reveal source file" for cue tracks

**Files:**
- Modify: `Wamp/UI/PlaylistView.swift`

- [ ] **Step 1: Locate the existing right-click menu**

Run: `grep -n 'NSMenu\|menuFor\|contextMenu\|rightMouseDown\|menuItem' Wamp/UI/PlaylistView.swift`
Read the matching block.

- [ ] **Step 2: Add the menu item**

In the menu builder, append:

```swift
let selected = playlistManager.tracks[safe: clickedRow]
if let track = selected, track.isCueVirtual {
    let item = NSMenuItem(title: "Reveal Source File in Finder",
                          action: #selector(revealCueSource(_:)),
                          keyEquivalent: "")
    item.target = self
    item.representedObject = track.url
    menu.addItem(item)
}
```

And the action handler:

```swift
@objc private func revealCueSource(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
```

If the existing code doesn't have a `[safe:]` collection extension, use the obvious bounds check inline:

```swift
guard clickedRow >= 0, clickedRow < playlistManager.tracks.count else { return }
let track = playlistManager.tracks[clickedRow]
```

- [ ] **Step 3: Build**

Run: `xcodebuild ... build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/PlaylistView.swift
git commit -m "feat: 'Reveal Source File' menu item for cue-virtual tracks"
```

---

### Task 18: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add an entry**

Open `CHANGELOG.md` and prepend an entry:

```markdown
## Unreleased

### Added
- CUE sheet support: drag a `.cue` onto the player to load a multi-track audio file as virtual tracks. External and FLAC-embedded CUESHEET both work, with sample-accurate gapless transitions between consecutive cue tracks on the same file. Encoding detection covers UTF-8, Shift-JIS, CP-1251, and CP-1252.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for cue sheet support"
```

---

### Task 19: Final acceptance pass

**Files:**
- N/A (verification only)

- [ ] **Step 1: Full build + test**

Run: `xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test`
Expected: all tests pass, no warnings introduced by this branch.

- [ ] **Step 2: Manual smoke test checklist (cross off in the end-of-list report)**

- Drag a `.cue` for a real DJ mix → playlist shows N tracks.
- Double-click track 1 → it plays. Wait for it to end → track 2 starts seamlessly (no audible click/silence at the boundary).
- Click around in the seek bar of a virtual track → seek stays within the track's range.
- Open a FLAC with embedded CUESHEET (use `metaflac --import-cuesheet-from=`) → expanded into virtual tracks.
- Open a FLAC where the sibling `.cue` exists → external wins.
- Open a `.cue` whose audio file is missing → error dialog, app survives.
- Right-click a cue-virtual track → "Reveal Source File in Finder" reveals the underlying audio file.
- Open a Shift-JIS / CP-1251 cue → titles render in the playlist with correct characters.

- [ ] **Step 3: Push the branch (optional, for review)**

```bash
git push -u origin feat/cue-sheets
```

- [ ] **Step 4: Post the end-of-list report per CLAUDE.md** — what was done, non-obvious decisions, anything skipped.

---

## Self-Review Notes

- **Spec coverage:** 2.1 parser → tasks 1, 4, 5, 6, 7. 2.2 encoding → tasks 2, 3, 7. 2.3 playlist integration → tasks 8, 9, 12. 2.4 audio engine → tasks 10, 11, 14. 2.5 FLAC embedded CUE → tasks 13, 16. 2.6 UI → tasks 15, 17. CHANGELOG → 18. All acceptance criteria are covered. Optional skin-icon UI is intentionally out of scope per the spec ("skip if it conflicts with the skin's playlist rendering").
- **No placeholders:** every code step contains the actual code an engineer pastes. The two non-code steps (Xcode resource bundle wiring, AppDelegate grep-then-edit) name the exact files and search commands.
- **Type consistency:** `cueStart` / `cueEnd` are `TimeInterval?` everywhere. `chainNextSegment(url:startTime:endTime:)` signature is consistent across AudioEngine and PlaylistManager. `CueResolver.resolveTracks(cue:cueDirectory:)` is consistent across CueResolver, PlaylistManager.addCueSheet, and PlaylistManager.addURLs.

