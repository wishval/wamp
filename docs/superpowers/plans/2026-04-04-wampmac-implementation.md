# WampMac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS audio player that faithfully recreates the Winamp 2.x experience using Swift + AppKit + AVAudioEngine.

**Architecture:** Single borderless NSWindow with vertical NSStackView hosting three togglable sections (MainPlayer, Equalizer, Playlist). Combine-based reactive state. All UI custom-drawn via NSView subclasses.

**Tech Stack:** Swift, AppKit, AVAudioEngine, AVAudioPlayerNode, AVAudioUnitEQ, Combine, Accelerate (vDSP for FFT), MediaPlayer (MPRemoteCommandCenter, MPNowPlayingInfoCenter)

**Design Spec:** `docs/superpowers/specs/2026-04-04-wampmac-design.md`

**Important Xcode Notes:**
- The project uses `PBXFileSystemSynchronizedRootGroup` — files placed in `WinampMac/` are auto-discovered. No need to edit `project.pbxproj` for source files.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set — all types are `@MainActor` by default. Use `nonisolated` where needed (e.g., Codable conformances, audio callbacks).
- Deployment target is macOS 26.3, Swift 5.0.

---

### Task 1: Project Setup

**Files:**
- Delete: `WinampMac/Base.lproj/MainMenu.xib`
- Modify: `WinampMac.xcodeproj/project.pbxproj` (build settings)
- Create: `WinampMac/WinampMac.entitlements`
- Create: `WinampMac/Info.plist`
- Modify: `WinampMac/AppDelegate.swift`

- [ ] **Step 1: Delete MainMenu.xib**

```bash
rm WinampMac/Base.lproj/MainMenu.xib
rmdir WinampMac/Base.lproj
```

- [ ] **Step 2: Update build settings in project.pbxproj**

In both Debug and Release target-level build configurations (the ones with `ASSETCATALOG_COMPILER_APPICON_NAME`), make these changes:

1. Remove: `INFOPLIST_KEY_NSMainNibFile = MainMenu;`
2. Change: `ENABLE_APP_SANDBOX = YES;` → `ENABLE_APP_SANDBOX = NO;`
3. Remove: `ENABLE_USER_SELECTED_FILES = readonly;`
4. Add: `INFOPLIST_FILE = WinampMac/Info.plist;`
5. Change: `GENERATE_INFOPLIST_FILE = YES;` → `GENERATE_INFOPLIST_FILE = NO;`

- [ ] **Step 3: Create entitlements file**

Create `WinampMac/WinampMac.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 4: Create Info.plist**

Create `WinampMac/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string></string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Audio File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.mp3</string>
                <string>public.mpeg-4-audio</string>
                <string>com.apple.m4a-audio</string>
                <string>org.xiph.flac</string>
                <string>com.microsoft.waveform-audio</string>
                <string>public.aiff-audio</string>
                <string>public.audio</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: Replace AppDelegate.swift with minimal programmatic entry**

Replace `WinampMac/AppDelegate.swift` with:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "chore: remove XIB, configure programmatic entry and sandbox disabled"
```

---

### Task 2: WinampTheme

**Files:**
- Create: `WinampMac/UI/WinampTheme.swift`

- [ ] **Step 1: Create the theme file with all design tokens**

Create `WinampMac/UI/WinampTheme.swift`:

```swift
import Cocoa

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

enum WinampTheme {
    // MARK: - Frame
    static let frameBackground = NSColor(hex: 0x3C4250)
    static let frameBorderLight = NSColor(hex: 0x5A6070)
    static let frameBorderDark = NSColor(hex: 0x20242C)

    // MARK: - Title Bar
    static let titleBarTop = NSColor(hex: 0x4A5268)
    static let titleBarBottom = NSColor(hex: 0x222840)
    static let titleBarStripe1 = NSColor(hex: 0xB8860B)
    static let titleBarStripe2 = NSColor(hex: 0xDAA520)
    static let titleBarText = NSColor(hex: 0xC0C8E0)

    // MARK: - LCD / Display
    static let lcdBackground = NSColor.black
    static let greenBright = NSColor(hex: 0x00E000)
    static let greenSecondary = NSColor(hex: 0x00A800)
    static let greenDim = NSColor(hex: 0x1A3A1A)
    static let greenDimText = NSColor(hex: 0x1A5A1A)

    // MARK: - Playlist
    static let white = NSColor.white
    static let selectionBlue = NSColor(hex: 0x0000C0)

    // MARK: - Buttons
    static let buttonFaceTop = NSColor(hex: 0x4A4E58)
    static let buttonFaceBottom = NSColor(hex: 0x3A3E48)
    static let buttonBorderLight = NSColor(hex: 0x5A5E68)
    static let buttonBorderDark = NSColor(hex: 0x2A2E38)
    static let buttonTextActive = NSColor(hex: 0x00E000)
    static let buttonTextInactive = NSColor(hex: 0x4A5A6A)
    static let buttonIconDefault = NSColor(hex: 0x8A9AAA)

    // MARK: - Seek / Balance Sliders
    static let seekFillTop = NSColor(hex: 0x6A8A40)
    static let seekFillBottom = NSColor(hex: 0x4A6A28)
    static let seekThumbTop = NSColor(hex: 0x9AA060)
    static let seekThumbMid = NSColor(hex: 0x6A7A40)
    static let seekThumbBottom = NSColor(hex: 0x4A5A28)
    static let seekThumbBorderLight = NSColor(hex: 0xB0BA70)
    static let seekThumbBorderDark = NSColor(hex: 0x3A4A20)

    // MARK: - Volume Slider
    static let volumeBgStart = NSColor(hex: 0x1A1200)
    static let volumeBgEnd = NSColor(hex: 0xAA7000)
    static let volumeFillStart = NSColor(hex: 0x8A6A20)
    static let volumeFillEnd = NSColor(hex: 0xFFAA00)
    static let volumeThumbTop = NSColor(hex: 0xDAA520)
    static let volumeThumbMid = NSColor(hex: 0xAA7A10)
    static let volumeThumbBottom = NSColor(hex: 0x8A6000)
    static let volumeThumbBorderLight = NSColor(hex: 0xEEBB40)
    static let volumeThumbBorderDark = NSColor(hex: 0x6A5000)

    // MARK: - EQ Sliders
    static let eqSliderBgTop = NSColor(hex: 0x2A2810)
    static let eqSliderBgBottom = NSColor(hex: 0x332E14)
    static let eqSliderTick = NSColor(hex: 0x3A3518)
    static let eqSliderCenter = NSColor(hex: 0x4A4520)
    static let eqThumbTop = NSColor(hex: 0xB0BA60)
    static let eqThumbMid = NSColor(hex: 0x8A9A40)
    static let eqThumbBottom = NSColor(hex: 0x6A7A28)
    static let eqThumbBorderLight = NSColor(hex: 0xD0DA80)
    static let eqThumbBorderDark = NSColor(hex: 0x4A5A18)
    static let eqFillStart = NSColor(hex: 0x2A6A10)
    static let eqFillEnd = NSColor(hex: 0x4A8A20)
    static let eqBandLabelColor = NSColor(hex: 0x6A8A6A)
    static let eqDbLabelColor = NSColor(hex: 0x6A7A6A)

    // MARK: - Spectrum
    static let spectrumBarBottom = NSColor(hex: 0x00C000)
    static let spectrumBarTop = NSColor(hex: 0xE0E000)

    // MARK: - Inset border (LCD panels)
    static let insetBorderDark = NSColor(hex: 0x1A1E28)
    static let insetBorderLight = NSColor(hex: 0x4A4E58)

    // MARK: - Fonts
    static let titleBarFont = NSFont(name: "Tahoma-Bold", size: 8) ?? NSFont.boldSystemFont(ofSize: 8)
    static let trackTitleFont = NSFont(name: "Tahoma", size: 9) ?? NSFont.systemFont(ofSize: 9)
    static let bitrateFont = NSFont(name: "Tahoma", size: 7) ?? NSFont.systemFont(ofSize: 7)
    static let smallLabelFont = NSFont(name: "Tahoma", size: 6) ?? NSFont.systemFont(ofSize: 6)
    static let buttonFont = NSFont(name: "Tahoma-Bold", size: 7) ?? NSFont.boldSystemFont(ofSize: 7)
    static let playlistFont = NSFont(name: "ArialMT", size: 8.5) ?? NSFont.systemFont(ofSize: 8.5)
    static let eqLabelFont = NSFont(name: "Tahoma", size: 6) ?? NSFont.systemFont(ofSize: 6)

    // MARK: - Dimensions
    static let windowWidth: CGFloat = 275
    static let mainPlayerHeight: CGFloat = 148
    static let equalizerHeight: CGFloat = 130
    static let playlistMinHeight: CGFloat = 232
    static let titleBarHeight: CGFloat = 16
    static let transportButtonSize = NSSize(width: 22, height: 18)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add WinampTheme with all design tokens"
```

---

### Task 3: Track Model

**Files:**
- Create: `WinampMac/Models/Track.swift`
- Create: `WinampMacTests/TrackTests.swift`

- [ ] **Step 1: Write tests for Track model**

Create `WinampMacTests/TrackTests.swift`:

```swift
import XCTest
@testable import WinampMac

final class TrackTests: XCTestCase {

    func testTrackFromURLFallbackToFilename() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-test-file.mp3")
        let track = await Track.fromURL(url)
        XCTAssertEqual(track.url, url)
        XCTAssertEqual(track.title, "nonexistent-test-file")
        XCTAssertEqual(track.artist, "Unknown Artist")
        XCTAssertEqual(track.duration, 0)
    }

    func testTrackDisplayTitle() {
        let track = Track(
            url: URL(fileURLWithPath: "/test.mp3"),
            title: "Echo",
            artist: "Crusher-P",
            album: "Album",
            duration: 230.0
        )
        XCTAssertEqual(track.displayTitle, "Crusher-P - Echo")
    }

    func testTrackDisplayTitleUnknownArtist() {
        let track = Track(
            url: URL(fileURLWithPath: "/test.mp3"),
            title: "Echo",
            artist: "Unknown Artist",
            album: "",
            duration: 230.0
        )
        XCTAssertEqual(track.displayTitle, "Echo")
    }

    func testTrackFormattedDuration() {
        let track = Track(
            url: URL(fileURLWithPath: "/test.mp3"),
            title: "Test",
            artist: "Artist",
            album: "",
            duration: 230.5
        )
        XCTAssertEqual(track.formattedDuration, "3:50")
    }

    func testTrackFormattedDurationZero() {
        let track = Track(
            url: URL(fileURLWithPath: "/test.mp3"),
            title: "Test",
            artist: "",
            album: "",
            duration: 0
        )
        XCTAssertEqual(track.formattedDuration, "0:00")
    }

    func testTrackCodable() throws {
        let track = Track(
            url: URL(fileURLWithPath: "/music/test.mp3"),
            title: "Echo",
            artist: "Crusher-P",
            album: "Album",
            duration: 230.0
        )
        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(decoded.url, track.url)
        XCTAssertEqual(decoded.title, track.title)
        XCTAssertEqual(decoded.artist, track.artist)
        XCTAssertEqual(decoded.duration, track.duration)
    }

    func testSupportedExtensions() {
        XCTAssertTrue(Track.supportedExtensions.contains("mp3"))
        XCTAssertTrue(Track.supportedExtensions.contains("flac"))
        XCTAssertTrue(Track.supportedExtensions.contains("wav"))
        XCTAssertTrue(Track.supportedExtensions.contains("aiff"))
        XCTAssertTrue(Track.supportedExtensions.contains("m4a"))
        XCTAssertTrue(Track.supportedExtensions.contains("aac"))
        XCTAssertFalse(Track.supportedExtensions.contains("txt"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug 2>&1 | grep -E "(Test Suite|Failing|error:)" | head -10`
Expected: Compilation errors — `Track` not defined.

- [ ] **Step 3: Implement Track model**

Create `WinampMac/Models/Track.swift`:

```swift
import Foundation
import AVFoundation

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

    init(
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        genre: String = "",
        bitrate: Int = 0,
        sampleRate: Int = 0,
        channels: Int = 2
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
    }

    var displayTitle: String {
        if artist.isEmpty || artist == "Unknown Artist" {
            return title
        }
        return "\(artist) - \(title)"
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var isStereo: Bool { channels >= 2 }

    @MainActor
    static func fromURL(_ url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = ""
        var genre = ""
        var duration: TimeInterval = 0
        var bitrate = 0
        var sampleRate = 0
        var channels = 2

        do {
            let metadata = try await asset.load(.commonMetadata)
            let dur = try await asset.load(.duration)
            duration = dur.seconds.isFinite ? dur.seconds : 0

            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        title = val
                    }
                case .commonKeyArtist:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        artist = val
                    }
                case .commonKeyAlbumName:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        album = val
                    }
                case .commonKeyType:
                    if let val = try await item.load(.stringValue), !val.isEmpty {
                        genre = val
                    }
                default:
                    break
                }
            }

            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let descriptions = try await audioTrack.load(.formatDescriptions)
                if let desc = descriptions.first {
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
                    if let asbd = asbd {
                        sampleRate = Int(asbd.mSampleRate)
                        channels = Int(asbd.mChannelsPerFrame)
                    }
                }
                let estimatedRate = try await audioTrack.load(.estimatedDataRate)
                bitrate = Int(estimatedRate / 1000)
            }
        } catch {
            // Fallback: use filename as title
        }

        return Track(
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            genre: genre,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels
        )
    }
}
```

- [ ] **Step 4: Ensure tests target exists and add test source**

The Xcode project may not have a test target. If `xcodebuild test` fails because there's no test target, create tests later via Xcode UI. For now, verify the main target builds:

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add Track model with metadata loading and Codable"
```

---

### Task 4: AudioEngine — Core Playback

**Files:**
- Create: `WinampMac/Audio/AudioEngine.swift`

- [ ] **Step 1: Create AudioEngine with playback core**

Create `WinampMac/Audio/AudioEngine.swift`:

```swift
import Foundation
import AVFoundation
import Combine
import Accelerate

enum RepeatMode: Int, Codable {
    case off = 0
    case track = 1
    case playlist = 2
}

extension Notification.Name {
    static let trackDidFinish = Notification.Name("trackDidFinish")
}

class AudioEngine: ObservableObject {
    // MARK: - Published State
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.75 {
        didSet { engine.mainMixerNode.outputVolume = effectiveVolume }
    }
    @Published var balance: Float = 0 {
        didSet { playerNode.pan = balance }
    }
    @Published var isMuted = false {
        didSet { engine.mainMixerNode.outputVolume = effectiveVolume }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var eqEnabled = true {
        didSet { eq.bypass = !eqEnabled }
    }
    @Published var preampGain: Float = 0 // dB, -12 to +12
    @Published var spectrumData: [Float] = Array(repeating: 0, count: 32)

    // MARK: - EQ State
    @Published private(set) var eqBands: [Float] = Array(repeating: 0, count: 10) // dB per band

    static let eqFrequencies: [Float] = [
        70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000
    ]

    // MARK: - Private
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq: AVAudioUnitEQ
    private var audioFile: AVAudioFile?
    private var seekFrame: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 44100
    private var audioLengthFrames: AVAudioFramePosition = 0
    private var timeUpdateTimer: Timer?
    private var needsScheduling = true

    private var effectiveVolume: Float {
        isMuted ? 0 : volume
    }

    // MARK: - Init
    init() {
        eq = AVAudioUnitEQ(numberOfBands: 10)
        setupAudioChain()
        setupEQBands()
    }

    private func setupAudioChain() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.connect(playerNode, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = effectiveVolume
    }

    private func setupEQBands() {
        for (i, freq) in Self.eqFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    // MARK: - Playback Controls
    func loadAndPlay(url: URL) {
        stop()

        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else { return }

            audioSampleRate = file.processingFormat.sampleRate
            audioLengthFrames = file.length
            duration = Double(audioLengthFrames) / audioSampleRate
            seekFrame = 0
            needsScheduling = true

            if !engine.isRunning {
                try engine.start()
            }
            installSpectrumTap()
            scheduleAndPlay()
        } catch {
            print("AudioEngine: failed to load \(url.lastPathComponent): \(error)")
        }
    }

    func play() {
        guard audioFile != nil else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            if needsScheduling {
                scheduleAndPlay()
            } else {
                playerNode.play()
            }
            isPlaying = true
            startTimeUpdates()
        } catch {
            print("AudioEngine: failed to start: \(error)")
        }
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimeUpdates()
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        seekFrame = 0
        needsScheduling = true
        stopTimeUpdates()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        let targetFrame = AVAudioFramePosition(time * audioSampleRate)
        seekFrame = max(0, min(targetFrame, audioLengthFrames))
        needsScheduling = true

        if isPlaying {
            playerNode.stop()
            scheduleAndPlay()
        } else {
            currentTime = time
        }
    }

    // MARK: - EQ
    func setEQ(band: Int, gain: Float) {
        guard band >= 0, band < 10 else { return }
        let clampedGain = max(-12, min(12, gain))
        eqBands[band] = clampedGain
        eq.bands[band].gain = clampedGain
    }

    func setPreamp(gain: Float) {
        preampGain = max(-12, min(12, gain))
        // Preamp as volume multiplier: convert dB to linear
        let linear = pow(10, preampGain / 20)
        engine.mainMixerNode.outputVolume = effectiveVolume * linear
    }

    func setAllEQBands(_ gains: [Float]) {
        for (i, gain) in gains.prefix(10).enumerated() {
            setEQ(band: i, gain: gain)
        }
    }

    func resetEQ() {
        setAllEQBands(Array(repeating: 0, count: 10))
        setPreamp(gain: 0)
    }

    // MARK: - Private Playback
    private func scheduleAndPlay() {
        guard let file = audioFile else { return }

        let framesToPlay = audioLengthFrames - seekFrame
        guard framesToPlay > 0 else {
            handleTrackCompletion()
            return
        }

        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: seekFrame,
            frameCount: AVAudioFrameCount(framesToPlay),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handleTrackCompletion()
            }
        }
        playerNode.play()
        isPlaying = true
        needsScheduling = false
        startTimeUpdates()
    }

    private func handleTrackCompletion() {
        guard isPlaying else { return }

        if repeatMode == .track {
            seekFrame = 0
            needsScheduling = true
            scheduleAndPlay()
        } else {
            isPlaying = false
            stopTimeUpdates()
            NotificationCenter.default.post(name: .trackDidFinish, object: nil)
        }
    }

    // MARK: - Time Updates
    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        currentTime = Double(seekFrame + playerTime.sampleTime) / audioSampleRate
    }

    // MARK: - Spectrum Tap
    private func installSpectrumTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processSpectrumData(buffer: buffer)
        }
    }

    private func processSpectrumData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Use power-of-2 size for FFT
        let log2n = vDSP_Length(log2(Float(frameCount)))
        let fftSize = Int(1 << log2n)
        let halfSize = fftSize / 2

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Split complex for FFT
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBytes { rawBuf in
                    let complexPtr = rawBuf.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitudes
                var magnitudes = [Float](repeating: 0, count: halfSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

                // Scale and map to 32 bins
                let binCount = 32
                var spectrum = [Float](repeating: 0, count: binCount)
                let binsPerOutput = max(1, halfSize / binCount)

                for i in 0..<binCount {
                    let start = i * binsPerOutput
                    let end = min(start + binsPerOutput, halfSize)
                    var sum: Float = 0
                    vDSP_sve(Array(magnitudes[start..<end]), 1, &sum, vDSP_Length(end - start))
                    spectrum[i] = sqrt(sum / Float(end - start)) * 0.05
                }

                DispatchQueue.main.async { [weak self] in
                    self?.spectrumData = spectrum
                }
            }
        }
    }

    deinit {
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add AudioEngine with playback, seek, EQ, and spectrum tap"
```

---

### Task 5: PlaylistManager

**Files:**
- Create: `WinampMac/Models/PlaylistManager.swift`

- [ ] **Step 1: Implement PlaylistManager**

Create `WinampMac/Models/PlaylistManager.swift`:

```swift
import Foundation
import Combine

class PlaylistManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = -1
    @Published var isShuffled = false
    @Published var searchQuery = ""

    private var shuffleOrder: [Int] = []
    private var shufflePosition = 0
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    var currentTrack: Track? {
        guard currentIndex >= 0, currentIndex < tracks.count else { return nil }
        return tracks[currentIndex]
    }

    var filteredTracks: [Track] {
        guard !searchQuery.isEmpty else { return tracks }
        let query = searchQuery.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query)
        }
    }

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalDuration: String {
        let total = Int(totalDuration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    init() {
        NotificationCenter.default.publisher(for: .trackDidFinish)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.advanceToNext() }
            .store(in: &cancellables)
    }

    func setAudioEngine(_ engine: AudioEngine) {
        self.audioEngine = engine
    }

    // MARK: - Track Management
    func addTracks(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
        if isShuffled { regenerateShuffleOrder() }
    }

    func addURLs(_ urls: [URL]) async {
        var newTracks: [Track] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if Track.supportedExtensions.contains(ext) {
                let track = await Track.fromURL(url)
                newTracks.append(track)
            }
        }
        addTracks(newTracks)
    }

    func addFolder(_ folderURL: URL) async {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if Track.supportedExtensions.contains(ext) {
                urls.append(fileURL)
            }
        }
        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        await addURLs(urls)
    }

    func removeTrack(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, tracks.count - 1)
        }
        if isShuffled { regenerateShuffleOrder() }
    }

    func clearPlaylist() {
        tracks.removeAll()
        currentIndex = -1
        shuffleOrder.removeAll()
        shufflePosition = 0
    }

    // MARK: - Playback Navigation
    func playTrack(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        currentIndex = index
        audioEngine?.loadAndPlay(url: tracks[index].url)
    }

    func playNext() {
        guard !tracks.isEmpty else { return }

        if isShuffled {
            shufflePosition += 1
            if shufflePosition >= shuffleOrder.count {
                if audioEngine?.repeatMode == .playlist {
                    regenerateShuffleOrder()
                    shufflePosition = 0
                } else {
                    audioEngine?.stop()
                    return
                }
            }
            playTrack(at: shuffleOrder[shufflePosition])
        } else {
            let nextIndex = currentIndex + 1
            if nextIndex >= tracks.count {
                if audioEngine?.repeatMode == .playlist {
                    playTrack(at: 0)
                } else {
                    audioEngine?.stop()
                }
            } else {
                playTrack(at: nextIndex)
            }
        }
    }

    func playPrevious() {
        guard !tracks.isEmpty else { return }

        if let engine = audioEngine, engine.currentTime > 3.0 {
            engine.seek(to: 0)
            return
        }

        if isShuffled {
            shufflePosition = max(0, shufflePosition - 1)
            playTrack(at: shuffleOrder[shufflePosition])
        } else {
            let prevIndex = currentIndex - 1
            if prevIndex < 0 {
                playTrack(at: tracks.count - 1)
            } else {
                playTrack(at: prevIndex)
            }
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            regenerateShuffleOrder()
        }
    }

    // MARK: - Saved Playlists
    func savePlaylist(name: String, to directory: URL) {
        let fileURL = directory.appendingPathComponent("\(name).json")
        let urls = tracks.map { $0.url.path }
        if let data = try? JSONEncoder().encode(urls) {
            try? data.write(to: fileURL)
        }
    }

    func loadPlaylist(from fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        clearPlaylist()
        let urls = paths.map { URL(fileURLWithPath: $0) }
        await addURLs(urls)
    }

    // MARK: - Private
    private func advanceToNext() {
        guard audioEngine?.repeatMode != .track else { return }
        playNext()
    }

    private func regenerateShuffleOrder() {
        shuffleOrder = Array(tracks.indices).shuffled()
        shufflePosition = 0
        // Place current track first if playing
        if currentIndex >= 0, let idx = shuffleOrder.firstIndex(of: currentIndex) {
            shuffleOrder.swapAt(0, idx)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add PlaylistManager with shuffle, search, and auto-advance"
```

---

### Task 6: StateManager

**Files:**
- Create: `WinampMac/Models/StateManager.swift`

- [ ] **Step 1: Implement StateManager**

Create `WinampMac/Models/StateManager.swift`:

```swift
import Foundation
import Combine

struct AppState: Codable {
    var volume: Float = 0.75
    var balance: Float = 0
    var repeatMode: Int = 0 // RepeatMode raw value
    var isShuffled: Bool = false
    var eqEnabled: Bool = true
    var showEqualizer: Bool = true
    var showPlaylist: Bool = true
    var windowX: Double = 100
    var windowY: Double = 100
    var lastTrackIndex: Int = -1
    var lastPlaybackPosition: Double = 0
}

struct EQState: Codable {
    var bands: [Float] = Array(repeating: 0, count: 10)
    var preampGain: Float = 0
    var presetName: String = "Flat"
    var autoMode: Bool = false
}

class StateManager {
    private let appSupportDir: URL
    private var cancellables = Set<AnyCancellable>()
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = appSupport.appendingPathComponent("WinampMac")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    var playlistsDirectory: URL {
        let dir = appSupportDir.appendingPathComponent("playlists")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Subscribe to Changes
    func observe(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        audioEngine.$volume
            .merge(with: audioEngine.$balance.map { _ in audioEngine.volume })
            .merge(with: audioEngine.$repeatMode.map { _ in audioEngine.volume })
            .merge(with: audioEngine.$eqEnabled.map { _ in audioEngine.volume })
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveState(audioEngine: audioEngine, playlistManager: playlistManager) }
            .store(in: &cancellables)

        playlistManager.$tracks
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.savePlaylist(playlistManager: playlistManager) }
            .store(in: &cancellables)

        playlistManager.$isShuffled
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveState(audioEngine: audioEngine, playlistManager: playlistManager) }
            .store(in: &cancellables)
    }

    // MARK: - Save
    func saveState(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        var state = AppState()
        state.volume = audioEngine.volume
        state.balance = audioEngine.balance
        state.repeatMode = audioEngine.repeatMode.rawValue
        state.isShuffled = playlistManager.isShuffled
        state.eqEnabled = audioEngine.eqEnabled
        state.lastTrackIndex = playlistManager.currentIndex
        state.lastPlaybackPosition = audioEngine.currentTime
        write(state, to: "state.json")
    }

    func saveEQState(audioEngine: AudioEngine, presetName: String = "Custom", autoMode: Bool = false) {
        let eqState = EQState(
            bands: audioEngine.eqBands,
            preampGain: audioEngine.preampGain,
            presetName: presetName,
            autoMode: autoMode
        )
        write(eqState, to: "equalizer.json")
    }

    func savePlaylist(playlistManager: PlaylistManager) {
        let trackData = playlistManager.tracks.map { $0 }
        write(trackData, to: "playlist.json")
    }

    func saveWindowState(x: Double, y: Double, showEQ: Bool, showPlaylist: Bool, audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        var state = loadAppState()
        state.windowX = x
        state.windowY = y
        state.showEqualizer = showEQ
        state.showPlaylist = showPlaylist
        state.volume = audioEngine.volume
        state.balance = audioEngine.balance
        state.repeatMode = audioEngine.repeatMode.rawValue
        state.isShuffled = playlistManager.isShuffled
        state.eqEnabled = audioEngine.eqEnabled
        state.lastTrackIndex = playlistManager.currentIndex
        state.lastPlaybackPosition = audioEngine.currentTime
        write(state, to: "state.json")
    }

    // MARK: - Load
    func loadAppState() -> AppState {
        read("state.json") ?? AppState()
    }

    func loadEQState() -> EQState {
        read("equalizer.json") ?? EQState()
    }

    func loadSavedPlaylist() -> [Track] {
        read("playlist.json") ?? []
    }

    // MARK: - Private I/O
    private func write<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportDir.appendingPathComponent(filename)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("StateManager: failed to write \(filename): \(error)")
        }
    }

    private func read<T: Decodable>(_ filename: String) -> T? {
        let url = appSupportDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add StateManager with JSON persistence and debounced auto-save"
```

---

### Task 7: Custom UI Components — WinampSlider and WinampButton

**Files:**
- Create: `WinampMac/UI/Components/WinampSlider.swift`
- Create: `WinampMac/UI/Components/WinampButton.swift`

- [ ] **Step 1: Create WinampSlider**

Create `WinampMac/UI/Components/WinampSlider.swift`:

```swift
import Cocoa

enum WinampSliderStyle {
    case seek       // olive-green, horizontal
    case volume     // orange gradient, horizontal
    case balance    // olive-green, horizontal
    case eqBand     // vertical, yellow-tinted background
}

class WinampSlider: NSView {
    var value: Float = 0 { didSet { needsDisplay = true; onChange?(value) } }
    var minValue: Float = 0
    var maxValue: Float = 1
    var onChange: ((Float) -> Void)?
    var style: WinampSliderStyle = .seek
    var isVertical: Bool = false

    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(style: WinampSliderStyle, isVertical: Bool = false) {
        self.init(frame: .zero)
        self.style = style
        self.isVertical = isVertical
        if style == .eqBand {
            self.isVertical = true
            self.minValue = -12
            self.maxValue = 12
        }
    }

    private var normalizedValue: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((value - minValue) / (maxValue - minValue))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        if isVertical {
            drawVerticalSlider(in: b)
        } else {
            drawHorizontalSlider(in: b)
        }
    }

    private func drawHorizontalSlider(in rect: NSRect) {
        let trackY = rect.midY - 3
        let trackRect = NSRect(x: 1, y: trackY, width: rect.width - 2, height: 6)

        // Track background
        switch style {
        case .volume:
            let gradient = NSGradient(starting: WinampTheme.volumeBgStart, ending: WinampTheme.volumeBgEnd)
            gradient?.draw(in: trackRect, angle: 0)
        default:
            WinampTheme.lcdBackground.setFill()
            trackRect.fill()
        }

        // Inset border
        drawInsetBorder(trackRect)

        // Fill
        let fillWidth = trackRect.width * normalizedValue
        let fillRect = NSRect(x: trackRect.minX + 1, y: trackY + 1, width: fillWidth, height: 4)
        switch style {
        case .volume:
            let gradient = NSGradient(starting: WinampTheme.volumeFillStart, ending: WinampTheme.volumeFillEnd)
            gradient?.draw(in: fillRect, angle: 0)
        default:
            let gradient = NSGradient(starting: WinampTheme.seekFillTop, ending: WinampTheme.seekFillBottom)
            gradient?.draw(in: fillRect, angle: 90)
        }

        // Thumb
        let thumbW: CGFloat = 14
        let thumbH: CGFloat = rect.height
        let thumbX = trackRect.minX + fillWidth - thumbW / 2
        let thumbRect = NSRect(x: max(0, thumbX), y: 0, width: thumbW, height: thumbH)
        drawThumb(thumbRect, isVolumeStyle: style == .volume)
    }

    private func drawVerticalSlider(in rect: NSRect) {
        let trackX = rect.midX - 5
        let trackRect = NSRect(x: trackX, y: 0, width: 10, height: rect.height)

        // Yellow-tinted EQ background
        let bgGradient = NSGradient(starting: WinampTheme.eqSliderBgTop, ending: WinampTheme.eqSliderBgBottom)
        bgGradient?.draw(in: trackRect, angle: 90)
        drawInsetBorder(trackRect)

        // Center line
        let centerY = rect.midY
        WinampTheme.eqSliderCenter.setStroke()
        let centerLine = NSBezierPath()
        centerLine.move(to: NSPoint(x: trackRect.minX + 2, y: centerY))
        centerLine.line(to: NSPoint(x: trackRect.maxX - 2, y: centerY))
        centerLine.lineWidth = 1
        centerLine.stroke()

        // Tick marks
        WinampTheme.eqSliderTick.setStroke()
        let tickPath = NSBezierPath()
        for i in stride(from: trackRect.minY + 2, to: trackRect.maxY, by: 3) {
            tickPath.move(to: NSPoint(x: rect.midX - 1, y: i))
            tickPath.line(to: NSPoint(x: rect.midX + 1, y: i))
        }
        tickPath.lineWidth = 0.5
        tickPath.stroke()

        // Fill from center
        let thumbY = rect.height * (1 - normalizedValue)
        if value > 0 {
            let fillRect = NSRect(x: trackRect.minX + 3, y: centerY, width: 4, height: thumbY < centerY ? centerY - thumbY : 0)
            let fillGradient = NSGradient(starting: WinampTheme.eqFillStart, ending: WinampTheme.eqFillEnd)
            fillGradient?.draw(in: NSRect(x: trackRect.minX + 3, y: thumbY, width: 4, height: centerY - thumbY), angle: 90)
        } else if value < 0 {
            let fillGradient = NSGradient(starting: WinampTheme.eqFillStart, ending: WinampTheme.eqFillEnd)
            fillGradient?.draw(in: NSRect(x: trackRect.minX + 3, y: centerY, width: 4, height: thumbY - centerY), angle: 270)
        }

        // Thumb
        let eqThumbH: CGFloat = 4
        let eqThumbW: CGFloat = 12
        let eqThumbRect = NSRect(x: rect.midX - eqThumbW / 2, y: thumbY - eqThumbH / 2, width: eqThumbW, height: eqThumbH)
        drawEQThumb(eqThumbRect)
    }

    private func drawThumb(_ rect: NSRect, isVolumeStyle: Bool) {
        if isVolumeStyle {
            let gradient = NSGradient(colors: [WinampTheme.volumeThumbTop, WinampTheme.volumeThumbMid, WinampTheme.volumeThumbBottom])
            gradient?.draw(in: rect, angle: 90)
            WinampTheme.volumeThumbBorderLight.setStroke()
            NSBezierPath(rect: rect).stroke()
        } else {
            let gradient = NSGradient(colors: [WinampTheme.seekThumbTop, WinampTheme.seekThumbMid, WinampTheme.seekThumbBottom])
            gradient?.draw(in: rect, angle: 90)
            WinampTheme.seekThumbBorderLight.setStroke()
            NSBezierPath(rect: rect).stroke()
        }
    }

    private func drawEQThumb(_ rect: NSRect) {
        let gradient = NSGradient(colors: [WinampTheme.eqThumbTop, WinampTheme.eqThumbMid, WinampTheme.eqThumbBottom])
        gradient?.draw(in: rect, angle: 90)
        WinampTheme.eqThumbBorderLight.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawInsetBorder(_ rect: NSRect) {
        let path = NSBezierPath()
        WinampTheme.insetBorderDark.setStroke()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.lineWidth = 1
        path.stroke()

        let path2 = NSBezierPath()
        WinampTheme.insetBorderLight.setStroke()
        path2.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        path2.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path2.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path2.lineWidth = 1
        path2.stroke()
    }

    // MARK: - Mouse Handling
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateValueFromMouse(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValueFromMouse(event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    private func updateValueFromMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let normalized: CGFloat

        if isVertical {
            normalized = 1 - max(0, min(1, point.y / bounds.height))
        } else {
            normalized = max(0, min(1, point.x / bounds.width))
        }

        value = minValue + Float(normalized) * (maxValue - minValue)
    }
}
```

- [ ] **Step 2: Create WinampButton**

Create `WinampMac/UI/Components/WinampButton.swift`:

```swift
import Cocoa

enum WinampButtonStyle {
    case transport
    case toggle
    case action
}

class WinampButton: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    var isPressed = false { didSet { needsDisplay = true } }
    var style: WinampButtonStyle = .transport
    var onClick: (() -> Void)?
    var drawIcon: ((NSRect, Bool) -> Void)? // custom icon drawer (rect, isActive)

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(title: String, style: WinampButtonStyle = .action) {
        self.init(frame: .zero)
        self.title = title
        self.style = style
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        // Button face gradient
        let faceTop = isPressed ? WinampTheme.buttonFaceBottom : WinampTheme.buttonFaceTop
        let faceBot = isPressed ? WinampTheme.buttonFaceTop : WinampTheme.buttonFaceBottom
        let gradient = NSGradient(starting: faceTop, ending: faceBot)
        gradient?.draw(in: b, angle: 90)

        // 3D beveled border
        let borderLight = isPressed ? WinampTheme.buttonBorderDark : WinampTheme.buttonBorderLight
        let borderDark = isPressed ? WinampTheme.buttonBorderLight : WinampTheme.buttonBorderDark

        borderLight.setStroke()
        var path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: 0, y: b.height))
        path.line(to: NSPoint(x: b.width, y: b.height))
        path.lineWidth = 1
        path.stroke()

        borderDark.setStroke()
        path = NSBezierPath()
        path.move(to: NSPoint(x: b.width, y: b.height))
        path.line(to: NSPoint(x: b.width, y: 0))
        path.line(to: NSPoint(x: 0, y: 0))
        path.lineWidth = 1
        path.stroke()

        // Content
        if let drawIcon = drawIcon {
            drawIcon(b.insetBy(dx: 4, dy: 3), isActive)
        } else if !title.isEmpty {
            let color = isActive ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WinampTheme.buttonFont,
                .foregroundColor: color
            ]
            let size = title.size(withAttributes: attrs)
            let point = NSPoint(
                x: (b.width - size.width) / 2,
                y: (b.height - size.height) / 2
            )
            title.draw(at: point, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add WinampSlider and WinampButton custom controls"
```

---

### Task 8: Custom UI Components — SevenSegmentView, LCDDisplay, SpectrumView

**Files:**
- Create: `WinampMac/UI/Components/SevenSegmentView.swift`
- Create: `WinampMac/UI/Components/LCDDisplay.swift`
- Create: `WinampMac/UI/Components/SpectrumView.swift`
- Create: `WinampMac/UI/Components/EQResponseView.swift`

- [ ] **Step 1: Create SevenSegmentView**

Create `WinampMac/UI/Components/SevenSegmentView.swift`:

```swift
import Cocoa

class SevenSegmentView: NSView {
    var timeInSeconds: TimeInterval = 0 { didSet { needsDisplay = true } }

    // Segment layout: 7 segments per digit (a-g), standard arrangement
    // a=top, b=topRight, c=bottomRight, d=bottom, e=bottomLeft, f=topLeft, g=middle
    private let digitSegments: [[Bool]] = [
        [true,  true,  true,  true,  true,  true,  false], // 0
        [false, true,  true,  false, false, false, false], // 1
        [true,  true,  false, true,  true,  false, true],  // 2
        [true,  true,  true,  true,  false, false, true],  // 3
        [false, true,  true,  false, false, true,  true],  // 4
        [true,  false, true,  true,  false, true,  true],  // 5
        [true,  false, true,  true,  true,  true,  true],  // 6
        [true,  true,  true,  false, false, false, false], // 7
        [true,  true,  true,  true,  true,  true,  true],  // 8
        [true,  true,  true,  true,  false, true,  true],  // 9
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalSeconds = Int(max(0, timeInSeconds))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        let digitWidth: CGFloat = 14
        let colonWidth: CGFloat = 6
        let digitHeight = bounds.height

        // Layout: M : S S (or MM : SS if >= 10 min)
        var digits: [Int] = []
        if minutes >= 10 {
            digits.append(minutes / 10)
        }
        digits.append(minutes % 10)

        let totalWidth = CGFloat(digits.count + 2) * digitWidth + colonWidth
        var x = (bounds.width - totalWidth) / 2

        // Minutes digits
        for d in digits {
            drawDigit(d, at: NSRect(x: x, y: 0, width: digitWidth, height: digitHeight))
            x += digitWidth
        }

        // Colon
        drawColon(at: NSRect(x: x, y: 0, width: colonWidth, height: digitHeight))
        x += colonWidth

        // Seconds
        drawDigit(seconds / 10, at: NSRect(x: x, y: 0, width: digitWidth, height: digitHeight))
        x += digitWidth
        drawDigit(seconds % 10, at: NSRect(x: x, y: 0, width: digitWidth, height: digitHeight))
    }

    private func drawDigit(_ digit: Int, at rect: NSRect) {
        guard digit >= 0, digit <= 9 else { return }
        let segs = digitSegments[digit]
        let w = rect.width - 2
        let h = rect.height - 2
        let x = rect.minX + 1
        let y = rect.minY + 1
        let t: CGFloat = 2 // segment thickness
        let mid = y + h / 2

        let segRects: [NSRect] = [
            NSRect(x: x + t, y: y + h - t, width: w - 2 * t, height: t),       // a top
            NSRect(x: x + w - t, y: mid, width: t, height: h / 2 - t),          // b topRight
            NSRect(x: x + w - t, y: y + t, width: t, height: h / 2 - t),        // c bottomRight
            NSRect(x: x + t, y: y, width: w - 2 * t, height: t),                // d bottom
            NSRect(x: x, y: y + t, width: t, height: h / 2 - t),                // e bottomLeft
            NSRect(x: x, y: mid, width: t, height: h / 2 - t),                  // f topLeft
            NSRect(x: x + t, y: mid - t / 2, width: w - 2 * t, height: t),      // g middle
        ]

        for (i, segRect) in segRects.enumerated() {
            let color = segs[i] ? WinampTheme.greenBright : WinampTheme.greenDim
            color.setFill()
            segRect.fill()
        }
    }

    private func drawColon(at rect: NSRect) {
        let dotSize: CGFloat = 2
        let cx = rect.midX - dotSize / 2

        WinampTheme.greenBright.setFill()
        NSRect(x: cx, y: rect.midY + 3, width: dotSize, height: dotSize).fill()
        NSRect(x: cx, y: rect.midY - 3 - dotSize, width: dotSize, height: dotSize).fill()
    }
}
```

- [ ] **Step 2: Create LCDDisplay**

Create `WinampMac/UI/Components/LCDDisplay.swift`:

```swift
import Cocoa

class LCDDisplay: NSView {
    var text: String = "" { didSet { scrollOffset = 0; needsDisplay = true } }
    var isScrolling = true

    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private let scrollSpeed: CGFloat = 0.5

    override init(frame: NSRect) {
        super.init(frame: frame)
        startScrolling()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startScrolling() {
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isScrolling, !self.text.isEmpty else { return }
            self.scrollOffset += self.scrollSpeed
            let textWidth = self.textSize().width + 30
            if self.scrollOffset > textWidth {
                self.scrollOffset = -self.bounds.width
            }
            self.needsDisplay = true
        }
    }

    private func textSize() -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]
        return text.size(withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]

        let size = text.size(withAttributes: attrs)
        let y = (bounds.height - size.height) / 2

        if size.width <= bounds.width || !isScrolling {
            text.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
        } else {
            // Scroll: draw text offset
            let displayText = text + "   ★   " + text
            displayText.draw(at: NSPoint(x: -scrollOffset, y: y), withAttributes: attrs)
        }
    }

    deinit {
        scrollTimer?.invalidate()
    }
}
```

- [ ] **Step 3: Create SpectrumView**

Create `WinampMac/UI/Components/SpectrumView.swift`:

```swift
import Cocoa

class SpectrumView: NSView {
    var spectrumData: [Float] = [] { didSet { needsDisplay = true } }
    var barCount: Int = 26

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barWidth: CGFloat = 3
        let gap: CGFloat = 1
        let totalBars = min(barCount, Int(bounds.width / (barWidth + gap)))

        for i in 0..<totalBars {
            let dataIndex = i < spectrumData.count ? i : 0
            let amplitude = spectrumData.isEmpty ? Float(0) : min(1, spectrumData[dataIndex] * 10)
            let barHeight = CGFloat(amplitude) * bounds.height
            let x = CGFloat(i) * (barWidth + gap)
            let barRect = NSRect(x: x, y: 0, width: barWidth, height: max(1, barHeight))

            let gradient = NSGradient(starting: WinampTheme.spectrumBarBottom, ending: WinampTheme.spectrumBarTop)
            gradient?.draw(in: barRect, angle: 90)
        }
    }
}
```

- [ ] **Step 4: Create EQResponseView**

Create `WinampMac/UI/Components/EQResponseView.swift`:

```swift
import Cocoa

class EQResponseView: NSView {
    var bands: [Float] = Array(repeating: 0, count: 10) { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        // Background
        let bgGradient = NSGradient(starting: WinampTheme.eqSliderBgTop, ending: WinampTheme.eqSliderBgBottom)
        bgGradient?.draw(in: b, angle: 90)

        // Center line
        WinampTheme.eqSliderCenter.setStroke()
        let centerPath = NSBezierPath()
        centerPath.move(to: NSPoint(x: 0, y: b.midY))
        centerPath.line(to: NSPoint(x: b.width, y: b.midY))
        centerPath.lineWidth = 0.5
        centerPath.stroke()

        // Response curve
        guard bands.count >= 10 else { return }
        let path = NSBezierPath()
        WinampTheme.greenBright.setStroke()
        path.lineWidth = 1.2

        for (i, gain) in bands.enumerated() {
            let x = b.width * CGFloat(i) / CGFloat(bands.count - 1)
            let normalized = CGFloat(gain / 12) // -1 to 1
            let y = b.midY - normalized * (b.height / 2 - 2)

            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.stroke()
    }
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: add SevenSegmentView, LCDDisplay, SpectrumView, EQResponseView"
```

---

### Task 9: Custom UI Components — TransportBar and TitleBarView

**Files:**
- Create: `WinampMac/UI/Components/TransportBar.swift`
- Create: `WinampMac/UI/Components/TitleBarView.swift`

- [ ] **Step 1: Create TransportBar**

Create `WinampMac/UI/Components/TransportBar.swift`:

```swift
import Cocoa

class TransportBar: NSView {
    var onPrevious: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onNext: (() -> Void)?
    var onEject: (() -> Void)?

    private(set) var prevButton: WinampButton!
    private(set) var playButton: WinampButton!
    private(set) var pauseButton: WinampButton!
    private(set) var stopButton: WinampButton!
    private(set) var nextButton: WinampButton!
    private(set) var ejectButton: WinampButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        let buttons = makeButtons()
        prevButton = buttons[0]
        playButton = buttons[1]
        pauseButton = buttons[2]
        stopButton = buttons[3]
        nextButton = buttons[4]
        ejectButton = buttons[5]

        prevButton.drawIcon = { rect, _ in self.drawPrevIcon(in: rect) }
        playButton.drawIcon = { rect, active in self.drawPlayIcon(in: rect, active: active) }
        pauseButton.drawIcon = { rect, _ in self.drawPauseIcon(in: rect) }
        stopButton.drawIcon = { rect, _ in self.drawStopIcon(in: rect) }
        nextButton.drawIcon = { rect, _ in self.drawNextIcon(in: rect) }
        ejectButton.drawIcon = { rect, _ in self.drawEjectIcon(in: rect) }

        prevButton.onClick = { [weak self] in self?.onPrevious?() }
        playButton.onClick = { [weak self] in self?.onPlay?() }
        pauseButton.onClick = { [weak self] in self?.onPause?() }
        stopButton.onClick = { [weak self] in self?.onStop?() }
        nextButton.onClick = { [weak self] in self?.onNext?() }
        ejectButton.onClick = { [weak self] in self?.onEject?() }

        for btn in buttons {
            btn.style = .transport
            addSubview(btn)
        }
    }

    private func makeButtons() -> [WinampButton] {
        (0..<6).map { _ in WinampButton(title: "", style: .transport) }
    }

    override func layout() {
        super.layout()
        let btnW: CGFloat = 22
        let btnH: CGFloat = 18
        let gap: CGFloat = 1
        let buttons = [prevButton!, playButton!, pauseButton!, stopButton!, nextButton!, ejectButton!]
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: CGFloat(i) * (btnW + gap), y: 0, width: btnW, height: btnH)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 6 * 22 + 5, height: 18)
    }

    // MARK: - Icon Drawing
    private func drawPrevIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        let cx = rect.midX
        let cy = rect.midY
        NSRect(x: cx - 5, y: cy - 4, width: 2, height: 8).fill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx + 3, y: cy - 4))
        tri.line(to: NSPoint(x: cx - 2, y: cy))
        tri.line(to: NSPoint(x: cx + 3, y: cy + 4))
        tri.close()
        tri.fill()
    }

    private func drawPlayIcon(in rect: NSRect, active: Bool) {
        let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonIconDefault
        color.setFill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: rect.midX - 3, y: rect.midY - 4))
        tri.line(to: NSPoint(x: rect.midX + 4, y: rect.midY))
        tri.line(to: NSPoint(x: rect.midX - 3, y: rect.midY + 4))
        tri.close()
        tri.fill()
    }

    private func drawPauseIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 3, height: 8).fill()
        NSRect(x: rect.midX + 1, y: rect.midY - 4, width: 3, height: 8).fill()
    }

    private func drawStopIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8).fill()
    }

    private func drawNextIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        let cx = rect.midX
        let cy = rect.midY
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx - 3, y: cy - 4))
        tri.line(to: NSPoint(x: cx + 2, y: cy))
        tri.line(to: NSPoint(x: cx - 3, y: cy + 4))
        tri.close()
        tri.fill()
        NSRect(x: cx + 3, y: cy - 4, width: 2, height: 8).fill()
    }

    private func drawEjectIcon(in rect: NSRect) {
        WinampTheme.buttonIconDefault.setFill()
        let cx = rect.midX
        let cy = rect.midY
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx - 4, y: cy - 1))
        tri.line(to: NSPoint(x: cx, y: cy + 4))
        tri.line(to: NSPoint(x: cx + 4, y: cy - 1))
        tri.close()
        tri.fill()
        NSRect(x: cx - 4, y: cy - 4, width: 8, height: 2).fill()
    }
}
```

- [ ] **Step 2: Create TitleBarView**

Create `WinampMac/UI/Components/TitleBarView.swift`:

```swift
import Cocoa

class TitleBarView: NSView {
    var titleText: String = "WAMP" { didSet { needsDisplay = true } }
    var showButtons: Bool = true
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let b = bounds

        // Gradient background
        let gradient = NSGradient(colors: [
            WinampTheme.titleBarTop,
            WinampTheme.titleBarBottom,
            NSColor(hex: 0x3A4460),
            WinampTheme.titleBarBottom
        ])
        gradient?.draw(in: b, angle: 90)

        // Calculate text width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.titleBarFont,
            .foregroundColor: WinampTheme.titleBarText
        ]
        let textSize = titleText.size(withAttributes: attrs)
        let textX = (b.width - textSize.width) / 2
        let textY = (b.height - textSize.height) / 2

        // Draw stripes on both sides
        let stripeMargin: CGFloat = 4
        let stripeGap: CGFloat = 4

        // Left stripes
        drawStripes(in: NSRect(
            x: stripeMargin,
            y: (b.height - 8) / 2,
            width: textX - stripeGap - stripeMargin,
            height: 8
        ))

        // Right stripes
        let rightStart = textX + textSize.width + stripeGap
        let rightEnd = showButtons ? b.width - 30 : b.width - stripeMargin
        if rightEnd > rightStart {
            drawStripes(in: NSRect(
                x: rightStart,
                y: (b.height - 8) / 2,
                width: rightEnd - rightStart,
                height: 8
            ))
        }

        // Title text
        titleText.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

        // Window buttons
        if showButtons {
            let btnSize: CGFloat = 9
            let btnY = (b.height - btnSize) / 2

            drawWindowButton(
                NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize),
                symbol: "−"
            )
            drawWindowButton(
                NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize),
                symbol: "×"
            )
        }

        // Bottom border
        WinampTheme.insetBorderDark.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: 0, y: 0))
        borderPath.line(to: NSPoint(x: b.width, y: 0))
        borderPath.lineWidth = 1
        borderPath.stroke()
    }

    private func drawStripes(in rect: NSRect) {
        guard rect.width > 2 else { return }
        var y = rect.minY
        while y < rect.maxY - 1 {
            WinampTheme.titleBarStripe1.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += 1
            WinampTheme.titleBarStripe2.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: 1).fill()
            y += 2
        }
    }

    private func drawWindowButton(_ rect: NSRect, symbol: String) {
        NSColor(hex: 0x3A4060).setFill()
        rect.fill()

        // 3D border
        WinampTheme.buttonBorderLight.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.lineWidth = 1
        path.stroke()

        WinampTheme.buttonBorderDark.setStroke()
        let path2 = NSBezierPath()
        path2.move(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path2.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path2.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path2.lineWidth = 1
        path2.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6),
            .foregroundColor: NSColor(hex: 0xA0A8C0)
        ]
        let size = symbol.size(withAttributes: attrs)
        symbol.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    // MARK: - Click handling for window buttons
    override func mouseUp(with event: NSEvent) {
        guard showButtons else { return }
        let point = convert(event.locationInWindow, from: nil)
        let b = bounds
        let btnSize: CGFloat = 9
        let btnY = (b.height - btnSize) / 2

        let minimizeRect = NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize)
        let closeRect = NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize)

        if closeRect.contains(point) {
            onClose?()
        } else if minimizeRect.contains(point) {
            onMinimize?()
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add TransportBar and TitleBarView with Winamp-style drawing"
```

---

### Task 10: MainWindow Shell

**Files:**
- Create: `WinampMac/UI/MainWindow.swift`

- [ ] **Step 1: Create MainWindow with NSStackView**

Create `WinampMac/UI/MainWindow.swift`:

```swift
import Cocoa
import Combine

class MainWindow: NSWindow {
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()
    private let stackView = NSStackView()
    private var cancellables = Set<AnyCancellable>()

    var showEqualizer: Bool = true {
        didSet {
            equalizerView.isHidden = !showEqualizer
            recalculateSize()
        }
    }

    var showPlaylist: Bool = true {
        didSet {
            playlistView.isHidden = !showPlaylist
            recalculateSize()
        }
    }

    init() {
        let rect = NSRect(x: 100, y: 100, width: WinampTheme.windowWidth, height: 510)
        super.init(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = WinampTheme.frameBackground
        hasShadow = true
        isReleasedWhenClosed = false

        setupStackView()
    }

    private func setupStackView() {
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(mainPlayerView)
        stackView.addArrangedSubview(equalizerView)
        stackView.addArrangedSubview(playlistView)

        contentView = NSView(frame: .zero)
        contentView!.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])

        // Section width constraints
        for view in [mainPlayerView, equalizerView, playlistView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: WinampTheme.windowWidth).isActive = true
        }

        mainPlayerView.heightAnchor.constraint(equalToConstant: WinampTheme.mainPlayerHeight).isActive = true
        equalizerView.heightAnchor.constraint(equalToConstant: WinampTheme.equalizerHeight).isActive = true
        playlistView.heightAnchor.constraint(greaterThanOrEqualToConstant: WinampTheme.playlistMinHeight).isActive = true

        recalculateSize()
    }

    func recalculateSize() {
        var height: CGFloat = WinampTheme.mainPlayerHeight
        if showEqualizer { height += WinampTheme.equalizerHeight }
        if showPlaylist { height += WinampTheme.playlistMinHeight }

        let origin = frame.origin
        let newFrame = NSRect(
            x: origin.x,
            y: origin.y + frame.height - height,
            width: WinampTheme.windowWidth,
            height: height
        )
        setFrame(newFrame, display: true, animate: true)
    }

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager)

        // EQ/PL toggle callbacks
        mainPlayerView.onToggleEQ = { [weak self] in
            self?.showEqualizer.toggle()
        }
        mainPlayerView.onTogglePL = { [weak self] in
            self?.showPlaylist.toggle()
        }
    }
}
```

Note: `MainPlayerView`, `EqualizerView`, and `PlaylistView` will be created in the next tasks. This file will not compile yet — that's expected. The next three tasks will add these views.

- [ ] **Step 2: Commit (work in progress)**

```bash
git add -A && git commit -m "feat: add MainWindow shell with NSStackView layout"
```

---

### Task 11: MainPlayerView

**Files:**
- Create: `WinampMac/UI/MainPlayerView.swift`

- [ ] **Step 1: Create MainPlayerView**

Create `WinampMac/UI/MainPlayerView.swift`:

```swift
import Cocoa
import Combine

class MainPlayerView: NSView {
    // Callbacks
    var onToggleEQ: (() -> Void)?
    var onTogglePL: (() -> Void)?

    // Subviews
    private let titleBar = TitleBarView()
    private let timeDisplay = SevenSegmentView()
    private let spectrumView = SpectrumView()
    private let lcdDisplay = LCDDisplay()
    private let seekSlider = WinampSlider(style: .seek)
    private let volumeSlider = WinampSlider(style: .volume)
    private let balanceSlider = WinampSlider(style: .balance)
    private let transportBar = TransportBar()

    // Toggle buttons
    private let shuffleButton = WinampButton(title: "", style: .toggle)
    private let repeatButton = WinampButton(title: "", style: .toggle)
    private let eqButton = WinampButton(title: "EQ", style: .toggle)
    private let plButton = WinampButton(title: "PL", style: .toggle)

    // Info labels
    private let bitrateLabel = NSTextField(labelWithString: "")
    private let sampleRateLabel = NSTextField(labelWithString: "")
    private let monoLabel = NSTextField(labelWithString: "mono")
    private let stereoLabel = NSTextField(labelWithString: "stereo")

    // Play state indicator
    private let playIndicator = NSView()

    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        // Title bar
        titleBar.titleText = "WAMP"
        titleBar.showButtons = true
        titleBar.onClose = { NSApp.terminate(nil) }
        titleBar.onMinimize = { NSApp.mainWindow?.miniaturize(nil) }
        addSubview(titleBar)

        // Left display panel background
        let leftPanel = NSView()
        leftPanel.wantsLayer = true
        leftPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(leftPanel)
        leftPanel.tag = 100

        // Time display
        timeDisplay.wantsLayer = true
        addSubview(timeDisplay)

        // Spectrum
        spectrumView.wantsLayer = true
        addSubview(spectrumView)

        // Right display panel
        let rightPanel = NSView()
        rightPanel.wantsLayer = true
        rightPanel.layer?.backgroundColor = NSColor.black.cgColor
        addSubview(rightPanel)
        rightPanel.tag = 101

        // LCD (track title)
        addSubview(lcdDisplay)

        // Info labels
        for label in [bitrateLabel, sampleRateLabel, monoLabel, stereoLabel] {
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.font = WinampTheme.bitrateFont
            label.textColor = WinampTheme.greenDimText
            addSubview(label)
        }

        // Seek slider
        seekSlider.maxValue = 1
        addSubview(seekSlider)

        // Volume
        volumeSlider.value = 0.75
        volumeSlider.maxValue = 1
        addSubview(volumeSlider)

        // Balance
        balanceSlider.value = 0.5
        balanceSlider.minValue = 0
        balanceSlider.maxValue = 1
        addSubview(balanceSlider)

        // Transport bar
        addSubview(transportBar)

        // Shuffle button (crossing arrows icon)
        shuffleButton.drawIcon = { rect, active in
            let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.move(to: NSPoint(x: rect.minX + 1, y: rect.midY - 2))
            path.line(to: NSPoint(x: rect.midX, y: rect.midY + 2))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY - 2))
            path.stroke()
            let path2 = NSBezierPath()
            path2.lineWidth = 1.2
            path2.move(to: NSPoint(x: rect.minX + 1, y: rect.midY + 2))
            path2.line(to: NSPoint(x: rect.midX, y: rect.midY - 2))
            path2.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY + 2))
            path2.stroke()
        }
        addSubview(shuffleButton)

        // Repeat button (loop arrows icon)
        repeatButton.drawIcon = { rect, active in
            let color = active ? WinampTheme.buttonTextActive : WinampTheme.buttonTextInactive
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            // Top arrow going right
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.midY + 1))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 1))
            path.stroke()
            // Arrow head right
            let arr1 = NSBezierPath()
            arr1.lineWidth = 1.2
            arr1.move(to: NSPoint(x: rect.maxX - 4, y: rect.midY + 3))
            arr1.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY + 1))
            arr1.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY - 1))
            arr1.stroke()
            // Bottom arrow going left
            let path2 = NSBezierPath()
            path2.lineWidth = 1.2
            path2.move(to: NSPoint(x: rect.maxX - 2, y: rect.midY - 2))
            path2.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 2))
            path2.stroke()
            // Arrow head left
            let arr2 = NSBezierPath()
            arr2.lineWidth = 1.2
            arr2.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            arr2.line(to: NSPoint(x: rect.minX + 2, y: rect.midY - 2))
            arr2.line(to: NSPoint(x: rect.minX + 4, y: rect.midY - 4))
            arr2.stroke()
        }
        addSubview(repeatButton)

        // EQ / PL buttons
        eqButton.isActive = true
        plButton.isActive = true
        addSubview(eqButton)
        addSubview(plButton)

        // Button actions
        shuffleButton.onClick = { [weak self] in
            self?.playlistManager?.toggleShuffle()
        }
        repeatButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            let next = RepeatMode(rawValue: (engine.repeatMode.rawValue + 1) % 3) ?? .off
            engine.repeatMode = next
        }
        eqButton.onClick = { [weak self] in self?.onToggleEQ?() }
        plButton.onClick = { [weak self] in self?.onTogglePL?() }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 3

        // Title bar
        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let contentTop = titleBar.frame.minY - pad
        let leftPanelW: CGFloat = 110
        let rightPanelX = leftPanelW + pad + pad
        let rightPanelW = w - rightPanelX - pad
        let displayH: CGFloat = 56

        // Left panel (black bg)
        if let leftPanel = viewWithTag(100) {
            leftPanel.frame = NSRect(x: pad, y: contentTop - displayH, width: leftPanelW, height: displayH)
        }

        // Time + play state top row (inside left panel area)
        let timeH: CGFloat = 26
        let specH = displayH - timeH - 2
        timeDisplay.frame = NSRect(x: pad + 2, y: contentTop - timeH - 2, width: leftPanelW - 4, height: timeH)
        spectrumView.frame = NSRect(x: pad + 2, y: contentTop - displayH + 2, width: leftPanelW - 4, height: specH)

        // Right panel (black bg)
        if let rightPanel = viewWithTag(101) {
            rightPanel.frame = NSRect(x: rightPanelX, y: contentTop - displayH, width: rightPanelW, height: displayH)
        }

        // LCD display
        lcdDisplay.frame = NSRect(x: rightPanelX + 4, y: contentTop - 22, width: rightPanelW - 8, height: 16)

        // Bitrate info
        bitrateLabel.frame = NSRect(x: rightPanelX + 4, y: contentTop - 42, width: 30, height: 12)
        sampleRateLabel.frame = NSRect(x: rightPanelX + 40, y: contentTop - 42, width: 30, height: 12)
        monoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 50, y: contentTop - 42, width: 22, height: 12)
        stereoLabel.frame = NSRect(x: rightPanelX + rightPanelW - 28, y: contentTop - 42, width: 28, height: 12)

        let controlsTop = contentTop - displayH - 3

        // Seek bar
        seekSlider.frame = NSRect(x: pad, y: controlsTop - 10, width: w - 2 * pad, height: 10)

        // Volume + Balance
        let sliderTop = controlsTop - 14
        let halfW = (w - 2 * pad - 4) / 2
        volumeSlider.frame = NSRect(x: pad, y: sliderTop - 8, width: halfW, height: 8)
        balanceSlider.frame = NSRect(x: pad + halfW + 4, y: sliderTop - 8, width: halfW, height: 8)

        // Transport row
        let transportTop = sliderTop - 12
        transportBar.frame = NSRect(x: pad, y: transportTop - 18, width: transportBar.intrinsicContentSize.width, height: 18)

        // Right side: shuffle, repeat, EQ, PL
        let btnH: CGFloat = 16
        let btnW: CGFloat = 20
        let toggleX = w - pad - (btnW * 4 + 3)
        let toggleY = transportTop - btnH - 1

        shuffleButton.frame = NSRect(x: toggleX, y: toggleY, width: btnW, height: btnH)
        repeatButton.frame = NSRect(x: toggleX + btnW + 1, y: toggleY, width: btnW, height: btnH)
        eqButton.frame = NSRect(x: toggleX + (btnW + 1) * 2, y: toggleY, width: btnW, height: btnH)
        plButton.frame = NSRect(x: toggleX + (btnW + 1) * 3, y: toggleY, width: btnW, height: btnH)
    }

    // MARK: - Binding
    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager

        // Time
        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.timeDisplay.timeInSeconds = time }
            .store(in: &cancellables)

        // Spectrum
        audioEngine.$spectrumData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.spectrumView.spectrumData = data }
            .store(in: &cancellables)

        // Track info
        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTrackInfo() }
            .store(in: &cancellables)

        // Seek slider
        audioEngine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in self?.seekSlider.maxValue = Float(dur) }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard self?.seekSlider.window != nil else { return }
                self?.seekSlider.value = Float(time)
            }
            .store(in: &cancellables)

        seekSlider.onChange = { [weak audioEngine] value in
            audioEngine?.seek(to: TimeInterval(value))
        }

        // Volume
        volumeSlider.value = audioEngine.volume
        volumeSlider.onChange = { [weak audioEngine] value in
            audioEngine?.volume = value
        }

        // Balance
        balanceSlider.value = (audioEngine.balance + 1) / 2 // convert -1..1 to 0..1
        balanceSlider.onChange = { [weak audioEngine] value in
            audioEngine?.balance = value * 2 - 1 // convert 0..1 to -1..1
        }

        // Transport
        transportBar.onPrevious = { [weak playlistManager] in playlistManager?.playPrevious() }
        transportBar.onPlay = { [weak audioEngine] in audioEngine?.play() }
        transportBar.onPause = { [weak audioEngine] in audioEngine?.pause() }
        transportBar.onStop = { [weak audioEngine] in audioEngine?.stop() }
        transportBar.onNext = { [weak playlistManager] in playlistManager?.playNext() }
        transportBar.onEject = { [weak self] in self?.showOpenFilePanel() }

        // Play state
        audioEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.transportBar.playButton.isActive = playing
            }
            .store(in: &cancellables)

        // Shuffle state
        playlistManager.$isShuffled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shuffled in
                self?.shuffleButton.isActive = shuffled
            }
            .store(in: &cancellables)

        // Repeat state
        audioEngine.$repeatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.repeatButton.isActive = mode != .off
            }
            .store(in: &cancellables)
    }

    private func updateTrackInfo() {
        guard let track = playlistManager?.currentTrack else {
            lcdDisplay.text = ""
            bitrateLabel.stringValue = ""
            sampleRateLabel.stringValue = ""
            return
        }
        let index = (playlistManager?.currentIndex ?? 0) + 1
        lcdDisplay.text = "\(index). \(track.displayTitle) (\(track.formattedDuration))"
        bitrateLabel.stringValue = "\(track.bitrate > 0 ? "\(track.bitrate)" : "---")"
        bitrateLabel.textColor = WinampTheme.greenBright
        sampleRateLabel.stringValue = "\(track.sampleRate > 0 ? "\(track.sampleRate / 1000)" : "--")"
        sampleRateLabel.textColor = WinampTheme.greenBright
        stereoLabel.textColor = track.isStereo ? WinampTheme.greenBright : WinampTheme.greenDimText
        monoLabel.textColor = track.isStereo ? WinampTheme.greenDimText : WinampTheme.greenBright
    }

    private func showOpenFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task {
                for url in panel.urls {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        await self?.playlistManager?.addFolder(url)
                    } else {
                        await self?.playlistManager?.addURLs([url])
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build (expect failure — EqualizerView and PlaylistView not yet created)**

This is expected. We'll create them in the next two tasks.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add MainPlayerView with full display, transport, and bindings"
```

---

### Task 12: EqualizerView

**Files:**
- Create: `WinampMac/UI/EqualizerView.swift`

- [ ] **Step 1: Create EqualizerView**

Create `WinampMac/UI/EqualizerView.swift`:

```swift
import Cocoa
import Combine

struct EQPreset {
    let name: String
    let bands: [Float]

    nonisolated static let presets: [EQPreset] = [
        EQPreset(name: "Flat", bands: [0,0,0,0,0,0,0,0,0,0]),
        EQPreset(name: "Rock", bands: [5,4,3,1,-1,-1,0,2,3,4]),
        EQPreset(name: "Pop", bands: [-1,2,4,5,3,0,-1,-2,-1,0]),
        EQPreset(name: "Jazz", bands: [4,3,1,2,-2,-2,0,1,3,4]),
        EQPreset(name: "Classical", bands: [5,4,3,2,-1,-1,0,2,3,4]),
        EQPreset(name: "Bass Boost", bands: [8,6,4,2,0,0,0,0,0,0]),
        EQPreset(name: "Treble Boost", bands: [0,0,0,0,0,1,3,5,7,8]),
        EQPreset(name: "Vocal", bands: [-2,-1,0,3,5,5,3,1,0,-2]),
        EQPreset(name: "Electronic", bands: [6,4,1,0,-2,2,1,2,5,6]),
        EQPreset(name: "Loudness", bands: [6,4,0,-2,-1,0,-1,-2,5,2]),
    ]
}

class EqualizerView: NSView {
    private let titleBar = TitleBarView()
    private let onButton = WinampButton(title: "ON", style: .toggle)
    private let autoButton = WinampButton(title: "AUTO", style: .toggle)
    private let presetsButton = WinampButton(title: "PRESETS", style: .action)
    private let preampSlider = WinampSlider(style: .eqBand, isVertical: true)
    private let responseView = EQResponseView()
    private var bandSliders: [WinampSlider] = []
    private var bandLabels: [NSTextField] = []
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    private let bandNames = ["70", "180", "320", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        titleBar.titleText = "WAMP EQUALIZER"
        titleBar.showButtons = false
        addSubview(titleBar)

        onButton.isActive = true
        onButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            engine.eqEnabled.toggle()
            self?.onButton.isActive = engine.eqEnabled
        }
        addSubview(onButton)

        autoButton.isActive = false
        autoButton.onClick = { [weak self] in
            self?.autoButton.isActive.toggle()
        }
        addSubview(autoButton)

        presetsButton.onClick = { [weak self] in self?.showPresetsMenu() }
        addSubview(presetsButton)

        // Preamp
        preampSlider.value = 0
        preampSlider.onChange = { [weak self] value in
            self?.audioEngine?.setPreamp(gain: value)
        }
        addSubview(preampSlider)

        // Response curve
        addSubview(responseView)

        // 10 band sliders
        for i in 0..<10 {
            let slider = WinampSlider(style: .eqBand, isVertical: true)
            slider.value = 0
            let bandIndex = i
            slider.onChange = { [weak self] value in
                self?.audioEngine?.setEQ(band: bandIndex, gain: value)
                self?.responseView.bands = self?.audioEngine?.eqBands ?? []
            }
            bandSliders.append(slider)
            addSubview(slider)

            let label = NSTextField(labelWithString: bandNames[i])
            label.font = WinampTheme.eqLabelFont
            label.textColor = WinampTheme.eqBandLabelColor
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .center
            bandLabels.append(label)
            addSubview(label)
        }

        // dB labels
        for (text, tag) in [("+12", 200), ("0", 201), ("-12", 202)] {
            let label = NSTextField(labelWithString: text)
            label.font = WinampTheme.eqLabelFont
            label.textColor = WinampTheme.eqDbLabelColor
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .right
            label.tag = tag
            addSubview(label)
        }

        // Preamp label
        let preLabel = NSTextField(labelWithString: "PRE")
        preLabel.font = WinampTheme.eqLabelFont
        preLabel.textColor = WinampTheme.eqBandLabelColor
        preLabel.isBezeled = false
        preLabel.drawsBackground = false
        preLabel.alignment = .center
        preLabel.tag = 210
        addSubview(preLabel)

        // dB label under response
        let dbLabel = NSTextField(labelWithString: "dB")
        dbLabel.font = WinampTheme.eqLabelFont
        dbLabel.textColor = WinampTheme.eqBandLabelColor
        dbLabel.isBezeled = false
        dbLabel.drawsBackground = false
        dbLabel.alignment = .center
        dbLabel.tag = 211
        addSubview(dbLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 4

        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let controlsY = bounds.height - WinampTheme.titleBarHeight - 16
        onButton.frame = NSRect(x: pad, y: controlsY, width: 26, height: 14)
        autoButton.frame = NSRect(x: pad + 28, y: controlsY, width: 30, height: 14)
        presetsButton.frame = NSRect(x: w - pad - 50, y: controlsY, width: 50, height: 14)

        let sliderAreaY: CGFloat = 10
        let sliderH: CGFloat = 62
        let sliderAreaTop = controlsY - 4

        // dB labels
        let dbLabelX: CGFloat = pad
        let dbLabelW: CGFloat = 16
        viewWithTag(200)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - 10, width: dbLabelW, height: 10)
        viewWithTag(201)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - sliderH / 2 - 5, width: dbLabelW, height: 10)
        viewWithTag(202)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - sliderH, width: dbLabelW, height: 10)

        // Preamp
        let preampX = dbLabelX + dbLabelW + 2
        preampSlider.frame = NSRect(x: preampX, y: sliderAreaTop - sliderH, width: 12, height: sliderH)
        viewWithTag(210)?.frame = NSRect(x: preampX - 2, y: sliderAreaTop - sliderH - 10, width: 16, height: 10)

        // Response view
        let respX = preampX + 16
        responseView.frame = NSRect(x: respX, y: sliderAreaTop - sliderH, width: 30, height: sliderH)
        viewWithTag(211)?.frame = NSRect(x: respX + 8, y: sliderAreaTop - sliderH - 10, width: 16, height: 10)

        // Band sliders
        let bandsStart = respX + 36
        let bandsWidth = w - bandsStart - pad
        let bandSpacing = bandsWidth / CGFloat(10)

        for i in 0..<10 {
            let x = bandsStart + CGFloat(i) * bandSpacing + (bandSpacing - 12) / 2
            bandSliders[i].frame = NSRect(x: x, y: sliderAreaTop - sliderH, width: 12, height: sliderH)
            bandLabels[i].frame = NSRect(x: x - 4, y: sliderAreaTop - sliderH - 10, width: 20, height: 10)
        }
    }

    func bindToModel(audioEngine: AudioEngine, playlistManager: PlaylistManager? = nil) {
        self.audioEngine = audioEngine

        audioEngine.$eqEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.onButton.isActive = enabled }
            .store(in: &cancellables)

        // AUTO mode: match genre to preset when track changes
        if let pm = playlistManager {
            pm.$currentIndex
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.autoApplyPreset(for: pm.currentTrack) }
                .store(in: &cancellables)
        }
    }

    private func autoApplyPreset(for track: Track?) {
        guard autoButton.isActive, let genre = track?.genre.lowercased(), !genre.isEmpty else { return }
        let genrePresetMap: [String: String] = [
            "rock": "Rock", "pop": "Pop", "jazz": "Jazz",
            "classical": "Classical", "electronic": "Electronic",
            "dance": "Electronic", "hip-hop": "Bass Boost", "r&b": "Vocal"
        ]
        let presetName = genrePresetMap.first { genre.contains($0.key) }?.value ?? "Flat"
        if let preset = EQPreset.presets.first(where: { $0.name == presetName }) {
            audioEngine?.setAllEQBands(preset.bands)
            for (i, slider) in bandSliders.enumerated() {
                slider.value = preset.bands[i]
            }
            responseView.bands = preset.bands
        }
    }

    private func showPresetsMenu() {
        let menu = NSMenu()
        for preset in EQPreset.presets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: presetsButton.frame.minX, y: presetsButton.frame.minY), in: self)
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        audioEngine?.setAllEQBands(preset.bands)
        for (i, slider) in bandSliders.enumerated() {
            slider.value = preset.bands[i]
        }
        responseView.bands = preset.bands
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add EqualizerView with 10 bands, preamp, presets, response curve"
```

---

### Task 13: PlaylistView

**Files:**
- Create: `WinampMac/UI/PlaylistView.swift`

- [ ] **Step 1: Create PlaylistView**

Create `WinampMac/UI/PlaylistView.swift`:

```swift
import Cocoa
import Combine
import UniformTypeIdentifiers

class PlaylistView: NSView {
    private let titleBar = TitleBarView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let searchField = NSTextField()
    private let addButton = WinampButton(title: "ADD", style: .action)
    private let remButton = WinampButton(title: "REM", style: .action)
    private let clrButton = WinampButton(title: "CLR", style: .action)
    private let infoLabel = NSTextField(labelWithString: "")

    private var cancellables = Set<AnyCancellable>()
    private weak var playlistManager: PlaylistManager?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        titleBar.titleText = "WAMP PLAYLIST"
        titleBar.showButtons = false
        addSubview(titleBar)

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.width = WinampTheme.windowWidth - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .black
        tableView.rowHeight = 18
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(doubleClickRow)
        tableView.target = self
        tableView.selectionHighlightStyle = .none
        tableView.gridStyleMask = []

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.backgroundColor = .black
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        // Custom scroller appearance
        scrollView.verticalScroller?.controlSize = .small
        addSubview(scrollView)

        // Search field
        searchField.placeholderString = "Search playlist..."
        searchField.font = WinampTheme.bitrateFont
        searchField.textColor = WinampTheme.greenBright
        searchField.backgroundColor = NSColor(hex: 0x0A0E0A)
        searchField.isBordered = true
        searchField.isBezeled = true
        searchField.bezelStyle = .squareBezel
        searchField.focusRingType = .none
        searchField.delegate = self
        addSubview(searchField)

        // Buttons
        addButton.onClick = { [weak self] in self?.showAddMenu() }
        remButton.onClick = { [weak self] in self?.removeSelected() }
        clrButton.onClick = { [weak self] in self?.playlistManager?.clearPlaylist() }
        addSubview(addButton)
        addSubview(remButton)
        addSubview(clrButton)

        // Info label
        infoLabel.font = WinampTheme.bitrateFont
        infoLabel.textColor = WinampTheme.greenBright
        infoLabel.backgroundColor = .black
        infoLabel.drawsBackground = true
        infoLabel.isBezeled = false
        infoLabel.isEditable = false
        infoLabel.alignment = .center
        addSubview(infoLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 3

        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let bottomBarH: CGFloat = 18
        let searchH: CGFloat = 16
        let scrollTop = bounds.height - WinampTheme.titleBarHeight

        // Bottom bar
        let btnW: CGFloat = 30
        let btnH: CGFloat = 14
        addButton.frame = NSRect(x: pad, y: 2, width: btnW, height: btnH)
        remButton.frame = NSRect(x: pad + btnW + 1, y: 2, width: btnW, height: btnH)
        clrButton.frame = NSRect(x: pad + (btnW + 1) * 2, y: 2, width: btnW, height: btnH)

        let infoW: CGFloat = 100
        infoLabel.frame = NSRect(x: w - pad - infoW, y: 2, width: infoW, height: btnH)

        // Search
        searchField.frame = NSRect(x: pad, y: bottomBarH, width: w - 2 * pad, height: searchH)

        // Scroll view
        let scrollH = scrollTop - bottomBarH - searchH - 2
        scrollView.frame = NSRect(x: pad, y: bottomBarH + searchH + 1, width: w - 2 * pad, height: scrollH)

        tableView.tableColumns.first?.width = scrollView.frame.width - 14
    }

    func bindToModel(playlistManager: PlaylistManager) {
        self.playlistManager = playlistManager

        playlistManager.$tracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateInfoLabel()
            }
            .store(in: &cancellables)

        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    private func updateInfoLabel() {
        guard let pm = playlistManager else { return }
        infoLabel.stringValue = "\(pm.tracks.count) tracks / \(pm.formattedTotalDuration)"
    }

    @objc private func doubleClickRow() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        let tracks = displayedTracks
        guard row < tracks.count else { return }
        // Find the actual index in the full playlist
        if let realIndex = playlistManager?.tracks.firstIndex(where: { $0.id == tracks[row].id }) {
            playlistManager?.playTrack(at: realIndex)
        }
    }

    private func removeSelected() {
        let indices = tableView.selectedRowIndexes.sorted().reversed()
        for index in indices {
            playlistManager?.removeTrack(at: index)
        }
    }

    private func showAddMenu() {
        let menu = NSMenu()
        let fileItem = NSMenuItem(title: "Add Files...", action: #selector(addFiles), keyEquivalent: "")
        fileItem.target = self
        let folderItem = NSMenuItem(title: "Add Folder...", action: #selector(addFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(fileItem)
        menu.addItem(folderItem)
        menu.popUp(positioning: nil, at: NSPoint(x: addButton.frame.minX, y: addButton.frame.maxY), in: self)
    }

    @objc private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { await self?.playlistManager?.addURLs(panel.urls) }
        }
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.playlistManager?.addFolder(url) }
        }
    }

    // MARK: - Drag and Drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        Task {
            for url in items {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    await playlistManager?.addFolder(url)
                } else {
                    await playlistManager?.addURLs([url])
                }
            }
        }
        return true
    }
}

// MARK: - NSTableViewDataSource / Delegate
extension PlaylistView: NSTableViewDataSource, NSTableViewDelegate {
    private var displayedTracks: [Track] {
        playlistManager?.filteredTracks ?? []
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedTracks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tracks = displayedTracks
        guard row < tracks.count else { return nil }
        let track = tracks[row]
        let isPlaying = playlistManager?.currentTrack?.id == track.id

        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? 200, height: 18))
        cell.wantsLayer = true

        // Number
        let numLabel = NSTextField(labelWithString: "\(row + 1).")
        numLabel.font = WinampTheme.playlistFont
        numLabel.textColor = isPlaying ? WinampTheme.white : WinampTheme.greenSecondary
        numLabel.isBezeled = false
        numLabel.drawsBackground = false
        numLabel.frame = NSRect(x: 4, y: 0, width: 20, height: 18)
        cell.addSubview(numLabel)

        // Track name
        let nameLabel = NSTextField(labelWithString: track.displayTitle)
        nameLabel.font = WinampTheme.playlistFont
        nameLabel.textColor = isPlaying ? WinampTheme.white : WinampTheme.greenBright
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 26, y: 0, width: (tableColumn?.width ?? 200) - 70, height: 18)
        cell.addSubview(nameLabel)

        // Duration
        let durLabel = NSTextField(labelWithString: track.formattedDuration)
        durLabel.font = WinampTheme.playlistFont
        durLabel.textColor = isPlaying ? WinampTheme.white : WinampTheme.greenSecondary
        durLabel.isBezeled = false
        durLabel.drawsBackground = false
        durLabel.alignment = .right
        durLabel.frame = NSRect(x: (tableColumn?.width ?? 200) - 40, y: 0, width: 36, height: 18)
        cell.addSubview(durLabel)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = WinampRowView()
        return rowView
    }
}

// Custom row view with Winamp-style blue selection
class WinampRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            WinampTheme.selectionBlue.setFill()
            bounds.fill()
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
    }
}

// MARK: - Search
extension PlaylistView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        playlistManager?.searchQuery = searchField.stringValue
        tableView.reloadData()
    }
}
```

- [ ] **Step 2: Build and verify**

Now all three views exist. Build should succeed:

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add PlaylistView with table, search, drag-drop, custom row selection"
```

---

### Task 14: Wire Everything in AppDelegate

**Files:**
- Modify: `WinampMac/AppDelegate.swift`

- [ ] **Step 1: Replace AppDelegate with full wiring**

Replace `WinampMac/AppDelegate.swift`:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    let audioEngine = AudioEngine()
    let playlistManager = PlaylistManager()
    let stateManager = StateManager()
    var mainWindow: MainWindow!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        playlistManager.setAudioEngine(audioEngine)

        // Restore state
        let appState = stateManager.loadAppState()
        audioEngine.volume = appState.volume
        audioEngine.balance = appState.balance
        audioEngine.repeatMode = RepeatMode(rawValue: appState.repeatMode) ?? .off
        audioEngine.eqEnabled = appState.eqEnabled
        playlistManager.isShuffled = appState.isShuffled

        let eqState = stateManager.loadEQState()
        audioEngine.setAllEQBands(eqState.bands)
        audioEngine.setPreamp(gain: eqState.preampGain)

        let savedTracks = stateManager.loadSavedPlaylist()
        if !savedTracks.isEmpty {
            playlistManager.addTracks(savedTracks)
            if appState.lastTrackIndex >= 0, appState.lastTrackIndex < savedTracks.count {
                playlistManager.currentIndex = appState.lastTrackIndex
            }
        }

        // Create window
        mainWindow = MainWindow()
        mainWindow.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        mainWindow.showEqualizer = appState.showEqualizer
        mainWindow.showPlaylist = appState.showPlaylist

        let windowOrigin = NSPoint(x: appState.windowX, y: appState.windowY)
        mainWindow.setFrameOrigin(windowOrigin)
        mainWindow.makeKeyAndOrderFront(nil)

        // Start observing for auto-save
        stateManager.observe(audioEngine: audioEngine, playlistManager: playlistManager)

        // Setup menu bar
        setupMainMenu()

        // Setup system tray
        setupStatusItem()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateManager.saveWindowState(
            x: mainWindow.frame.origin.x,
            y: mainWindow.frame.origin.y,
            showEQ: mainWindow.showEqualizer,
            showPlaylist: mainWindow.showPlaylist,
            audioEngine: audioEngine,
            playlistManager: playlistManager
        )
        stateManager.saveEQState(audioEngine: audioEngine)
        stateManager.savePlaylist(playlistManager: playlistManager)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task {
            await playlistManager.addURLs(urls)
        }
    }

    // MARK: - Main Menu
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About WinampMac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit WinampMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        let openFile = NSMenuItem(title: "Open File...", action: #selector(openFileAction), keyEquivalent: "o")
        openFile.target = self
        fileMenu.addItem(openFile)
        let openFolder = NSMenuItem(title: "Open Folder...", action: #selector(openFolderAction), keyEquivalent: "O")
        openFolder.target = self
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(openFolder)
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Controls menu
        let controlsMenu = NSMenu(title: "Controls")
        let playPause = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: " ")
        playPause.target = self
        controlsMenu.addItem(playPause)
        let stop = NSMenuItem(title: "Stop", action: #selector(stopAction), keyEquivalent: ".")
        stop.target = self
        controlsMenu.addItem(stop)
        let next = NSMenuItem(title: "Next", action: #selector(nextAction), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        next.target = self
        next.keyEquivalentModifierMask = [.command]
        controlsMenu.addItem(next)
        let prev = NSMenuItem(title: "Previous", action: #selector(prevAction), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        prev.target = self
        prev.keyEquivalentModifierMask = [.command]
        controlsMenu.addItem(prev)
        controlsMenu.addItem(.separator())
        let repeat_ = NSMenuItem(title: "Repeat", action: #selector(toggleRepeat), keyEquivalent: "r")
        repeat_.target = self
        controlsMenu.addItem(repeat_)
        let shuffle = NSMenuItem(title: "Shuffle", action: #selector(toggleShuffle), keyEquivalent: "s")
        shuffle.target = self
        controlsMenu.addItem(shuffle)
        let controlsMenuItem = NSMenuItem()
        controlsMenuItem.submenu = controlsMenu
        mainMenu.addItem(controlsMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let showPlayer = NSMenuItem(title: "Show Player", action: #selector(showPlayerAction), keyEquivalent: "1")
        showPlayer.target = self
        viewMenu.addItem(showPlayer)
        let showEQ = NSMenuItem(title: "Show Equalizer", action: #selector(toggleEQ), keyEquivalent: "2")
        showEQ.target = self
        viewMenu.addItem(showEQ)
        let showPL = NSMenuItem(title: "Show Playlist", action: #selector(togglePL), keyEquivalent: "3")
        showPL.target = self
        viewMenu.addItem(showPL)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions
    @objc private func openFileAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { await self?.playlistManager.addURLs(panel.urls) }
        }
    }

    @objc private func openFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.playlistManager.addFolder(url) }
        }
    }

    @objc private func togglePlayPause() { audioEngine.togglePlayPause() }
    @objc private func stopAction() { audioEngine.stop() }
    @objc private func nextAction() { playlistManager.playNext() }
    @objc private func prevAction() { playlistManager.playPrevious() }

    @objc private func toggleRepeat() {
        let next = RepeatMode(rawValue: (audioEngine.repeatMode.rawValue + 1) % 3) ?? .off
        audioEngine.repeatMode = next
    }

    @objc private func toggleShuffle() { playlistManager.toggleShuffle() }

    @objc private func showPlayerAction() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEQ() { mainWindow.showEqualizer.toggle() }
    @objc private func togglePL() { mainWindow.showPlaylist.toggle() }

    // MARK: - System Tray
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "♪"

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Player", action: #selector(showPlayerAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let playPause = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: "")
        playPause.target = self
        menu.addItem(playPause)
        let next = NSMenuItem(title: "Next Track", action: #selector(nextAction), keyEquivalent: "")
        next.target = self
        menu.addItem(next)
        let prev = NSMenuItem(title: "Previous Track", action: #selector(prevAction), keyEquivalent: "")
        prev.target = self
        menu.addItem(prev)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        statusItem.menu = menu
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: wire AppDelegate with menu bar, system tray, state restore"
```

---

### Task 15: HotKeyManager — Media Keys and Now Playing

**Files:**
- Create: `WinampMac/Utils/HotKeyManager.swift`
- Modify: `WinampMac/AppDelegate.swift` (add HotKeyManager init)

- [ ] **Step 1: Create HotKeyManager**

Create `WinampMac/Utils/HotKeyManager.swift`:

```swift
import Foundation
import MediaPlayer

class HotKeyManager {
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?

    init(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager
        setupRemoteCommands()
        setupNowPlayingUpdates()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.audioEngine?.play()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.audioEngine?.pause()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.audioEngine?.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playlistManager?.playNext()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playlistManager?.playPrevious()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.audioEngine?.seek(to: posEvent.positionTime)
            return .success
        }
    }

    private func setupNowPlayingUpdates() {
        // Update periodically
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNowPlaying()
        }
    }

    func updateNowPlaying() {
        guard let engine = audioEngine,
              let track = playlistManager?.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: engine.isPlaying ? 1.0 : 0.0
        ]

        if !track.album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = track.album
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
```

- [ ] **Step 2: Add HotKeyManager to AppDelegate**

In `WinampMac/AppDelegate.swift`, add a property and initialization:

Add property after `var statusItem`:
```swift
var hotKeyManager: HotKeyManager!
```

Add after `setupStatusItem()` in `applicationDidFinishLaunching`:
```swift
hotKeyManager = HotKeyManager(audioEngine: audioEngine, playlistManager: playlistManager)
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add HotKeyManager with media keys and Now Playing integration"
```

---

### Task 16: Final Build Verification and Fix Any Issues

- [ ] **Step 1: Clean build**

Run: `xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug clean build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Fix any compilation errors**

If there are errors, fix them. Common issues to watch for:
- Missing `import` statements
- `@MainActor` isolation issues — use `nonisolated` on Codable conformances and callbacks from audio threads
- Missing `@objc` on selector methods
- Type mismatches between `Float` and `CGFloat`

- [ ] **Step 3: Run the app**

Run: `open WinampMac.xcodeproj` and hit Cmd+R in Xcode, or:
```bash
xcodebuild -project WinampMac.xcodeproj -scheme WinampMac -configuration Debug build 2>&1 | tail -5 && open build/Debug/WinampMac.app
```

Verify:
- Window appears with Winamp-style dark metallic frame
- Title bar shows "WAMP" with orange stripes
- Transport buttons are visible and clickable
- EQ and PL toggle buttons show/hide sections
- System tray icon (♪) appears in menu bar
- Menu bar has File, Controls, View menus with shortcuts
- Drag audio files onto playlist — they appear in the list
- Double-click a track — audio plays, time display updates, spectrum animates

- [ ] **Step 4: Final commit**

```bash
git add -A && git commit -m "fix: resolve build issues and verify full application launch"
```
