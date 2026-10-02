import Foundation
import AVFoundation
import Combine
import Accelerate

enum RepeatMode: Int, Codable {
    case off = 0
    case track = 1
    case playlist = 2
}

enum PlayState {
    case stopped
    case playing
    case paused
}

extension Notification.Name {
    static let trackDidFinish = Notification.Name("trackDidFinish")
}

extension AudioEngine {
    /// userInfo key on `.trackDidFinish`: true when the engine has already
    /// promoted a queued gapless segment and audio is continuing seamlessly —
    /// the playlist should only advance its index, not start playback anew.
    static let gaplessChainedKey = "gaplessChained"
}

class AudioEngine: ObservableObject {
    // MARK: - Published State
    @Published var isPlaying = false
    @Published var playState: PlayState = .stopped
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
    @Published var spectrumData: [Float] = []
    /// Number of analyzer bars the UI draws (19 skinned, 26 built-in). Set by
    /// the view on layout; the tap reads it once per buffer.
    var spectrumBarCount = 19

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
    private var playbackGeneration: UInt64 = 0
    /// Upper frame bound of the segment currently scheduled. Matches
    /// `audioLengthFrames` for a whole-file play, or the CUE track's end frame
    /// when we're playing a bounded segment.
    private var currentSegmentEndFrame: AVAudioFramePosition = 0
    /// Logical start frame of the current track's segment (0 for whole-file
    /// playback, the CUE start frame for virtual tracks). Unlike `seekFrame`
    /// it is not moved by seeks — repeat-one loops back to it.
    private var currentSegmentStartFrame: AVAudioFramePosition = 0
    /// Set by `chainNextSegment` when a follow-up segment has already been
    /// queued on the player node. Consumed by `handleTrackCompletion` so the
    /// engine keeps playing into the chained segment without re-loading.
    private var pendingChain: (startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition)?

    private var effectiveVolume: Float {
        isMuted ? 0 : volume
    }

    // MARK: - Spectrum FFT state (touched only from the tap thread)
    private var spectrumFFTSetup: FFTSetup?
    private var spectrumFFTSize = 0
    private var spectrumSampleRate: Float = 0
    private var spectrumBars = 0
    private var spectrumWindow: [Float] = []
    private var spectrumWindowed: [Float] = []
    private var spectrumReal: [Float] = []
    private var spectrumImag: [Float] = []
    private var spectrumPower: [Float] = []
    /// FFT bin range per displayed bar, log-spaced between min/max frequency.
    private var spectrumRanges: [Range<Int>] = []
    private var spectrumNormalization: Float = 0
    private static let spectrumMinFrequency: Float = 32
    private static let spectrumMaxFrequency: Float = 16_000
    /// pow(amplitude, x): 1.0 is linear, lower lifts quiet bands.
    private static let spectrumCompression: Float = 0.5
    private static let spectrumGain: Float = pow(10, 4.5 / 20) // +4.5 dB

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
            // Shelves on the outer bands so the 70 Hz / 16 kHz sliders lift
            // or cut everything beyond them, not just a bell around the center.
            switch i {
            case 0: band.filterType = .lowShelf
            case Self.eqFrequencies.count - 1: band.filterType = .highShelf
            default: band.filterType = .parametric
            }
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    // MARK: - Playback Controls

    /// Loads an audio file and prepares duration/metadata without starting playback.
    func load(url: URL) {
        stop()
        playbackGeneration &+= 1

        do {
            try loadFile(url: url)
        } catch {
            debugLog("🔴 failed to load \(url.lastPathComponent): \(error)")
        }
    }

    func loadAndPlay(url: URL) {
        debugLog("🔵 \(url.lastPathComponent), gen=\(playbackGeneration)")
        stop()
        playbackGeneration &+= 1
        debugLog("🔵 after stop, new gen=\(playbackGeneration)")

        do {
            try loadFile(url: url)

            if !engine.isRunning {
                try engine.start()
                debugLog("🔵 engine started")
            }
            installSpectrumTap()
            scheduleAndPlay()
        } catch {
            debugLog("🔴 failed to load \(url.lastPathComponent): \(error)")
        }
    }

    /// Schedule a follow-up segment back-to-back on the same player node —
    /// no `stop()`, no reload — so the boundary is sample-exact. Returns true
    /// on success, false if the engine isn't currently playing this file.
    ///
    /// The chained segment's completion handler fires `.trackDidFinish` when
    /// the chained segment itself ends. When the *prior* segment ends its
    /// completion handler will also fire; it consumes `pendingChain` and
    /// updates the seek/end bookkeeping without interrupting playback.
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

        let generation = playbackGeneration
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
        pendingChain = (startFrame: max(0, startFrame), endFrame: endFrame)
        return true
    }

    /// Load `url` and play from `startTime` until `endTime` (or EOF if nil).
    /// Used for CUE-derived virtual tracks. When playback reaches the end frame
    /// the completion handler posts `.trackDidFinish` exactly like a normal track.
    func loadAndPlay(url: URL, startTime: TimeInterval, endTime: TimeInterval?) {
        debugLog("🔵 \(url.lastPathComponent) [\(startTime), \(endTime as Any)]")
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
            currentSegmentStartFrame = seekFrame
            scheduleSegment(endFrame: endFrame)
        } catch {
            debugLog("🔴 failed to load \(url.lastPathComponent): \(error)")
        }
    }

    /// Shared helper: opens the audio file and sets duration/sample-rate metadata.
    private func loadFile(url: URL) throws {
        audioFile = try AVAudioFile(forReading: url)
        guard let file = audioFile else {
            debugLog("🔴 audioFile is nil after init")
            return
        }

        audioSampleRate = file.processingFormat.sampleRate
        audioLengthFrames = file.length
        duration = Double(audioLengthFrames) / audioSampleRate
        seekFrame = 0
        needsScheduling = true
        currentSegmentStartFrame = 0
        currentSegmentEndFrame = 0
        debugLog("🔵 file loaded, sampleRate=\(audioSampleRate), frames=\(audioLengthFrames), duration=\(duration)s")
    }

    func play() {
        guard audioFile != nil else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            installSpectrumTap()
            if needsScheduling {
                // Respect the active CUE segment bound (set by a paused seek);
                // scheduling to EOF here would bleed past the cue track's end.
                scheduleSegment(endFrame: currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames)
            } else {
                playerNode.play()
            }
            isPlaying = true
            playState = .playing
            startTimeUpdates()
        } catch {
            debugLog("failed to start: \(error)")
        }
    }

    func pause() {
        // Pausing a stopped engine would arm Play's "resume" path with
        // whatever file was loaded last — possibly one no longer in the list.
        guard playState == .playing else { return }
        playerNode.pause()
        isPlaying = false
        playState = .paused
        stopTimeUpdates()
    }

    func stop() {
        debugLog("🟡 stop() called, gen=\(playbackGeneration), isPlaying=\(isPlaying)")
        playerNode.stop()
        isPlaying = false
        playState = .stopped
        currentTime = 0
        seekFrame = 0
        needsScheduling = true
        pendingChain = nil
        currentSegmentStartFrame = 0
        currentSegmentEndFrame = 0
        stopTimeUpdates()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil else { return }
        let targetFrame = AVAudioFramePosition(time * audioSampleRate)
        let upperBound = currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames
        seekFrame = max(0, min(targetFrame, upperBound))
        needsScheduling = true
        // Rescheduling wipes the player node's queue, so any chained gapless
        // segment is gone — forget it, or completion bookkeeping derails.
        pendingChain = nil

        if isPlaying {
            scheduleSegment(endFrame: upperBound)
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
        // Preamp lives on the EQ unit (like Winamp, it's bypassed with the EQ).
        // Folding it into the mixer volume capped any boost at outputVolume 1.0.
        eq.globalGain = preampGain
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
        scheduleSegment(endFrame: audioLengthFrames)
    }

    private func scheduleSegment(endFrame: AVAudioFramePosition) {
        guard let file = audioFile else {
            debugLog("🔴 no audioFile")
            return
        }
        let framesToPlay = endFrame - seekFrame
        debugLog("🟢 framesToPlay=\(framesToPlay), seekFrame=\(seekFrame), endFrame=\(endFrame), gen=\(playbackGeneration)")
        guard framesToPlay > 0 else {
            debugLog("🔴 no frames to play, calling handleTrackCompletion")
            handleTrackCompletion()
            return
        }

        // Invalidate completion handlers of whatever was scheduled before:
        // playerNode.stop() fires them asynchronously, and without the bump
        // they'd be mistaken for a genuine end-of-segment.
        playbackGeneration &+= 1
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
        currentSegmentEndFrame = capturedEnd
        startTimeUpdates()
    }

    private func handleTrackCompletion() {
        debugLog("🔴 isPlaying=\(isPlaying), repeatMode=\(repeatMode), gen=\(playbackGeneration)")
        guard isPlaying else {
            debugLog("🔴 NOT playing, ignoring")
            return
        }

        if repeatMode == .track {
            // Loop the current track's segment, not the whole file — for a CUE
            // virtual track that segment is a slice of the album file.
            pendingChain = nil
            seekFrame = currentSegmentStartFrame
            needsScheduling = true
            scheduleSegment(endFrame: currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames)
            return
        }

        // Gapless chain: the next segment is already queued on the player node
        // and may already be feeding audio. Adopt its bookkeeping and notify
        // the playlist, but do NOT stop or reset the engine.
        if let pending = pendingChain {
            // playerTime.sampleTime keeps counting across the chain boundary
            // (no node stop), so rebase seekFrame by the just-finished
            // segment's length — otherwise currentTime overcounts by it.
            let finishedLength = max(0, currentSegmentEndFrame - seekFrame)
            seekFrame = pending.startFrame - finishedLength
            currentSegmentStartFrame = pending.startFrame
            currentSegmentEndFrame = pending.endFrame
            pendingChain = nil
            debugLog("🟢 promoted chained segment [\(pending.startFrame), \(pending.endFrame)]")
            NotificationCenter.default.post(name: .trackDidFinish, object: nil,
                                            userInfo: [AudioEngine.gaplessChainedKey: true])
            return
        }

        isPlaying = false
        playState = .stopped
        stopTimeUpdates()
        debugLog("🔴 posting .trackDidFinish")
        NotificationCenter.default.post(name: .trackDidFinish, object: nil)
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

    /// (Re)builds the FFT setup, Hann window, scratch buffers and per-bar bin
    /// ranges when the buffer size, sample rate or bar count changes — not on
    /// every tap callback.
    private func prepareSpectrumFFT(fftSize: Int, sampleRate: Float, bars: Int) -> FFTSetup? {
        if let setup = spectrumFFTSetup, fftSize == spectrumFFTSize,
           sampleRate == spectrumSampleRate, bars == spectrumBars {
            return setup
        }
        if let setup = spectrumFFTSetup {
            vDSP_destroy_fftsetup(setup)
            spectrumFFTSetup = nil
        }
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }

        let halfSize = fftSize / 2
        spectrumFFTSetup = setup
        spectrumFFTSize = fftSize
        spectrumSampleRate = sampleRate
        spectrumBars = bars
        spectrumWindow = [Float](repeating: 0, count: fftSize)
        spectrumWindowed = [Float](repeating: 0, count: fftSize)
        spectrumReal = [Float](repeating: 0, count: halfSize)
        spectrumImag = [Float](repeating: 0, count: halfSize)
        spectrumPower = [Float](repeating: 0, count: halfSize)
        vDSP_hann_window(&spectrumWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_sve(spectrumWindow, 1, &spectrumNormalization, vDSP_Length(fftSize))

        let hzPerBin = sampleRate / Float(fftSize)
        let maxFrequency = min(Self.spectrumMaxFrequency, sampleRate / 2)
        let ratio = pow(maxFrequency / Self.spectrumMinFrequency, 1 / Float(bars))
        spectrumRanges = (0..<bars).map { i in
            let lower = Self.spectrumMinFrequency * pow(ratio, Float(i))
            let upper = Self.spectrumMinFrequency * pow(ratio, Float(i + 1))
            let start = max(1, min(Int(lower / hzPerBin), halfSize - 1))
            let end = max(start + 1, min(Int(upper / hzPerBin), halfSize))
            return start..<end
        }
        return setup
    }

    private func processSpectrumData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let bars = spectrumBarCount
        guard frameCount > 0, bars > 0 else { return }

        // Use power-of-2 size for FFT
        let log2n = vDSP_Length(log2(Float(frameCount)))
        let fftSize = 1 << Int(log2n)
        let halfSize = fftSize / 2
        // The tap doesn't guarantee buffer sizes; with halfSize below the
        // bar count the bin ranges would collapse.
        guard halfSize >= bars,
              let fftSetup = prepareSpectrumFFT(fftSize: fftSize, sampleRate: Float(buffer.format.sampleRate), bars: bars)
        else { return }

        vDSP_vmul(channelData, 1, spectrumWindow, 1, &spectrumWindowed, 1, vDSP_Length(fftSize))

        var spectrum = [Float](repeating: 0, count: bars)
        spectrumReal.withUnsafeMutableBufferPointer { realBuf in
            spectrumImag.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                spectrumWindowed.withUnsafeBytes { rawBuf in
                    let complexPtr = rawBuf.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &spectrumPower, 1, vDSP_Length(halfSize))
            }
        }

        // Sum power over each bar's log-spaced bin range, then normalize by
        // the window sum and compress so quiet bands still register.
        spectrumPower.withUnsafeBufferPointer { power in
            for (i, range) in spectrumRanges.enumerated() {
                var bandPower: Float = 0
                vDSP_sve(power.baseAddress! + range.lowerBound, 1, &bandPower, vDSP_Length(range.count))
                let amplitude = sqrt(bandPower) / spectrumNormalization
                spectrum[i] = min(1, pow(amplitude, Self.spectrumCompression) * Self.spectrumGain)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.spectrumData = spectrum
        }
    }

    deinit {
        if let setup = spectrumFFTSetup { vDSP_destroy_fftsetup(setup) }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
}
