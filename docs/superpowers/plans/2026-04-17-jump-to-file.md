# Jump-to-File Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Cmd+J / Ctrl+J modal "Jump to file" dialog with incremental, ranked search over the current playlist.

**Architecture:** Pure-logic `JumpFilter` in `Models/` (TDD-tested, ranks prefix > word-boundary > substring) + an AppKit `NSPanel` subclass `JumpToFileWindow` in `UI/` that hosts an `NSSearchField` over an `NSTableView`. AppDelegate owns one lazy panel instance and exposes a `presentJumpToFileWindow()` action wired to the menu (Cmd+J) and a local `NSEvent` monitor (Ctrl+J).

**Tech Stack:** Swift 5.9, AppKit (no SwiftUI), Swift Testing framework (`@Test` / `#expect`), Combine for model bindings.

---

## File Structure

**Create:**
- `Wamp/Models/JumpFilter.swift` — pure matching/ranking logic. Returns `[Match]` with original playlist indices.
- `Wamp/UI/JumpToFileWindow.swift` — `NSPanel` subclass; owns the search field, table view, status label, "Go to current" button. Calls back to a `JumpToFileDelegate` for "play index N".
- `WampTests/Models/JumpFilterTests.swift` — unit tests for `JumpFilter`.
- `WampTests/Integration/JumpToFilePlaybackTests.swift` — model-level integration: filter → select → `PlaylistManager.playTrack(at:)` updates `currentIndex`.
- `CHANGELOG.md` — top-level changelog (does not exist yet).

**Modify:**
- `Wamp/AppDelegate.swift` — own one lazy `JumpToFileWindow`; add `@objc presentJumpToFileWindow()`; add menu item under Controls (Cmd+J); install `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` for Ctrl+J.

**Why a separate `JumpFilter` file:** matching is the only piece that needs unit tests (per CLAUDE.md, tests cover `Models/` only). Keeping it pure (no AppKit, no PlaylistManager dep — takes `[(index: Int, displayTitle: String, filename: String)]`) makes it trivially testable.

**Why no edits to `Track.swift`:** Track is `Codable` and persisted to disk; adding a non-encoded precomputed haystack adds ceremony. Instead, `JumpFilter` lowercases on the fly per call. For 10k tracks × ~50-char haystack, lowercasing + substring check on M1 measures well under 16ms — we'll verify in Task 1 with a perf assertion. If it ever becomes a bottleneck, adding a cached `lowerHaystack` to `PlaylistManager` is a contained follow-up.

**Project setup:** `Wamp.xcodeproj` uses `fileSystemSynchronizedGroups` — files dropped into `Wamp/` and `WampTests/` are picked up automatically. **No xcodeproj edits needed.**

---

## Task 1: `JumpFilter` model with TDD

**Files:**
- Create: `Wamp/Models/JumpFilter.swift`
- Test:   `WampTests/Models/JumpFilterTests.swift`

- [ ] **Step 1: Branch off main**

```bash
git checkout main
git pull --ff-only
git checkout -b feat/jump-to-file
```

- [ ] **Step 2: Write the failing tests**

Create `WampTests/Models/JumpFilterTests.swift` exactly:

```swift
import Testing
import Foundation
@testable import Wamp

@Suite("JumpFilter")
struct JumpFilterTests {

    private func candidates(_ items: [(String, String)]) -> [JumpFilter.Candidate] {
        items.enumerated().map { idx, pair in
            JumpFilter.Candidate(index: idx, displayTitle: pair.0, filename: pair.1)
        }
    }

    @Test func emptyQuery_returnsAllInOriginalOrder() {
        let cs = candidates([("Pink Floyd - Money", "money.mp3"),
                             ("Queen - Bohemian Rhapsody", "queen.mp3")])
        let result = JumpFilter.filter(query: "", candidates: cs)
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func whitespaceOnlyQuery_returnsAll() {
        let cs = candidates([("a", "a.mp3"), ("b", "b.mp3")])
        let result = JumpFilter.filter(query: "   ", candidates: cs)
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func substring_caseInsensitive_matchesArtistOrTitle() {
        let cs = candidates([("Pink Floyd - Money", "01.mp3"),
                             ("Queen - Bohemian Rhapsody", "02.mp3"),
                             ("Daft Punk - Around the World", "03.mp3")])
        let result = JumpFilter.filter(query: "pink", candidates: cs)
        #expect(result.map(\.index) == [0])
    }

    @Test func substring_fallsBackToFilenameWhenDisplayTitleDoesNotMatch() {
        let cs = candidates([("Untitled - Untitled", "rare-keyword.mp3")])
        let result = JumpFilter.filter(query: "rare", candidates: cs)
        #expect(result.map(\.index) == [0])
    }

    @Test func ranking_prefixBeatsWordBoundaryBeatsSubstring() {
        // "abc" appears in three different positions:
        //   index 0: substring deep inside ("xyzabcxyz")        -> tier 3
        //   index 1: word-boundary in middle ("foo abcdef")     -> tier 2
        //   index 2: prefix at very start ("abcdef ghi")        -> tier 1
        let cs = candidates([("xyzabcxyz", "0.mp3"),
                             ("foo abcdef", "1.mp3"),
                             ("abcdef ghi", "2.mp3")])
        let result = JumpFilter.filter(query: "abc", candidates: cs)
        #expect(result.map(\.index) == [2, 1, 0])
    }

    @Test func ranking_withinSameTier_preservesOriginalOrder() {
        // All three are pure substring matches at identical positions.
        let cs = candidates([("xxabcxx", "0.mp3"),
                             ("yyabcyy", "1.mp3"),
                             ("zzabczz", "2.mp3")])
        let result = JumpFilter.filter(query: "abc", candidates: cs)
        #expect(result.map(\.index) == [0, 1, 2])
    }

    @Test func wordBoundary_matchesAfterDashOrSpace() {
        // "dash - rider" -> 'r' at index 7 is a word boundary (preceded by space).
        // "underdash"    -> 'd' at index 5 is a substring (no boundary).
        let cs = candidates([("alpha - rider", "0.mp3"),
                             ("alpharider", "1.mp3")])
        let result = JumpFilter.filter(query: "rider", candidates: cs)
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func noMatches_returnsEmpty() {
        let cs = candidates([("a", "a.mp3"), ("b", "b.mp3")])
        let result = JumpFilter.filter(query: "zzzz", candidates: cs)
        #expect(result.isEmpty)
    }

    @Test func performance_under16msFor10kTracks() {
        // Generate 10k synthetic tracks. Half of them contain "abc" somewhere.
        let cs: [JumpFilter.Candidate] = (0..<10_000).map { i in
            let display = i % 2 == 0
                ? "Artist\(i) - Track abc \(i)"
                : "Other\(i) - Random \(i)"
            return JumpFilter.Candidate(index: i, displayTitle: display, filename: "\(i).mp3")
        }
        let start = Date()
        _ = JumpFilter.filter(query: "abc", candidates: cs)
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        #expect(elapsedMs < 16, "JumpFilter took \(elapsedMs)ms on 10k tracks (target <16ms)")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail (compile error: no JumpFilter)**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -40
```
Expected: build failure citing `cannot find 'JumpFilter' in scope`.

- [ ] **Step 4: Implement `JumpFilter`**

Create `Wamp/Models/JumpFilter.swift`:

```swift
import Foundation

/// Pure substring-with-ranking matcher used by the Jump-to-file dialog.
///
/// Three tiers (lower number = better match):
///   1. Prefix:        query matches at the very start of the haystack
///   2. Word boundary: query matches right after a space or dash
///   3. Substring:     query matches anywhere else
///
/// Within a tier, original `index` order is preserved (stable sort).
enum JumpFilter {
    struct Candidate {
        let index: Int
        let displayTitle: String  // e.g. "Pink Floyd - Money"
        let filename: String      // e.g. "track01.mp3"
    }

    struct Match {
        let index: Int
        let tier: Int
    }

    /// Returns matches ordered by tier then original index.
    /// Empty/whitespace query returns every candidate in its original order.
    static func filter(query: String, candidates: [Candidate]) -> [Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            return candidates.map { Match(index: $0.index, tier: 0) }
        }

        var matches: [Match] = []
        matches.reserveCapacity(candidates.count)

        for c in candidates {
            let t = tier(for: trimmed, in: c.displayTitle.lowercased())
            if t > 0 {
                matches.append(Match(index: c.index, tier: t))
                continue
            }
            // Fallback to filename
            let ft = tier(for: trimmed, in: c.filename.lowercased())
            if ft > 0 {
                matches.append(Match(index: c.index, tier: ft))
            }
        }

        // Stable sort: Swift's sort is not guaranteed stable, so we encode
        // the original position into a secondary key.
        let indexed = matches.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.1.tier != rhs.1.tier { return lhs.1.tier < rhs.1.tier }
            return lhs.0 < rhs.0
        }
        return sorted.map { $0.1 }
    }

    /// Returns 1 (prefix), 2 (word boundary), 3 (substring), or 0 (no match).
    /// `query` and `haystack` must already be lowercased.
    private static func tier(for query: String, in haystack: String) -> Int {
        guard !query.isEmpty, !haystack.isEmpty else { return 0 }
        if haystack.hasPrefix(query) { return 1 }
        guard let range = haystack.range(of: query) else { return 0 }
        let prevIdx = haystack.index(before: range.lowerBound)
        let prev = haystack[prevIdx]
        if prev == " " || prev == "-" || prev == "\t" { return 2 }
        return 3
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: all 9 `JumpFilter` tests pass. The performance test should report comfortably under 16ms.

- [ ] **Step 6: Commit**

```bash
git add Wamp/Models/JumpFilter.swift WampTests/Models/JumpFilterTests.swift
git commit -m "feat: add JumpFilter ranked matcher for jump-to-file"
```

---

## Task 2: `JumpToFileWindow` panel scaffolding (no filtering yet)

**Files:**
- Create: `Wamp/UI/JumpToFileWindow.swift`

This task gets the panel on screen with a search field, an empty table, and a status label — wired only enough that we can manually open it via a temporary `presentJumpToFileWindow()` call we'll add in Task 6.

- [ ] **Step 1: Create `JumpToFileWindow.swift`**

```swift
import Cocoa

/// Delegate that JumpToFileWindow calls back to. Implemented by AppDelegate.
protocol JumpToFileDelegate: AnyObject {
    /// All tracks in the playlist, in playlist order.
    var jumpCandidates: [JumpFilter.Candidate] { get }
    /// Index of the currently-playing track, or nil.
    var currentTrackIndex: Int? { get }
    /// Play the track at the given playlist index.
    func playTrack(atPlaylistIndex index: Int)
}

final class JumpToFileWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    weak var jumpDelegate: JumpToFileDelegate?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let goToCurrentButton = NSButton(title: "Go to current", target: nil, action: nil)

    private var matches: [JumpFilter.Match] = []
    private var candidates: [JumpFilter.Candidate] = []

    init() {
        let rect = NSRect(x: 0, y: 0, width: 500, height: 400)
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Jump to file"
        isFloatingPanel = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        setupContent()
    }

    override var canBecomeKey: Bool { true }

    private func setupContent() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        contentView = content

        // Search field — top
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Type to filter…"
        searchField.delegate = self
        content.addSubview(searchField)

        // Table — single column, no header
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.width = 480
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 18
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        if #available(macOS 11.0, *) { tableView.style = .plain }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        content.addSubview(scrollView)

        // Bottom bar
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        goToCurrentButton.translatesAutoresizingMaskIntoConstraints = false
        goToCurrentButton.bezelStyle = .rounded
        goToCurrentButton.target = self
        goToCurrentButton.action = #selector(scrollToCurrent)
        content.addSubview(goToCurrentButton)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: goToCurrentButton.centerYAnchor),

            goToCurrentButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            goToCurrentButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    /// Reset state and present centered over `parent`. Call this every time the user opens the dialog.
    func present(over parent: NSWindow?) {
        candidates = jumpDelegate?.jumpCandidates ?? []
        searchField.stringValue = ""
        recompute()
        if let parent {
            let parentFrame = parent.frame
            let x = parentFrame.midX - frame.width / 2
            let y = parentFrame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
        // Pre-select current track if visible
        if let curIdx = jumpDelegate?.currentTrackIndex,
           let row = matches.firstIndex(where: { $0.index == curIdx }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    private func recompute() {
        matches = JumpFilter.filter(query: searchField.stringValue, candidates: candidates)
        tableView.reloadData()
        statusLabel.stringValue = "\(matches.count) of \(candidates.count) tracks"
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        recompute()
        if !matches.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tv: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tv.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let v = NSTableCellView()
            v.identifier = identifier
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = NSFont.systemFont(ofSize: 12)
            v.addSubview(tf)
            v.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            ])
            return v
        }()
        let m = matches[row]
        if let c = candidates.first(where: { $0.index == m.index }) {
            cell.textField?.stringValue = c.displayTitle
        }
        return cell
    }

    // MARK: - Actions

    @objc private func handleDoubleClick() {
        playSelected()
    }

    @objc private func scrollToCurrent() {
        guard let curIdx = jumpDelegate?.currentTrackIndex,
              let row = matches.firstIndex(where: { $0.index == curIdx }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func playSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < matches.count else { return }
        let playlistIndex = matches[row].index
        jumpDelegate?.playTrack(atPlaylistIndex: playlistIndex)
        close()
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Wamp/UI/JumpToFileWindow.swift
git commit -m "feat: add JumpToFileWindow panel scaffolding"
```

---

## Task 3: Keyboard handling — arrows, Enter, Esc

The panel currently relies on the table for arrow keys, but the search field has focus, so arrows insert characters into the field instead of moving the table selection. Intercept arrows in the search field and forward to the table. Wire Enter/Return to play, Esc/Cmd+. to close.

**Files:**
- Modify: `Wamp/UI/JumpToFileWindow.swift`

- [ ] **Step 1: Add the `control(_:textView:doCommandBy:)` delegate method**

Add this method to the `JumpToFileWindow` class (after `controlTextDidChange`):

```swift
func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)):
        moveSelection(by: +1); return true
    case #selector(NSResponder.moveUp(_:)):
        moveSelection(by: -1); return true
    case #selector(NSResponder.moveToBeginningOfDocument(_:)),
         #selector(NSResponder.scrollPageUp(_:)):
        moveSelection(toRow: 0); return true
    case #selector(NSResponder.moveToEndOfDocument(_:)),
         #selector(NSResponder.scrollPageDown(_:)):
        moveSelection(toRow: matches.count - 1); return true
    case #selector(NSResponder.insertNewline(_:)):
        playSelected(); return true
    case #selector(NSResponder.cancelOperation(_:)):
        close(); return true
    case #selector(NSResponder.insertTab(_:)),
         #selector(NSResponder.insertBacktab(_:)):
        // Eat Tab so focus can't escape to the button
        return true
    default:
        return false
    }
}

private func moveSelection(by delta: Int) {
    guard !matches.isEmpty else { return }
    let current = tableView.selectedRow
    let proposed = current < 0 ? (delta > 0 ? 0 : matches.count - 1) : current + delta
    let clamped = max(0, min(matches.count - 1, proposed))
    moveSelection(toRow: clamped)
}

private func moveSelection(toRow row: Int) {
    guard row >= 0, row < matches.count else { return }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
}
```

- [ ] **Step 2: Override `keyDown` for Cmd+. (Esc equivalent)**

Add this override to `JumpToFileWindow`:

```swift
override func keyDown(with event: NSEvent) {
    // Cmd+. is the macOS-native cancel chord.
    if event.modifierFlags.contains(.command),
       event.charactersIgnoringModifiers == "." {
        close()
        return
    }
    super.keyDown(with: event)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Wamp/UI/JumpToFileWindow.swift
git commit -m "feat: keyboard handling for jump-to-file (arrows, Enter, Esc)"
```

---

## Task 4: Wire AppDelegate — menu item, Ctrl+J monitor, delegate conformance

**Files:**
- Modify: `Wamp/AppDelegate.swift`

- [ ] **Step 1: Make AppDelegate conform to `JumpToFileDelegate`**

Add this extension at the bottom of `AppDelegate.swift`:

```swift
// MARK: - JumpToFileDelegate
extension AppDelegate: JumpToFileDelegate {
    var jumpCandidates: [JumpFilter.Candidate] {
        playlistManager.tracks.enumerated().map { idx, track in
            JumpFilter.Candidate(
                index: idx,
                displayTitle: track.displayTitle,
                filename: track.url.lastPathComponent
            )
        }
    }

    var currentTrackIndex: Int? {
        playlistManager.currentIndex >= 0 ? playlistManager.currentIndex : nil
    }

    func playTrack(atPlaylistIndex index: Int) {
        playlistManager.playTrack(at: index)
    }
}
```

- [ ] **Step 2: Add stored property for the panel and the event monitor**

Add these stored properties to the `AppDelegate` class (next to `var hotKeyManager: HotKeyManager!`):

```swift
private var jumpToFileWindow: JumpToFileWindow?
private var jumpToFileMonitor: Any?
```

- [ ] **Step 3: Add `presentJumpToFileWindow()` and Ctrl+J monitor setup**

Add these methods to `AppDelegate`:

```swift
@objc func presentJumpToFileWindow() {
    if jumpToFileWindow == nil {
        let panel = JumpToFileWindow()
        panel.jumpDelegate = self
        jumpToFileWindow = panel
    }
    jumpToFileWindow?.present(over: mainWindow)
}

private func installJumpToFileShortcut() {
    // Ctrl+J — Cmd+J is handled by the menu key equivalent.
    jumpToFileMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCtrlJ = mods == .control && event.charactersIgnoringModifiers?.lowercased() == "j"
        if isCtrlJ {
            self?.presentJumpToFileWindow()
            return nil // swallow
        }
        return event
    }
}
```

- [ ] **Step 4: Call `installJumpToFileShortcut()` and add the menu item**

In `applicationDidFinishLaunching(_:)`, after `hotKeyManager = HotKeyManager(...)`, add:

```swift
installJumpToFileShortcut()
```

In `setupMainMenu()`, inside the Controls menu (after the `shuffle` menu item but before `controlsMenuItem`), add:

```swift
controlsMenu.addItem(.separator())
let jump = NSMenuItem(title: "Jump to File…", action: #selector(presentJumpToFileWindow), keyEquivalent: "j")
jump.target = self
jump.keyEquivalentModifierMask = [.command]
controlsMenu.addItem(jump)
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Wamp/AppDelegate.swift
git commit -m "feat: wire jump-to-file via Cmd+J menu and Ctrl+J monitor"
```

---

## Task 5: Integration test — filter → play

A model-level integration test that proves the wiring from `PlaylistManager.tracks` → `JumpFilter.Candidate` → `JumpFilter.filter` → `PlaylistManager.playTrack(at:)` updates `currentIndex`. This is the closest we get to the "open dialog, type, press Enter, verify playback started" acceptance criterion without dragging UI tests in (per CLAUDE.md, AudioEngine and UI views are out of test scope).

**Files:**
- Create: `WampTests/Integration/JumpToFilePlaybackTests.swift`

- [ ] **Step 1: Write the test**

```swift
import Testing
import Foundation
@testable import Wamp

@MainActor
@Suite("JumpToFile playback integration")
struct JumpToFilePlaybackTests {

    private func track(_ title: String, artist: String = "A") -> Track {
        Track(
            url: URL(fileURLWithPath: "/tmp/\(title).m4a"),
            title: title,
            artist: artist,
            album: "",
            duration: 1
        )
    }

    /// Build the same Candidate list that AppDelegate.jumpCandidates produces.
    private func candidates(from pm: PlaylistManager) -> [JumpFilter.Candidate] {
        pm.tracks.enumerated().map { idx, t in
            JumpFilter.Candidate(
                index: idx,
                displayTitle: t.displayTitle,
                filename: t.url.lastPathComponent
            )
        }
    }

    @Test func filterAndPlay_setsCurrentIndexToMatchedTrack() {
        let pm = PlaylistManager()
        pm.addTracks([
            track("Money", artist: "Pink Floyd"),
            track("Bohemian Rhapsody", artist: "Queen"),
            track("Around the World", artist: "Daft Punk"),
        ])
        let cs = candidates(from: pm)
        let matches = JumpFilter.filter(query: "queen", candidates: cs)
        #expect(matches.count == 1)
        #expect(matches[0].index == 1)
        // Simulate the dialog calling playTrack(at:) with the top match
        pm.playTrack(at: matches[0].index)
        #expect(pm.currentIndex == 1)
        #expect(pm.currentTrack?.title == "Bohemian Rhapsody")
    }

    @Test func filterEmpty_returnsAllTracks() {
        let pm = PlaylistManager()
        pm.addTracks([track("a"), track("b"), track("c")])
        let cs = candidates(from: pm)
        let matches = JumpFilter.filter(query: "", candidates: cs)
        #expect(matches.count == 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: both new tests pass alongside existing suite.

- [ ] **Step 3: Commit**

```bash
git add WampTests/Integration/JumpToFilePlaybackTests.swift
git commit -m "test: integration coverage for jump-to-file → playback wiring"
```

---

## Task 6: Manual verification

This task has no commit — it's the "did you actually run the app?" gate before declaring done. Per CLAUDE.md, UI views are deliberately untested; manual verification stands in.

- [ ] **Step 1: Build & run from CLI**

```bash
xcodebuild -project Wamp.xcodeproj -scheme Wamp -configuration Debug build 2>&1 | tail -5
open Wamp.xcodeproj
```
Then Run from Xcode (Cmd+R). Add a folder of audio (File → Open Folder…) so the playlist has tracks.

- [ ] **Step 2: Verify each acceptance criterion manually**

- [ ] Cmd+J opens the dialog from the main window
- [ ] Ctrl+J opens the dialog from the main window
- [ ] Search field is focused on open (cursor blinks there)
- [ ] Typing filters the list on every keystroke (no perceptible lag)
- [ ] Status label shows "N of M tracks" and updates as you type
- [ ] Down/Up arrows move table selection while focus stays in the search field
- [ ] Enter plays the selected track and closes the dialog
- [ ] Esc closes the dialog without changing playback
- [ ] Cmd+. closes the dialog
- [ ] Tab does nothing (focus stays on search field)
- [ ] "Go to current" scrolls to and selects the playing track without changing the query
- [ ] Switching to another app (Finder) closes the dialog (`hidesOnDeactivate`)
- [ ] Re-opening the dialog after closing it shows an empty query and the current track pre-selected

If any criterion fails, fix it and amend the relevant earlier task's commit (or add a fix commit).

---

## Task 7: CHANGELOG

**Files:**
- Create: `CHANGELOG.md`

`CHANGELOG.md` does not currently exist at the repo root. Create it with the standard Keep-a-Changelog format and the first entry.

- [ ] **Step 1: Write the changelog**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG with jump-to-file entry"
```

---

## Self-Review Checklist (run after writing this plan)

- [x] **Spec coverage:**
  - Cmd+J + Ctrl+J shortcut → Task 4
  - NSPanel with specified styleMask → Task 2
  - Vertical layout (search/table/status+button) → Task 2
  - Substring matching, case-insensitive, artist-title primary, filename fallback → Task 1
  - Ranking prefix > word-boundary > substring, ties preserve playlist order → Task 1
  - Empty query shows full list with current highlighted → Task 2 (`present`) + Task 3
  - ↑/↓ moves selection, Enter plays, Esc closes, Cmd+. closes, Tab eaten → Task 3
  - "Go to current" → Task 2
  - Reset state on every open → Task 2 (`present` clears query)
  - Performance <16ms on 10k tracks → Task 1 (perf test included)
  - Unit tests for matcher → Task 1
  - One integration test (filter → play) → Task 5 (model-level; UI integration is out of test scope per CLAUDE.md, replaced by Task 6 manual verification)
  - CHANGELOG.md → Task 7
  - Auto-close on app deactivation → Task 2 (`hidesOnDeactivate = true`)

- [x] **Placeholder scan:** none. Every code step has the full code; every command has the full command and expected output.

- [x] **Type consistency:** `JumpFilter.Candidate` (index/displayTitle/filename), `JumpFilter.Match` (index/tier), `JumpToFileDelegate.playTrack(atPlaylistIndex:)`, `JumpToFileWindow.present(over:)` all referenced consistently across Tasks 1, 2, 3, 4, 5.

- [x] **Note re acceptance criterion "integration test that opens the dialog, types, presses Enter, and verifies playback started":** the spec calls for a UI-level test; CLAUDE.md scopes tests to Models/ and persistence only. Resolution: Task 5 covers the model wiring (filter → playTrack), Task 6 manual verification covers the UI flow. If the user wants a true UI test later, it's a separate task that would need to set up `XCTest`-based UI test target.
