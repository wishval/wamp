#!/usr/bin/env swift
//
// generate-sample.swift
//
// One-off generator for WampTests/Fixtures/sample.m4a. This script is NOT
// compiled into the WampTests target; it lives in the repo as documentation
// of how the fixture was produced. Re-run only if you need to regenerate the
// fixture.
//
// Usage:
//   swift WampTests/Fixtures/generate-sample.swift
//
// Output: WampTests/Fixtures/sample.m4a — ~0.5s stereo 44.1kHz AAC silence
// tagged with title/artist/album/genre. Tags are written via the iTunes
// metadata keyspace because AVAssetWriter ignores `.common` keyspace for
// m4a; AVFoundation exposes iTunes keys as `commonKey` automatically when
// reading, which is exactly how Wamp's Track.fromURL consumes them.
//

import Foundation
import AVFoundation

let fixtureTitle = "Wamp Fixture Title"
let fixtureArtist = "Wamp Fixture Artist"
let fixtureAlbum = "Wamp Fixture Album"
let fixtureGenre = "Electronic"

let scriptURL = URL(fileURLWithPath: #filePath)
let outputURL = scriptURL.deletingLastPathComponent().appendingPathComponent("sample.m4a")

// Remove any prior copy so AVAssetWriter can write fresh.
try? FileManager.default.removeItem(at: outputURL)

let sampleRate: Double = 44100
let channels: AVAudioChannelCount = 2
let durationSeconds: Double = 0.5
let totalFrames = AVAudioFrameCount(sampleRate * durationSeconds)

// ---- AVAssetWriter setup --------------------------------------------------

let writer: AVAssetWriter
do {
    writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
} catch {
    FileHandle.standardError.write("AVAssetWriter init failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

// Metadata — title/artist/album via iTunes keyspace, which AVFoundation
// surfaces under commonKey when reading. Genre via iTunes keyspace alone
// does NOT map to commonKeyType reliably, so we also attach a QuickTime
// userdata ©gen item to force commonKeyType to appear.
func iTunesItem(key: String, value: String) -> AVMutableMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = .iTunes
    item.key = key as NSString
    item.value = value as NSString
    item.locale = Locale(identifier: "en_US")
    return item
}

func identifiedItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMutableMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value as NSString
    item.locale = Locale(identifier: "en_US")
    return item
}

// Title/artist/album via iTunes keys (AVFoundation surfaces these under
// commonKey automatically). Genre goes through the identifier form against
// `commonIdentifierType` — the iTunes user-genre key alone does not map to
// commonKeyType when read back, whereas the identifier form does.
writer.metadata = [
    iTunesItem(key: AVMetadataKey.iTunesMetadataKeySongName.rawValue, value: fixtureTitle),
    iTunesItem(key: AVMetadataKey.iTunesMetadataKeyArtist.rawValue, value: fixtureArtist),
    iTunesItem(key: AVMetadataKey.iTunesMetadataKeyAlbum.rawValue, value: fixtureAlbum),
    identifiedItem(.commonIdentifierType, fixtureGenre),
]

// Audio input settings — AAC LC stereo 44.1 kHz.
let outputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: channels,
    AVEncoderBitRateKey: 64000,
]

let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
input.expectsMediaDataInRealTime = false
guard writer.canAdd(input) else {
    FileHandle.standardError.write("Writer cannot add audio input\n".data(using: .utf8)!)
    exit(1)
}
writer.add(input)

guard writer.startWriting() else {
    FileHandle.standardError.write("startWriting failed: \(String(describing: writer.error))\n".data(using: .utf8)!)
    exit(1)
}
writer.startSession(atSourceTime: .zero)

// ---- Build a silent PCM buffer and feed it in -----------------------------

// Use non-interleaved Float32 PCM matching what AAC encoder expects.
guard let pcmFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: sampleRate,
    channels: channels,
    interleaved: false
) else {
    FileHandle.standardError.write("Failed to build PCM format\n".data(using: .utf8)!)
    exit(1)
}

guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: totalFrames) else {
    FileHandle.standardError.write("Failed to build PCM buffer\n".data(using: .utf8)!)
    exit(1)
}
pcmBuffer.frameLength = totalFrames
// PCMBuffer memory is already zero-initialized — that is our silence.

// Convert AVAudioPCMBuffer → CMSampleBuffer.
func makeSampleBuffer(from pcm: AVAudioPCMBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
    let asbd = pcm.format.streamDescription
    var formatDescription: CMAudioFormatDescription?
    let status = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )
    guard status == noErr, let formatDescription else { return nil }

    var sampleBuffer: CMSampleBuffer?
    let createStatus = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: nil,
        dataReady: false,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDescription,
        sampleCount: CMItemCount(pcm.frameLength),
        sampleTimingEntryCount: 1,
        sampleTimingArray: [CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(pcm.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )],
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard createStatus == noErr, let sampleBuffer else { return nil }

    // Attach the AVAudioBufferList data to the CMSampleBuffer.
    let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
        sampleBuffer,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0,
        bufferList: pcm.audioBufferList
    )
    guard setStatus == noErr else { return nil }
    return sampleBuffer
}

guard let sampleBuffer = makeSampleBuffer(from: pcmBuffer, presentationTime: .zero) else {
    FileHandle.standardError.write("Failed to build sample buffer\n".data(using: .utf8)!)
    exit(1)
}

// Drain-then-append. For a tiny buffer this loop normally fires once.
let semaphore = DispatchSemaphore(value: 0)
let queue = DispatchQueue(label: "fixture.writer")
input.requestMediaDataWhenReady(on: queue) {
    if input.isReadyForMoreMediaData {
        if !input.append(sampleBuffer) {
            FileHandle.standardError.write("append failed: \(String(describing: writer.error))\n".data(using: .utf8)!)
        }
        input.markAsFinished()
        semaphore.signal()
    }
}
semaphore.wait()

let finishSem = DispatchSemaphore(value: 0)
writer.finishWriting {
    finishSem.signal()
}
finishSem.wait()

if writer.status != .completed {
    FileHandle.standardError.write("writer.status = \(writer.status.rawValue), error = \(String(describing: writer.error))\n".data(using: .utf8)!)
    exit(1)
}

// ---- Verification ---------------------------------------------------------

let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
let size = attrs[.size] as? Int ?? -1
print("Wrote \(outputURL.path) (\(size) bytes)")

// Read back via AVURLAsset and check commonMetadata surfaces all four tags.
let sem = DispatchSemaphore(value: 0)
var verifyError: String?
Task {
    let asset = AVURLAsset(url: outputURL)
    do {
        let items = try await asset.load(.commonMetadata)
        print("commonMetadata count: \(items.count)")
        var seen: [String: String] = [:]
        for item in items {
            guard let key = item.commonKey else { continue }
            if let v = try await item.load(.stringValue) {
                seen[key.rawValue] = v
                print("  \(key.rawValue) = \(v)")
            }
        }
        let needed = ["title", "artist", "albumName", "type"]
        for k in needed where seen[k] == nil {
            verifyError = "missing commonKey: \(k)"
            break
        }
    } catch {
        verifyError = "load failed: \(error)"
    }
    sem.signal()
}
sem.wait()
if let verifyError {
    FileHandle.standardError.write("VERIFICATION FAILED: \(verifyError)\n".data(using: .utf8)!)
    exit(2)
}
print("Verification OK — all four commonKey tags present.")
