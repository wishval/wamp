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
