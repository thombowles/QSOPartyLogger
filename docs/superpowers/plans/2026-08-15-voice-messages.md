# Voice Messages (Mac-side recordings) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record, edit and save eight phone messages per party on the Mac, and play them to the radio — through a sound card with CAT PTT on the Elecraft family, over DAX on a Flex — with the radio's own memories kept as the option.

**Architecture:** A pure `Core/Voice` model (clips, sets, on-disk library, DSP on `VoiceAudio`); a `Hardware/Voice` layer with two driver protocols (`TransmitControlCapable`, `AudioStreamTransmitCapable`), a sound-card player whose keying sequence is a testable state machine, a recorder, file IO and resampling; `EntryFlow` resolves `.recording(...)` transmissions from a per-party set; `RadioController` dispatches to whichever path the connected driver offers. Three behaviour commits: core+UI with no radio conforming, then Elecraft, then Flex.

**Tech Stack:** Swift 6, SwiftUI, AVFAudio (`AVAudioEngine`, `AVAudioFile`, `AVAudioConverter`), CoreAudio device enumeration, BSD UDP socket, XCTest. Build with `xcodegen generate` + `xcodebuild`.

**Spec:** [`docs/superpowers/specs/2026-08-15-voice-messages-design.md`](../specs/2026-08-15-voice-messages-design.md). **Research:** [`docs/research/voice_transports.md`](../../research/voice_transports.md).

**Conventions that apply to every task:**
- Run the full suite with `xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -quiet -resultBundlePath build-logs/<name>.xcresult > build-logs/<name>.log 2>&1` and read the summary with `xcrun xcresulttool get test-results summary --path build-logs/<name>.xcresult`. Never `tail` a log to decide pass/fail — read the summary's `result`/`failedTests`.
- After adding a new source file run `xcodegen generate` (sources are directory globs; the pbxproj is generated but tracked — commit it with the files).
- A single test class: `xcodebuild test … -only-testing:QSOPartyLoggerTests/<ClassName>`.
- Regression tests are proved **red first**.
- Article 10: no manufacturer, model, "DAX", port number or memory layout in any string an operator can see, and none in `Sources/App` or `Sources/UI` code.

---

## Commit A — the recordings path, no radio conforming yet

### Task 1: `VoiceAudio` — the in-memory clip and its DSP

**Files:**
- Create: `Sources/Core/Voice/VoiceAudio.swift`
- Test: `Tests/Core/VoiceAudioTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class VoiceAudioTests: XCTestCase {

    /// 1 kHz, 0.5 s at 48 kHz, peak 0.5.
    private func tone(seconds: Double = 0.5, rate: Double = 48_000, peak: Float = 0.5) -> VoiceAudio {
        let n = Int(seconds * rate)
        return VoiceAudio(sampleRate: rate, samples: (0..<n).map {
            peak * sinf(2 * .pi * 1000 * Float($0) / Float(rate))
        })
    }

    func testDurationAndEmptiness() {
        XCTAssertEqual(tone().duration, 0.5, accuracy: 1e-9)
        XCTAssertFalse(tone().isEmpty)
        XCTAssertTrue(VoiceAudio(sampleRate: 48_000, samples: []).isEmpty)
    }

    func testTrimmedKeepsTheWindowAndClamps() {
        let a = tone(seconds: 1)
        let t = a.trimmed(from: 0.25, to: 0.75)
        XCTAssertEqual(t.samples.count, 24_000)
        XCTAssertEqual(t.samples.first, a.samples[12_000])
        // Out-of-range and inverted windows clamp rather than trap.
        XCTAssertEqual(a.trimmed(from: -1, to: 5).samples.count, a.samples.count)
        XCTAssertTrue(a.trimmed(from: 0.8, to: 0.2).isEmpty)
    }

    func testGainInDecibels() {
        let a = VoiceAudio(sampleRate: 48_000, samples: [0.5, -0.5])
        XCTAssertEqual(a.applyingGain(dB: 6.0206).samples[0], 1.0, accuracy: 1e-4)
        XCTAssertEqual(a.applyingGain(dB: -6.0206).samples[1], -0.25, accuracy: 1e-4)
        XCTAssertEqual(a.applyingGain(dB: 0), a)
        XCTAssertEqual(VoiceAudio.decibels(1), 0, accuracy: 1e-6)
        XCTAssertEqual(VoiceAudio.decibels(0), -120)  // floored, never -inf
        XCTAssertEqual(VoiceAudio.linear(dB: -20), 0.1, accuracy: 1e-6)
    }

    func testPeakAndRMS() {
        let a = VoiceAudio(sampleRate: 48_000, samples: [0.5, -0.8, 0.1])
        XCTAssertEqual(a.peak, 0.8)
        XCTAssertEqual(a.rms, sqrtf((0.25 + 0.64 + 0.01) / 3), accuracy: 1e-6)
        XCTAssertEqual(VoiceAudio(sampleRate: 48_000, samples: []).peak, 0)
    }

    /// Silence, then 0.3 s of tone starting at 0.5 s, then silence: the voiced
    /// range is the tone, padded by 120 ms on each side, clamped to the clip.
    func testVoicedRangeFindsTheSpeechAndPads() {
        let rate = 48_000.0
        var samples = [Float](repeating: 0, count: Int(0.5 * rate))
        samples += tone(seconds: 0.3).samples
        samples += [Float](repeating: 0, count: Int(0.5 * rate))
        let a = VoiceAudio(sampleRate: rate, samples: samples)
        let r = a.voicedRange(thresholdDB: -40, pad: 0.12)!
        XCTAssertEqual(r.lowerBound, 0.5 - 0.12, accuracy: 0.002)
        XCTAssertEqual(r.upperBound, 0.8 + 0.12, accuracy: 0.002)
    }

    func testVoicedRangeClampsPadToTheClipAndIsNilForSilence() {
        let a = tone(seconds: 0.2)                        // voice from the very start
        let r = a.voicedRange(thresholdDB: -40, pad: 0.12)!
        XCTAssertEqual(r.lowerBound, 0)
        XCTAssertEqual(r.upperBound, 0.2, accuracy: 1e-6)
        XCTAssertNil(VoiceAudio(sampleRate: 48_000, samples: [Float](repeating: 0, count: 100))
            .voicedRange(thresholdDB: -40, pad: 0.12))
    }

    func testNormalizationGainBringsPeakToTarget() {
        let a = tone(peak: 0.25)
        let g = a.normalizationGainDB(targetDB: -1)
        XCTAssertEqual(a.applyingGain(dB: g).peak, VoiceAudio.linear(dB: -1), accuracy: 1e-3)
        XCTAssertEqual(VoiceAudio(sampleRate: 48_000, samples: [0, 0]).normalizationGainDB(targetDB: -1), 0)
    }

    func testWaveformBinsArePeaksAndCountIsExact() {
        let a = VoiceAudio(sampleRate: 4, samples: [0.1, -0.9, 0.2, 0.3, 0.0, 0.5, 0.4, 0.1])
        XCTAssertEqual(a.waveform(bins: 4), [0.9, 0.3, 0.5, 0.4])
        XCTAssertEqual(a.waveform(bins: 3).count, 3)
        XCTAssertEqual(VoiceAudio(sampleRate: 4, samples: []).waveform(bins: 3), [0, 0, 0])
    }

    func testSilenceAndScaled() {
        let s = VoiceAudio.silence(seconds: 0.1, sampleRate: 24_000)
        XCTAssertEqual(s.samples.count, 2_400)
        XCTAssertTrue(s.samples.allSatisfy { $0 == 0 })
        XCTAssertEqual(VoiceAudio(sampleRate: 1, samples: [0.5]).scaled(by: 0.5).samples, [0.25])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/VoiceAudioTests -quiet 2>&1 | grep -E "error:|BUILD|Executed" | head`
Expected: compile error — `VoiceAudio` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// A mono clip in memory: the form every voice path works on. Recordings are
/// rendered into one of these (file → trim → gain) once, when the party's set
/// loads, so an F-key never waits on disk.
struct VoiceAudio: Equatable, Sendable {
    var sampleRate: Double
    /// Mono, nominally −1…1. Never clipped here — the transports clip at the wire.
    var samples: [Float]

    init(sampleRate: Double, samples: [Float]) {
        self.sampleRate = sampleRate
        self.samples = samples
    }

    var duration: TimeInterval { Double(samples.count) / sampleRate }
    var isEmpty: Bool { samples.isEmpty }

    static func silence(seconds: TimeInterval, sampleRate: Double) -> VoiceAudio {
        VoiceAudio(sampleRate: sampleRate,
                   samples: [Float](repeating: 0, count: max(0, Int((seconds * sampleRate).rounded()))))
    }

    /// The window `start…end` in seconds, clamped to the clip. An inverted or
    /// empty window yields an empty clip rather than trapping.
    func trimmed(from start: TimeInterval, to end: TimeInterval) -> VoiceAudio {
        let lo = max(0, min(samples.count, Int((start * sampleRate).rounded())))
        let hi = max(0, min(samples.count, Int((end * sampleRate).rounded())))
        guard hi > lo else { return VoiceAudio(sampleRate: sampleRate, samples: []) }
        return VoiceAudio(sampleRate: sampleRate, samples: Array(samples[lo..<hi]))
    }

    func scaled(by linear: Float) -> VoiceAudio {
        guard linear != 1 else { return self }
        return VoiceAudio(sampleRate: sampleRate, samples: samples.map { $0 * linear })
    }

    func applyingGain(dB: Float) -> VoiceAudio {
        dB == 0 ? self : scaled(by: Self.linear(dB: dB))
    }

    var peak: Float { samples.reduce(0) { max($0, abs($1)) } }

    var rms: Float {
        guard !samples.isEmpty else { return 0 }
        return sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    /// 20·log10, floored at −120 so silence never reads −∞.
    static func decibels(_ linear: Float) -> Float {
        linear <= 0 ? -120 : max(-120, 20 * log10f(linear))
    }

    static func linear(dB: Float) -> Float { powf(10, dB / 20) }

    /// First and last sample louder than `thresholdDB` (relative to full scale),
    /// widened by `pad` seconds each side and clamped to the clip. Nil when
    /// nothing crosses the threshold — a silent recording.
    func voicedRange(thresholdDB: Float = -40, pad: TimeInterval = 0.12) -> ClosedRange<TimeInterval>? {
        let threshold = Self.linear(dB: thresholdDB)
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
              let last = samples.lastIndex(where: { abs($0) >= threshold }) else { return nil }
        let start = max(0, Double(first) / sampleRate - pad)
        let end = min(duration, Double(last + 1) / sampleRate + pad)
        return start...end
    }

    /// The gain, in dB, that puts the peak at `targetDB`. 0 for a silent clip —
    /// there is nothing to normalize and infinite gain would be the answer.
    func normalizationGainDB(targetDB: Float = -1) -> Float {
        let p = peak
        guard p > 0 else { return 0 }
        return targetDB - Self.decibels(p)
    }

    /// `bins` peak values across the clip, for drawing. Always exactly `bins`
    /// long; an empty clip draws flat.
    func waveform(bins: Int) -> [Float] {
        guard bins > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: bins) }
        return (0..<bins).map { bin in
            let lo = bin * samples.count / bins
            let hi = max(lo + 1, (bin + 1) * samples.count / bins)
            return samples[lo..<min(hi, samples.count)].reduce(0) { max($0, abs($1)) }
        }
    }
}
```

- [ ] **Step 4: `xcodegen generate`, run the class — expect all PASS.**
- [ ] **Step 5: Commit** — `git add Sources/Core/Voice/VoiceAudio.swift Tests/Core/VoiceAudioTests.swift QSOPartyLogger.xcodeproj && git commit -m "voice: VoiceAudio — the in-memory clip and its DSP"`

### Task 2: `VoiceClip`, `VoiceMessageSet`, `VoiceLibrary` — the model on disk

**Files:**
- Create: `Sources/Core/Voice/VoiceClip.swift`, `Sources/Core/Voice/VoiceLibrary.swift`, `Sources/Core/Voice/PhoneMessageSource.swift`
- Test: `Tests/Core/VoiceLibraryTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class VoiceLibraryTests: XCTestCase {
    private var folder: URL!
    private var library: VoiceLibrary!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceLibraryTests-\(UUID().uuidString)", isDirectory: true)
        library = VoiceLibrary(folder: folder)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func clip(_ n: Int, duration: TimeInterval = 2) -> VoiceClip {
        VoiceClip(fileName: VoiceLibrary.fileName(memory: n), duration: duration,
                  trimStart: 0, trimEnd: duration, gainDB: 0, recordedAt: Date(timeIntervalSince1970: 0))
    }
    private func writeFakeWAV(partyID: String, memory: Int) throws {
        let url = library.fileURL(partyID: partyID, fileName: VoiceLibrary.fileName(memory: memory))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
    }

    func testMissingPartyLoadsAnEmptySet() throws {
        let set = try library.load(partyID: "txqp")
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.version, VoiceMessageSet.currentVersion)
    }

    func testSaveThenLoadRoundTripsAndKeysAreMemoryNumbers() throws {
        var set = VoiceMessageSet()
        set[1] = clip(1)
        set[5] = clip(5, duration: 3.5)
        try library.save(set, partyID: "txqp")
        let back = try library.load(partyID: "txqp")
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.recordedMemories, [1, 5])
        // Human-readable sidecar: memory numbers are JSON object keys, not an array.
        let json = try String(contentsOf: library.sidecarURL(partyID: "txqp"), encoding: .utf8)
        XCTAssertTrue(json.contains("\"5\""), json)
    }

    func testCorruptSidecarThrowsRatherThanReplacing() throws {
        try FileManager.default.createDirectory(at: library.setFolder(partyID: "alqp"), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: library.sidecarURL(partyID: "alqp"))
        XCTAssertThrowsError(try library.load(partyID: "alqp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.sidecarURL(partyID: "alqp").path),
                      "the operator's file is never deleted on a read failure")
    }

    func testRemoveDeletesTheFileAndTheEntry() throws {
        var set = VoiceMessageSet(); set[2] = clip(2)
        try library.save(set, partyID: "txqp")
        try writeFakeWAV(partyID: "txqp", memory: 2)
        try library.remove(memory: 2, partyID: "txqp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.fileURL(partyID: "txqp", fileName: "M2.wav").path))
        XCTAssertNil(try library.load(partyID: "txqp")[2])
        // Removing what is not there is not an error.
        XCTAssertNoThrow(try library.remove(memory: 7, partyID: "txqp"))
    }

    func testCopyMissingFillsOnlyTheGaps() throws {
        var src = VoiceMessageSet(); src[1] = clip(1); src[3] = clip(3); src[4] = clip(4)
        try library.save(src, partyID: "alqp")
        for m in [1, 3, 4] { try writeFakeWAV(partyID: "alqp", memory: m) }
        var dst = VoiceMessageSet(); dst[3] = clip(3, duration: 9)   // already recorded here
        try library.save(dst, partyID: "txqp")

        let copied = try library.copyMissing(from: "alqp", to: "txqp")
        XCTAssertEqual(copied, 2)
        let after = try library.load(partyID: "txqp")
        XCTAssertEqual(after.recordedMemories, [1, 3, 4])
        XCTAssertEqual(after[3]?.duration, 9, "an existing recording is never overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(partyID: "txqp", fileName: "M1.wav").path))
    }

    func testPartiesWithRecordingsIsSortedAndSkipsEmptySets() throws {
        var a = VoiceMessageSet(); a[1] = clip(1)
        try library.save(a, partyID: "txqp")
        try library.save(a, partyID: "alqp")
        try library.save(VoiceMessageSet(), partyID: "empty")
        XCTAssertEqual(library.partiesWithRecordings(), ["alqp", "txqp"])
    }

    func testPartyIDsAreValidatedBeforeTouchingDisk() {
        XCTAssertTrue(VoiceLibrary.isValidPartyID("nyqp"))
        XCTAssertTrue(VoiceLibrary.isValidPartyID("7qp_2026-x"))
        XCTAssertFalse(VoiceLibrary.isValidPartyID(""))
        XCTAssertFalse(VoiceLibrary.isValidPartyID("../etc"))
        XCTAssertFalse(VoiceLibrary.isValidPartyID("a b"))
        XCTAssertThrowsError(try library.load(partyID: "../x"))
        XCTAssertThrowsError(try library.save(VoiceMessageSet(), partyID: ""))
    }

    func testClipTrimmedDuration() {
        var c = clip(1, duration: 4)
        c.trimStart = 0.5; c.trimEnd = 3
        XCTAssertEqual(c.trimmedDuration, 2.5, accuracy: 1e-9)
        c.trimEnd = 0.2
        XCTAssertEqual(c.trimmedDuration, 0)
    }

    func testDefaultsOfTheSettingEnums() {
        XCTAssertEqual(PhoneMessageSource(rawValue: "recordings"), .recordings)
        XCTAssertEqual(PhoneMessageSource(rawValue: "radioMemories"), .radioMemories)
        XCTAssertEqual(VoicePTTMode(rawValue: "radioCommand"), .radioCommand)
        XCTAssertEqual(VoicePTTMode(rawValue: "vox"), .vox)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**
- [ ] **Step 3: Implement**

`Sources/Core/Voice/PhoneMessageSource.swift`:
```swift
import Foundation

/// Where phone keys get their audio, on a radio that offers both. Raw values are
/// UserDefaults storage, never display (Article 10 practice).
enum PhoneMessageSource: String, Codable, CaseIterable, Sendable {
    /// Recordings on this Mac, played to the radio — the default.
    case recordings
    /// The radio's own recorder.
    case radioMemories
}

/// How the sound-card path keys the radio. Not used by a radio that takes the
/// audio over its own link — that driver keys itself.
enum VoicePTTMode: String, Codable, CaseIterable, Sendable {
    /// `TX;`/`RX;` (or the maker's equivalent) over CAT — the default.
    case radioCommand
    /// Nothing: the radio's VOX keys on the audio.
    case vox
}
```

`Sources/Core/Voice/VoiceClip.swift`:
```swift
import Foundation

/// One recording as the sidecar describes it. Non-destructive: the file is
/// what was recorded or imported; trim and gain apply at playback.
struct VoiceClip: Codable, Equatable, Sendable {
    /// Always relative to the set's folder — "M3.wav".
    var fileName: String
    /// Of the whole file, so the row can show it without opening it.
    var duration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    /// 0 = as recorded. Normalize writes the gain that puts the peak at −1 dBFS.
    var gainDB: Float
    var recordedAt: Date

    var trimmedDuration: TimeInterval { max(0, trimEnd - trimStart) }
}

/// A party's memories, 1...`MessageSets.voiceMemorySlots`. A missing key is an
/// empty memory. Encoded with the memory number as the JSON object key
/// ("1": {…}) so the sidecar reads like the editor.
struct VoiceMessageSet: Equatable, Sendable {
    static let currentVersion = 1
    var version = VoiceMessageSet.currentVersion
    var clips: [Int: VoiceClip] = [:]

    subscript(memory: Int) -> VoiceClip? {
        get { clips[memory] }
        set { clips[memory] = newValue }
    }
    var recordedMemories: Set<Int> { Set(clips.keys) }
    var isEmpty: Bool { clips.isEmpty }
}

extension VoiceMessageSet: Codable {
    private enum CodingKeys: String, CodingKey { case version, clips }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        let keyed = try c.decodeIfPresent([String: VoiceClip].self, forKey: .clips) ?? [:]
        clips = Dictionary(uniqueKeysWithValues: keyed.compactMap { key, clip in
            Int(key).map { ($0, clip) }
        })
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(Dictionary(uniqueKeysWithValues: clips.map { (String($0.key), $0.value) }), forKey: .clips)
    }
}
```

`Sources/Core/Voice/VoiceLibrary.swift`:
```swift
import Foundation

/// The recordings on disk: one folder per party holding `voice.json` and the
/// WAVs it names, in the app's Application Support folder — a temp dir in
/// tests. Kept per party rather than per log because a party's messages are
/// the same next year, and because eight WAVs do not belong in a JSON log that
/// autosaves on every contact.
struct VoiceLibrary: Sendable {
    let folder: URL

    /// `~/Library/Application Support/QSOPartyLogger/Voice`
    /// (container-relative when sandboxed), beside the user parties folder.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Voice", isDirectory: true)
    }

    static let sidecarName = "voice.json"

    enum LibraryError: Error, LocalizedError, Equatable {
        case invalidPartyID(String)
        var errorDescription: String? {
            switch self {
            case .invalidPartyID(let id): "'\(id)' is not a party id this app can keep recordings for."
            }
        }
    }

    /// Party ids are file-system path components. Only what the catalogue's
    /// own ids use.
    static func isValidPartyID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

    static func fileName(memory: Int) -> String { "M\(memory).wav" }

    func setFolder(partyID: String) -> URL {
        folder.appendingPathComponent(partyID, isDirectory: true)
    }
    func sidecarURL(partyID: String) -> URL {
        setFolder(partyID: partyID).appendingPathComponent(Self.sidecarName)
    }
    func fileURL(partyID: String, fileName: String) -> URL {
        setFolder(partyID: partyID).appendingPathComponent(fileName)
    }

    private func validated(_ partyID: String) throws {
        guard Self.isValidPartyID(partyID) else { throw LibraryError.invalidPartyID(partyID) }
    }

    /// Empty when the party has no folder or no sidecar. A sidecar that exists
    /// but cannot be read throws — the WAVs beside it are the operator's work,
    /// and are never replaced by an empty set on a read failure.
    func load(partyID: String) throws -> VoiceMessageSet {
        try validated(partyID)
        let url = sidecarURL(partyID: partyID)
        guard FileManager.default.fileExists(atPath: url.path) else { return VoiceMessageSet() }
        return try JSONDecoder.voice.decode(VoiceMessageSet.self, from: Data(contentsOf: url))
    }

    func save(_ set: VoiceMessageSet, partyID: String) throws {
        try validated(partyID)
        try FileManager.default.createDirectory(at: setFolder(partyID: partyID), withIntermediateDirectories: true)
        try JSONEncoder.voice.encode(set).write(to: sidecarURL(partyID: partyID), options: .atomic)
    }

    /// Deletes the memory's file and its entry. A memory that is not there is
    /// already removed.
    func remove(memory: Int, partyID: String) throws {
        var set = try load(partyID: partyID)
        guard let clip = set[memory] else { return }
        let url = fileURL(partyID: partyID, fileName: clip.fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        set[memory] = nil
        try save(set, partyID: partyID)
    }

    /// Copies every memory `to` lacks from `from` — file and entry — and
    /// returns how many. Existing recordings are never overwritten.
    func copyMissing(from source: String, to destination: String) throws -> Int {
        let src = try load(partyID: source)
        var dst = try load(partyID: destination)
        var copied = 0
        for (memory, clip) in src.clips.sorted(by: { $0.key < $1.key }) where dst[memory] == nil {
            let srcURL = fileURL(partyID: source, fileName: clip.fileName)
            guard FileManager.default.fileExists(atPath: srcURL.path) else { continue }
            let dstURL = fileURL(partyID: destination, fileName: Self.fileName(memory: memory))
            try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dstURL.path) { try FileManager.default.removeItem(at: dstURL) }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            var copy = clip
            copy.fileName = Self.fileName(memory: memory)
            dst[memory] = copy
            copied += 1
        }
        if copied > 0 { try save(dst, partyID: destination) }
        return copied
    }

    /// Party ids with at least one recording, sorted — the "Copy from…" menu.
    func partiesWithRecordings() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { Self.isValidPartyID($0) }
            .filter { !((try? load(partyID: $0))?.isEmpty ?? true) }
            .sorted()
    }
}

extension JSONEncoder {
    static var voice: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
extension JSONDecoder {
    static var voice: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
```

- [ ] **Step 4: `xcodegen generate`; run `VoiceLibraryTests` — PASS.**
- [ ] **Step 5: Commit** — `git commit -m "voice: VoiceClip, VoiceMessageSet, VoiceLibrary — the per-party set on disk"`

### Task 3: The transport protocols and the player interface

**Files:**
- Create: `Sources/Hardware/Voice/VoiceTransports.swift`

No test of its own (protocols); it compiles with Task 4.

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// A radio the app can key over its control link for the duration of a message
/// it plays through a sound card. `TX;`/`RX;` on the Elecraft family. Nothing
/// about the audio: that goes out a CoreAudio device the operator picked.
protocol TransmitControlCapable: RadioDriver {
    func setTransmit(_ on: Bool)
}

/// What a voice transport reports about one play. Exactly one terminal event
/// (`finished`, `stopped` or `failed`) per play.
enum TransmitAudioEvent: Equatable, Sendable {
    /// Audio has begun to go out.
    case started
    /// Played to the end; the radio is unkeyed.
    case finished
    /// Aborted; the radio is unkeyed.
    case stopped
    /// Never keyed, or unkeyed early. The text is shown to the operator.
    case failed(String)
}

/// A radio that takes transmit audio from the app over its own connection —
/// no sound card, no PTT line. The driver keys, streams, and unkeys.
protocol AudioStreamTransmitCapable: RadioDriver {
    /// The rate the radio wants samples at. The caller resamples to it.
    var transmitSampleRate: Double { get }
    /// Key the radio, put `audio` on the air, unkey. One at a time: a second
    /// call while one is in flight stops the first.
    func transmitAudio(_ audio: VoiceAudio)
    func stopTransmitAudio()
    var onTransmitAudioEvent: (@Sendable (TransmitAudioEvent) -> Void)? { get set }
}

/// The sound-card path: plays a clip to an output device and keys the radio
/// around it. A protocol so `RadioController` is tested against a fake.
protocol VoicePlaying: AnyObject {
    /// `deviceUID` nil = the system default output. `keyRadio`, when given, is
    /// called with `true` `leadMs` before the first sample and `false`
    /// `tailMs` after the last; nil means VOX — never key. `onEvent` fires
    /// `.started` when audio begins and one terminal event at the end.
    func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
              keyRadio: (@Sendable (Bool) -> Void)?, leadMs: Int, tailMs: Int,
              onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void)
    func stop()
}
```

- [ ] **Step 2: `xcodegen generate` and build** — `xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -quiet 2>&1 | grep -E "error:|warning: unused" ; echo done` — expect no errors.
- [ ] **Step 3: Commit** — `git commit -m "voice: transport protocols — TransmitControlCapable, AudioStreamTransmitCapable, VoicePlaying"`

### Task 4: `VoicePlayer` — the keying sequence over an `AudioOutput`

**Files:**
- Create: `Sources/Hardware/Voice/VoicePlayer.swift`
- Test: `Tests/Hardware/VoicePlayerSequenceTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The lead → play → tail → unkey sequence, and abort at every point, driven
/// through a fake output and a hand-cranked scheduler. No audio device.
final class VoicePlayerSequenceTests: XCTestCase {

    final class FakeOutput: AudioOutput, @unchecked Sendable {
        var started: [(VoiceAudio, String?, Float)] = []
        var stops = 0
        var failStart = false
        var completion: (@Sendable (Bool) -> Void)?
        func start(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
                   completion: @escaping @Sendable (Bool) -> Void) throws {
            if failStart { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no device"]) }
            started.append((audio, deviceUID, gain))
            self.completion = completion
        }
        func stop() { stops += 1 }
    }

    /// Captures scheduled blocks so the test decides when time passes.
    final class ManualScheduler: @unchecked Sendable {
        var pending: [(ms: Int, block: @Sendable () -> Void)] = []
        func schedule(_ ms: Int, _ block: @escaping @Sendable () -> Void) { pending.append((ms, block)) }
        func fireNext() { let p = pending.removeFirst(); p.block() }
    }

    private let clip = VoiceAudio(sampleRate: 48_000, samples: [0.1, 0.2])

    func testFullSequenceKeysLeadsPlaysTailsUnkeys() {
        let out = FakeOutput(); let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        var keys: [Bool] = []; var events: [TransmitAudioEvent] = []
        player.play(clip, deviceUID: "dev", gain: 0.6, keyRadio: { keys.append($0) },
                    leadMs: 120, tailMs: 100) { events.append($0) }

        XCTAssertEqual(keys, [true], "keyed at once")
        XCTAssertTrue(out.started.isEmpty, "no audio during the lead")
        XCTAssertEqual(clock.pending.first?.ms, 120)
        clock.fireNext()
        XCTAssertEqual(out.started.count, 1)
        XCTAssertEqual(out.started[0].1, "dev"); XCTAssertEqual(out.started[0].2, 0.6)
        XCTAssertEqual(events, [.started])
        out.completion?(true)                       // last sample left the device
        XCTAssertEqual(clock.pending.first?.ms, 100)
        XCTAssertEqual(keys, [true], "still keyed through the tail")
        clock.fireNext()
        XCTAssertEqual(keys, [true, false])
        XCTAssertEqual(events, [.started, .finished])
    }

    func testVOXNeverKeysAndHasNoLead() {
        let out = FakeOutput(); let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        var events: [TransmitAudioEvent] = []
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: nil, leadMs: 120, tailMs: 100) { events.append($0) }
        XCTAssertEqual(out.started.count, 1, "no lead without a radio to key")
        out.completion?(true)
        XCTAssertEqual(events, [.started, .finished], "no tail either")
    }

    func testStopDuringLeadUnkeysAndNeverPlays() {
        let out = FakeOutput(); let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        var keys: [Bool] = []; var events: [TransmitAudioEvent] = []
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: { keys.append($0) }, leadMs: 120, tailMs: 100) { events.append($0) }
        player.stop()
        XCTAssertEqual(keys, [true, false])
        XCTAssertEqual(events, [.stopped])
        clock.fireNext()                              // the stale lead timer fires
        XCTAssertTrue(out.started.isEmpty, "a cancelled lead must not start audio")
        XCTAssertEqual(events, [.stopped], "and reports nothing more")
    }

    func testStopMidClipUnkeysAtOnceAndSkipsTheTail() {
        let out = FakeOutput(); let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        var keys: [Bool] = []; var events: [TransmitAudioEvent] = []
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: { keys.append($0) }, leadMs: 0, tailMs: 100) { events.append($0) }
        clock.fireNext()
        XCTAssertEqual(events, [.started])
        player.stop()
        XCTAssertEqual(out.stops, 1)
        XCTAssertEqual(keys, [true, false])
        XCTAssertEqual(events, [.started, .stopped])
        out.completion?(false)                         // the output reports the interrupted end
        XCTAssertEqual(events, [.started, .stopped], "no second terminal event")
    }

    func testStartFailureUnkeysAndReportsTheReason() {
        let out = FakeOutput(); out.failStart = true
        let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        var keys: [Bool] = []; var events: [TransmitAudioEvent] = []
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: { keys.append($0) }, leadMs: 0, tailMs: 0) { events.append($0) }
        clock.fireNext()
        XCTAssertEqual(keys, [true, false])
        XCTAssertEqual(events, [.failed("no device")])
    }

    func testSecondPlayReplacesTheFirst() {
        let out = FakeOutput(); let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        var first: [TransmitAudioEvent] = []; var second: [TransmitAudioEvent] = []
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: nil, leadMs: 0, tailMs: 0) { first.append($0) }
        clock.fireNext()
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: nil, leadMs: 0, tailMs: 0) { second.append($0) }
        XCTAssertEqual(first, [.started, .stopped])
        XCTAssertEqual(out.stops, 1)
        clock.fireNext()
        XCTAssertEqual(second, [.started])
    }
}
```

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement**

```swift
import Foundation
import AVFAudio
import CoreAudio

/// The audio half of the sound-card player, behind a protocol so the keying
/// sequence is tested with a fake and the engine adapter stays thin.
protocol AudioOutput: AnyObject {
    /// Start playing to `deviceUID` (nil = system default). `completion` is
    /// called once: `true` when the last sample has left the device, `false`
    /// after `stop()`.
    func start(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
               completion: @escaping @Sendable (Bool) -> Void) throws
    func stop()
}

/// Lead → play → tail → unkey, with abort at every point. `keyRadio(false)`
/// always precedes the terminal event, so Esc is never waiting on a callback.
final class VoicePlayer: VoicePlaying, @unchecked Sendable {
    typealias Schedule = @Sendable (_ delayMs: Int, _ block: @escaping @Sendable () -> Void) -> Void

    private let output: any AudioOutput
    private let schedule: Schedule
    private let lock = NSLock()
    /// Incremented on every play and stop; a timer or completion that wakes up
    /// with a stale generation does nothing.
    private var generation = 0
    private var active: (keyRadio: (@Sendable (Bool) -> Void)?, onEvent: @Sendable (TransmitAudioEvent) -> Void)?

    init(output: any AudioOutput,
         schedule: @escaping Schedule = { ms, block in
             DispatchQueue.global(qos: .userInteractive)
                 .asyncAfter(deadline: .now() + .milliseconds(ms), execute: block)
         }) {
        self.output = output
        self.schedule = schedule
    }

    func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
              keyRadio: (@Sendable (Bool) -> Void)?, leadMs: Int, tailMs: Int,
              onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void) {
        stop()
        let gen: Int = lock.withLock {
            generation += 1
            active = (keyRadio, onEvent)
            return generation
        }
        keyRadio?(true)
        let begin: @Sendable () -> Void = { [weak self] in
            guard let self, self.isCurrent(gen) else { return }
            do {
                try self.output.start(audio, deviceUID: deviceUID, gain: gain) { [weak self] playedToEnd in
                    guard let self, playedToEnd, self.isCurrent(gen) else { return }
                    let end: @Sendable () -> Void = { [weak self] in
                        guard let self, let done = self.finish(gen) else { return }
                        done.keyRadio?(false)
                        done.onEvent(.finished)
                    }
                    if keyRadio != nil, tailMs > 0 { self.schedule(tailMs, end) } else { end() }
                }
                onEvent(.started)
            } catch {
                guard let done = self.finish(gen) else { return }
                done.keyRadio?(false)
                done.onEvent(.failed(error.localizedDescription))
            }
        }
        if keyRadio != nil, leadMs > 0 { schedule(leadMs, begin) } else { begin() }
    }

    func stop() {
        guard let done = finish(nil) else { return }
        output.stop()
        done.keyRadio?(false)
        done.onEvent(.stopped)
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.withLock { generation == gen && active != nil }
    }

    /// Takes the active play if `gen` is current (or any play, when nil),
    /// bumping the generation so nothing stale can fire afterwards.
    private func finish(_ gen: Int?) -> (keyRadio: (@Sendable (Bool) -> Void)?, onEvent: @Sendable (TransmitAudioEvent) -> Void)? {
        lock.withLock {
            guard let current = active, gen == nil || gen == generation else { return nil }
            active = nil
            generation += 1
            return current
        }
    }
}

/// `AVAudioEngine` → the chosen output device. Thin on purpose: everything
/// decidable is decided in `VoicePlayer`.
final class EngineAudioOutput: AudioOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    enum OutputError: Error, LocalizedError {
        case deviceNotFound(String), format
        var errorDescription: String? {
            switch self {
            case .deviceNotFound(let uid): "The audio device for the radio (\(uid)) is not connected."
            case .format: "Could not build an audio buffer for the device."
            }
        }
    }

    func start(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
               completion: @escaping @Sendable (Bool) -> Void) throws {
        stop()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        if let uid = deviceUID {
            guard let deviceID = AudioDevices.deviceID(uid: uid) else { throw OutputError.deviceNotFound(uid) }
            var id = deviceID
            let status = AudioUnitSetProperty(
                engine.outputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw OutputError.deviceNotFound(uid) }
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count))
        else { throw OutputError.format }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        for (i, s) in audio.samples.enumerated() { buffer.floatChannelData![0][i] = s * gain }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        lock.withLock { self.engine = engine; self.player = player }
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { type in
            completion(type == .dataPlayedBack)
        }
        player.play()
    }

    func stop() {
        let (e, p): (AVAudioEngine?, AVAudioPlayerNode?) = lock.withLock {
            defer { engine = nil; player = nil }
            return (engine, player)
        }
        p?.stop()
        e?.stop()
    }
}
```

`AudioDevices.deviceID(uid:)` is written in Task 5; add it in the same build.

- [ ] **Step 4: Run `VoicePlayerSequenceTests` — PASS.** (Note: `stop()` on the fake after `finish(nil)` still counts a stop for a play that had not started audio; the test for stop-during-lead does not assert `stops == 0`.)
- [ ] **Step 5: Commit** — `git commit -m "voice: VoicePlayer — lead, play, tail, unkey; abort at every point"`

### Task 5: `AudioDevices`, `AudioFileIO`, `AudioResampler`

**Files:**
- Create: `Sources/Hardware/Voice/AudioDevices.swift`, `Sources/Hardware/Voice/AudioFileIO.swift`, `Sources/Hardware/Voice/AudioResampler.swift`
- Test: `Tests/Hardware/AudioFileIOTests.swift`, `Tests/Hardware/AudioResamplerTests.swift`

- [ ] **Step 1: Failing tests**

```swift
// Tests/Hardware/AudioFileIOTests.swift
import XCTest
@testable import QSOPartyLogger

final class AudioFileIOTests: XCTestCase {
    private var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("AudioFileIOTests-\(UUID().uuidString).wav")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testWriteThenReadRoundTripsMonoAt48k() throws {
        let src = VoiceAudio(sampleRate: 48_000, samples: (0..<4800).map { sinf(Float($0) * 0.05) * 0.5 })
        try AudioFileIO.write(src, to: url)
        let back = try AudioFileIO.read(url)
        XCTAssertEqual(back.sampleRate, 48_000)
        XCTAssertEqual(back.samples.count, src.samples.count)
        for i in stride(from: 0, to: 4800, by: 97) {
            XCTAssertEqual(back.samples[i], src.samples[i], accuracy: 1 / 32_000, "16-bit PCM round trip")
        }
    }

    func testStereoImportFoldsToMonoAndKeepsItsOwnRate() throws {
        // Write a stereo 44.1 kHz file with AVAudioFile directly, L=0.4, R=0.0.
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 441)!
        buf.frameLength = 441
        for i in 0..<441 { buf.floatChannelData![0][i] = 0.4; buf.floatChannelData![1][i] = 0 }
        try file.write(from: buf)
        let back = try AudioFileIO.read(url)
        XCTAssertEqual(back.sampleRate, 44_100)
        XCTAssertEqual(back.samples.count, 441)
        XCTAssertEqual(back.samples[100], 0.2, accuracy: 1e-4, "L and R averaged")
    }

    func testDurationWithoutDecoding() throws {
        try AudioFileIO.write(VoiceAudio(sampleRate: 48_000, samples: [Float](repeating: 0, count: 96_000)), to: url)
        XCTAssertEqual(try AudioFileIO.duration(of: url), 2, accuracy: 1e-6)
    }
}
```

```swift
// Tests/Hardware/AudioResamplerTests.swift
import XCTest
@testable import QSOPartyLogger

final class AudioResamplerTests: XCTestCase {
    private func zeroCrossings(_ s: [Float]) -> Int {
        zip(s, s.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    func testHalvingTheRateHalvesTheCountAndKeepsTheTone() throws {
        let rate = 48_000.0
        let src = VoiceAudio(sampleRate: rate, samples: (0..<48_000).map { 0.5 * sinf(2 * .pi * 1000 * Float($0) / Float(rate)) })
        let out = try AudioResampler.resample(src, to: 24_000)
        XCTAssertEqual(out.sampleRate, 24_000)
        XCTAssertEqual(Double(out.samples.count), 24_000, accuracy: 64)
        // 1 kHz for 1 s ⇒ ~2000 zero crossings at either rate.
        XCTAssertEqual(Double(zeroCrossings(out.samples)), 2000, accuracy: 30)
        XCTAssertEqual(out.peak, 0.5, accuracy: 0.05)
    }

    func testSameRateIsIdentity() throws {
        let src = VoiceAudio(sampleRate: 24_000, samples: [0.1, 0.2, 0.3])
        XCTAssertEqual(try AudioResampler.resample(src, to: 24_000), src)
    }

    func testEmptyStaysEmpty() throws {
        XCTAssertTrue(try AudioResampler.resample(VoiceAudio(sampleRate: 48_000, samples: []), to: 24_000).isEmpty)
    }
}
```

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement**

`AudioDevices.swift`:
```swift
import Foundation
import CoreAudio

/// CoreAudio's device list, as the pickers need it: UID (stable across
/// launches) and name. UIDs are what the settings store; names are display.
struct AudioDevice: Identifiable, Equatable, Hashable, Sendable {
    let uid: String
    let name: String
    var id: String { uid }
}

enum AudioDevices {
    static func inputDevices() -> [AudioDevice] { devices(input: true) }
    static func outputDevices() -> [AudioDevice] { devices(input: false) }

    static func device(uid: String) -> AudioDevice? {
        (inputDevices() + outputDevices()).first { $0.uid == uid }
    }

    static func deviceID(uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { self.uid(of: $0) == uid }
    }

    // MARK: CoreAudio plumbing

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func devices(input: Bool) -> [AudioDevice] {
        allDeviceIDs().compactMap { id in
            guard channelCount(id, input: input) > 0, let uid = uid(of: id), let name = name(of: id) else { return nil }
            return AudioDevice(uid: uid, name: name)
        }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    private static func uid(of id: AudioDeviceID) -> String? { string(id, kAudioDevicePropertyDeviceUID) }
    private static func name(of id: AudioDeviceID) -> String? { string(id, kAudioObjectPropertyName) }

    private static func channelCount(_ id: AudioDeviceID, input: Bool) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
```

`AudioFileIO.swift`:
```swift
import Foundation
import AVFAudio

/// Reads any file `AVAudioFile` can (folded to mono, at its own rate) and
/// writes the app's own recordings as 48 kHz mono 16-bit PCM WAV.
enum AudioFileIO {
    static let recordingSampleRate = 48_000.0

    enum IOError: Error, LocalizedError {
        case unreadable, unwritable
        var errorDescription: String? {
            switch self {
            case .unreadable: "The audio file could not be read."
            case .unwritable: "The recording could not be written."
            }
        }
    }

    static func read(_ url: URL) throws -> VoiceAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1)) else { throw IOError.unreadable }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        guard let data = buffer.floatChannelData, channels > 0 else {
            return VoiceAudio(sampleRate: format.sampleRate, samples: [])
        }
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            for i in 0..<n { mono[i] += data[c][i] }
        }
        if channels > 1 { for i in 0..<n { mono[i] /= Float(channels) } }
        return VoiceAudio(sampleRate: format.sampleRate, samples: mono)
    }

    static func write(_ audio: VoiceAudio, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(audio.samples.count, 1)))
        else { throw IOError.unwritable }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        for (i, s) in audio.samples.enumerated() { buffer.floatChannelData![0][i] = max(-1, min(1, s)) }
        try file.write(from: buffer)
    }

    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
```

`AudioResampler.swift`:
```swift
import Foundation
import AVFAudio

/// `AVAudioConverter` between two mono float rates. Used once per clip when
/// the party's set loads (for a radio whose rate is not the recording's), never
/// on the F-key press.
enum AudioResampler {
    enum ResampleError: Error, LocalizedError {
        case converter
        var errorDescription: String? { "Could not convert the recording to the radio's sample rate." }
    }

    static func resample(_ audio: VoiceAudio, to rate: Double) throws -> VoiceAudio {
        guard audio.sampleRate != rate else { return audio }
        guard !audio.samples.isEmpty else { return VoiceAudio(sampleRate: rate, samples: []) }
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(audio.samples.count))
        else { throw ResampleError.converter }
        input.frameLength = AVAudioFrameCount(audio.samples.count)
        for (i, s) in audio.samples.enumerated() { input.floatChannelData![0][i] = s }

        let outFrames = AVAudioFrameCount((Double(audio.samples.count) * rate / audio.sampleRate).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else { throw ResampleError.converter }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        let n = Int(output.frameLength)
        return VoiceAudio(sampleRate: rate, samples: Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: n)))
    }
}
```

- [ ] **Step 4: `xcodegen generate`; run both classes plus `VoicePlayerSequenceTests` — PASS.**
- [ ] **Step 5: Commit** — `git commit -m "voice: AudioDevices, AudioFileIO, AudioResampler"`

### Task 6: `VoiceRecorder` — accumulator (pure) + engine adapter

**Files:**
- Create: `Sources/Hardware/Voice/VoiceRecorder.swift`
- Test: `Tests/Hardware/RecordingAccumulatorTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class RecordingAccumulatorTests: XCTestCase {
    func testAppendsAndReportsLevelAndElapsed() {
        var acc = RecordingAccumulator(sampleRate: 48_000, maxSeconds: 30)
        XCTAssertFalse(acc.append([0.1, -0.5, 0.2]))
        XCTAssertEqual(acc.lastPeak, 0.5)
        XCTAssertEqual(acc.elapsed, 3.0 / 48_000, accuracy: 1e-12)
        XCTAssertEqual(acc.audio.samples, [0.1, -0.5, 0.2])
    }

    func testCutsAtTheMaximumAndSaysSo() {
        var acc = RecordingAccumulator(sampleRate: 10, maxSeconds: 1)
        XCTAssertFalse(acc.append([Float](repeating: 0.1, count: 8)))
        XCTAssertTrue(acc.append([Float](repeating: 0.1, count: 8)), "crossing the cap reports full")
        XCTAssertEqual(acc.audio.samples.count, 10, "and keeps exactly the cap")
        XCTAssertTrue(acc.isFull)
    }
}
```

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement**

```swift
import Foundation
import AVFAudio
import CoreAudio

/// Collects tapped input buffers into one clip, caps the length, and keeps
/// the last buffer's peak for the meter. Pure, so it is tested without a
/// microphone.
struct RecordingAccumulator: Sendable {
    let sampleRate: Double
    let maxSamples: Int
    private(set) var samples: [Float] = []
    private(set) var lastPeak: Float = 0

    init(sampleRate: Double, maxSeconds: TimeInterval) {
        self.sampleRate = sampleRate
        self.maxSamples = Int(maxSeconds * sampleRate)
    }

    var isFull: Bool { samples.count >= maxSamples }
    var elapsed: TimeInterval { Double(samples.count) / sampleRate }
    var audio: VoiceAudio { VoiceAudio(sampleRate: sampleRate, samples: samples) }

    /// Appends up to the cap. Returns true when the cap has been reached.
    mutating func append(_ chunk: [Float]) -> Bool {
        lastPeak = chunk.reduce(0) { max($0, abs($1)) }
        let room = maxSamples - samples.count
        if room > 0 { samples.append(contentsOf: chunk.prefix(room)) }
        return isFull
    }
}

/// The microphone side, behind a protocol for `VoiceStore`'s tests.
protocol VoiceRecording: AnyObject {
    /// Start capturing from `deviceUID` (nil = system default input) at the
    /// recording rate. `onLevel` gets the latest peak (0…1) as buffers arrive.
    func start(deviceUID: String?, maxSeconds: TimeInterval,
               onLevel: @escaping @Sendable (Float, TimeInterval) -> Void,
               onFull: @escaping @Sendable () -> Void) throws
    /// Stops and returns what was captured, resampled to the recording rate.
    func stop() -> VoiceAudio?
}

final class EngineVoiceRecorder: VoiceRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var accumulator: RecordingAccumulator?
    private var inputRate: Double = 48_000

    enum RecorderError: Error, LocalizedError {
        case deviceNotFound(String), noInput
        var errorDescription: String? {
            switch self {
            case .deviceNotFound(let uid): "The microphone (\(uid)) is not connected."
            case .noInput: "No microphone is available."
            }
        }
    }

    func start(deviceUID: String?, maxSeconds: TimeInterval,
               onLevel: @escaping @Sendable (Float, TimeInterval) -> Void,
               onFull: @escaping @Sendable () -> Void) throws {
        _ = stop()
        let engine = AVAudioEngine()
        if let uid = deviceUID {
            guard let deviceID = AudioDevices.deviceID(uid: uid) else { throw RecorderError.deviceNotFound(uid) }
            var id = deviceID
            let status = AudioUnitSetProperty(
                engine.inputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw RecorderError.deviceNotFound(uid) }
        }
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        var acc = RecordingAccumulator(sampleRate: format.sampleRate, maxSeconds: maxSeconds)
        lock.withLock { accumulator = acc; inputRate = format.sampleRate; self.engine = engine }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: n)
            for c in 0..<channels { for i in 0..<n { mono[i] += data[c][i] } }
            if channels > 1 { for i in 0..<n { mono[i] /= Float(channels) } }
            let full: Bool = self.lock.withLock {
                guard self.accumulator != nil else { return false }
                let f = self.accumulator!.append(mono)
                acc = self.accumulator!
                return f
            }
            onLevel(acc.lastPeak, acc.elapsed)
            if full { onFull() }
        }
        try engine.start()
    }

    func stop() -> VoiceAudio? {
        let (e, acc): (AVAudioEngine?, RecordingAccumulator?) = lock.withLock {
            defer { engine = nil; accumulator = nil }
            return (engine, accumulator)
        }
        e?.inputNode.removeTap(onBus: 0)
        e?.stop()
        guard let acc, !acc.samples.isEmpty else { return nil }
        return (try? AudioResampler.resample(acc.audio, to: AudioFileIO.recordingSampleRate)) ?? acc.audio
    }
}
```

- [ ] **Step 4: `xcodegen generate`; run `RecordingAccumulatorTests` — PASS.**
- [ ] **Step 5: Commit** — `git commit -m "voice: VoiceRecorder — accumulator and engine tap"`

### Task 7: `AppSettings` — the voice preferences

**Files:**
- Modify: `Sources/App/AppSettings.swift`
- Test: `Tests/App/VoiceSettingsTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import QSOPartyLogger

@MainActor
final class VoiceSettingsTests: XCTestCase {
    private func scratch() -> UserDefaults {
        let name = "VoiceSettingsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaults() {
        let s = AppSettings(defaults: scratch())
        XCTAssertEqual(s.phoneMessageSource, .recordings)
        XCTAssertNil(s.voiceInputDeviceUID)
        XCTAssertNil(s.voiceOutputDeviceUID)
        XCTAssertEqual(s.voiceLevel, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.voicePTT, .radioCommand)
        XCTAssertEqual(s.voicePTTLeadMs, 120)
    }

    func testRoundTripThroughDefaults() {
        let d = scratch()
        let s = AppSettings(defaults: d)
        s.phoneMessageSource = .radioMemories
        s.voiceInputDeviceUID = "mic-1"
        s.voiceOutputDeviceUID = "codec-2"
        s.voiceLevel = 0.25
        s.voicePTT = .vox
        s.voicePTTLeadMs = 250
        let again = AppSettings(defaults: d)
        XCTAssertEqual(again.phoneMessageSource, .radioMemories)
        XCTAssertEqual(again.voiceInputDeviceUID, "mic-1")
        XCTAssertEqual(again.voiceOutputDeviceUID, "codec-2")
        XCTAssertEqual(again.voiceLevel, 0.25, accuracy: 1e-9)
        XCTAssertEqual(again.voicePTT, .vox)
        XCTAssertEqual(again.voicePTTLeadMs, 250)
    }

    func testUnreadableTokensFallBackToDefaults() {
        let d = scratch()
        d.set("garbage", forKey: "phoneMessageSource")
        d.set("garbage", forKey: "voicePTT")
        d.set(-5, forKey: "voicePTTLeadMs")
        d.set(7.0, forKey: "voiceLevel")
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.phoneMessageSource, .recordings)
        XCTAssertEqual(s.voicePTT, .radioCommand)
        XCTAssertEqual(s.voicePTTLeadMs, 0, "clamped into 0…500")
        XCTAssertEqual(s.voiceLevel, 1, "clamped into 0…1")
    }
}
```

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement** — after `repeatIntervalSeconds` add:

```swift
    // MARK: Voice messages recorded on this Mac

    /// Where phone keys get their audio on a radio that offers both sources.
    var phoneMessageSource: PhoneMessageSource {
        didSet { defaults.set(phoneMessageSource.rawValue, forKey: "phoneMessageSource") }
    }
    /// Microphone for recording; nil = the system default input.
    var voiceInputDeviceUID: String? {
        didSet { defaults.set(voiceInputDeviceUID, forKey: "voiceInputDeviceUID") }
    }
    /// The radio's audio input, for the sound-card path; nil = not chosen,
    /// which leaves that path not ready rather than guessing a device.
    var voiceOutputDeviceUID: String? {
        didSet { defaults.set(voiceOutputDeviceUID, forKey: "voiceOutputDeviceUID") }
    }
    /// Transmit audio level, 0…1, applied to both paths.
    var voiceLevel: Double {
        didSet { defaults.set(voiceLevel, forKey: "voiceLevel") }
    }
    /// How the sound-card path keys the radio.
    var voicePTT: VoicePTTMode {
        didSet { defaults.set(voicePTT.rawValue, forKey: "voicePTT") }
    }
    /// Milliseconds between keying and the first sample, 0…500.
    var voicePTTLeadMs: Int {
        didSet { defaults.set(voicePTTLeadMs, forKey: "voicePTTLeadMs") }
    }
```
and in `init`, before `lastStationProfile`:
```swift
        phoneMessageSource = PhoneMessageSource(rawValue: defaults.string(forKey: "phoneMessageSource") ?? "") ?? .recordings
        voiceInputDeviceUID = defaults.string(forKey: "voiceInputDeviceUID")
        voiceOutputDeviceUID = defaults.string(forKey: "voiceOutputDeviceUID")
        voiceLevel = min(1, max(0, defaults.object(forKey: "voiceLevel") as? Double ?? 0.6))
        voicePTT = VoicePTTMode(rawValue: defaults.string(forKey: "voicePTT") ?? "") ?? .radioCommand
        voicePTTLeadMs = min(500, max(0, defaults.object(forKey: "voicePTTLeadMs") as? Int ?? 120))
```

- [ ] **Step 4: Run `VoiceSettingsTests` — PASS.**
- [ ] **Step 5: Commit** — `git commit -m "voice: AppSettings — source, devices, level, PTT"`

### Task 8: `EntryFlow` — `.recording` transmissions and `PhoneSource`

**Files:**
- Modify: `Sources/App/EntryFlow.swift`
- Test: `Tests/App/EntryFlowTests.swift` (append)

- [ ] **Step 1: Failing tests** (append to `EntryFlowTests`)

```swift
    // MARK: Recordings on this Mac

    private func recordingsContext(ready: Bool = true) -> EntryFlow.Context {
        var keying = KeyingSettings(); keying.esmEnabled = true
        return EntryFlow.Context(modeClass: .phone, rawMode: "USB", radioConnected: true,
                                 cursor: .call, keying: keying, voiceMemoryCount: 0,
                                 phoneSource: .recordings(ready: ready))
    }
    private let clip = VoiceAudio(sampleRate: 48_000, samples: [0.1, 0.2, 0.3])

    func testRecordingsSourcePlaysTheMappedRecording() {
        let document = LogDocument(); document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        XCTAssertEqual(flow.transmission(at: 0, context: recordingsContext()),
                       .recording(memory: 1, audio: clip, caption: "M1 CQ"))
    }

    func testUnrecordedMemoryIsSilentUnderRecordings() {
        let document = LogDocument(); document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [2: clip]                 // F1 → M1 has nothing
        XCTAssertEqual(flow.transmission(at: 0, context: recordingsContext()), .silent)
        XCTAssertEqual(flow.transmission(at: 1, context: recordingsContext()),
                       .recording(memory: 2, audio: clip, caption: "M2 Exch"))
    }

    func testUnreadyRecordingsSourceIsSilentAndNeverFallsBackToTheRadio() {
        let document = LogDocument(); document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        var context = recordingsContext(ready: false)
        context.voiceMemoryCount = 8                       // the radio has memories, too
        XCTAssertEqual(flow.transmission(at: 0, context: context), .silent)
        XCTAssertFalse(flow.esmDrivesReturn(context))
    }

    func testESMDrivesReturnUnderRecordingsOnlyWhenReadyAndSomethingIsRecorded() {
        let flow = EntryFlow(document: LogDocument())
        XCTAssertFalse(flow.esmDrivesReturn(recordingsContext()), "nothing recorded")
        flow.voiceRecordings = [3: clip]
        XCTAssertTrue(flow.esmDrivesReturn(recordingsContext()))
        XCTAssertFalse(flow.esmDrivesReturn(recordingsContext(ready: false)))
    }

    func testRadioMemoriesSourceIgnoresRecordings() {
        let document = LogDocument(); document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        XCTAssertEqual(flow.transmission(at: 0, context: phoneContext(memories: 8)),
                       .voice(memory: 1, caption: "M1 CQ"))
    }
```

- [ ] **Step 2: Run `EntryFlowTests` — compile failure (`phoneSource`, `.recording`, `voiceRecordings`).**
- [ ] **Step 3: Implement** in `EntryFlow.swift`:

Add to `Context` (after `voiceMemoryCount`), and to its `init` as `phoneSource: PhoneSource = .radioMemories`:
```swift
        /// Where phone keys get their audio. `.radioMemories` reads
        /// `voiceMemoryCount`; `.recordings` reads `voiceRecordings` on the flow,
        /// and only when `ready`. Defaulted, so every existing literal means
        /// what it did.
        var phoneSource: PhoneSource
```
Add nested in `EntryFlow`:
```swift
    /// The two places a phone key's audio can come from — decided by the view
    /// from the setting, the connected radio and the audio path's readiness.
    enum PhoneSource: Equatable, Sendable {
        /// The radio's own recorder, memories 1...`voiceMemoryCount`.
        case radioMemories
        /// Recordings on this Mac. An unready path leaves every key silent,
        /// with the reason shown by the row — it never falls back to the
        /// radio's recorder, which would put a different recording on the air.
        case recordings(ready: Bool)
    }
```
Add to `Transmission`:
```swift
        /// A recording on this Mac, resolved to its audio so the caller can
        /// hand it straight to the radio path.
        case recording(memory: Int, audio: VoiceAudio, caption: String)
```
Add the property (after `callHistoryIndex`):
```swift
    /// The active party's recordings, memory number → rendered audio — set by
    /// the view from `VoiceStore`, like `callHistoryIndex`. Only read under
    /// `PhoneSource.recordings`.
    var voiceRecordings: [Int: VoiceAudio] = [:]
```
Replace `transmission(at:context:)`'s phone branch:
```swift
        if context.modeClass == .phone {
            let memories = document.log.messages.voiceMemories(for: document.log.operatingMode)
            guard memories.indices.contains(index), let memory = memories[index] else { return .silent }
            let caption = document.log.messages.voiceMemoryCaption(memory)
            switch context.phoneSource {
            case .radioMemories:
                guard context.voiceMemoryCount > 0,
                      (1...context.voiceMemoryCount).contains(memory) else { return .silent }
                return .voice(memory: memory, caption: caption)
            case .recordings(let ready):
                guard ready, let audio = voiceRecordings[memory] else { return .silent }
                return .recording(memory: memory, audio: audio, caption: caption)
            }
        }
```
Replace `esmDrivesReturn`'s phone arm:
```swift
        case .phone:
            switch context.phoneSource {
            case .radioMemories: return context.voiceMemoryCount > 0
            case .recordings(let ready): return ready && !voiceRecordings.isEmpty
            }
```
`MainView` must compile: in `messageKeys` add `case .recording(_, _, let caption): MessagesRow.MessageKey(caption: caption, isActive: true)`; in `transmit` add `case .recording: break` for now (Task 10 replaces it); in `waitForEndOfTransmission` add `.recording` beside `.voice`.

- [ ] **Step 4: Run `EntryFlowTests` — PASS (all, including the pre-existing phone tests).**
- [ ] **Step 5: Commit** — `git commit -m "voice: EntryFlow resolves recordings — PhoneSource, Transmission.recording"`

### Task 9: `RadioController` — the voice path and `playRecording`

**Files:**
- Modify: `Sources/App/RadioController.swift`
- Test: `Tests/App/RadioControllerRecordingTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// `RadioController`'s recordings path over a fake player. The K3 descriptor
/// on `/dev/null` is a serial radio; until the driver conforms to a transport
/// protocol the path reads `.unsupported`, which these tests pin — the
/// conformance commits flip it.
@MainActor
final class RadioControllerRecordingTests: XCTestCase {

    final class FakePlayer: VoicePlaying, @unchecked Sendable {
        var plays: [(VoiceAudio, String?, Float, Int, Int, Bool)] = []
        var stops = 0
        var onEvent: (@Sendable (TransmitAudioEvent) -> Void)?
        var keyRadio: (@Sendable (Bool) -> Void)?
        func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
                  keyRadio: (@Sendable (Bool) -> Void)?, leadMs: Int, tailMs: Int,
                  onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void) {
            plays.append((audio, deviceUID, gain, leadMs, tailMs, keyRadio != nil))
            self.onEvent = onEvent; self.keyRadio = keyRadio
        }
        func stop() { stops += 1 }
    }

    private func makeSettings() -> AppSettings {
        let s = AppSettings(defaults: Preferences.store)
        s.radioID = "elecraft-k3"; s.portPath = "/dev/null"
        s.voiceOutputDeviceUID = "codec"; s.voicePTT = .vox; s.voiceLevel = 0.5; s.voicePTTLeadMs = 90
        return s
    }
    private let clip = VoiceAudio(sampleRate: 48_000, samples: [0.5, 0.25])

    func testPathStatusTruthTable() {
        XCTAssertEqual(RadioController.voicePath(streams: false, keysOverCAT: false, ptt: .radioCommand, outputName: "USB Audio CODEC"), .unsupported)
        XCTAssertEqual(RadioController.voicePath(streams: true, keysOverCAT: false, ptt: .radioCommand, outputName: nil), .readyOverNetwork)
        XCTAssertEqual(RadioController.voicePath(streams: false, keysOverCAT: true, ptt: .radioCommand, outputName: "USB Audio CODEC"), .readyOverDevice(name: "USB Audio CODEC"))
        XCTAssertEqual(RadioController.voicePath(streams: false, keysOverCAT: false, ptt: .vox, outputName: "USB Audio CODEC"), .readyOverDevice(name: "USB Audio CODEC"),
                       "VOX needs no CAT keying, so any radio with a sound card works")
        XCTAssertEqual(RadioController.voicePath(streams: false, keysOverCAT: true, ptt: .radioCommand, outputName: nil), .notReady(reason: RadioController.chooseOutputReason))
    }

    func testDisconnectedControllerIsUnsupportedAndPlaysNothing() {
        let radio = RadioController()
        let player = FakePlayer(); radio.makeVoicePlayer = { player }
        XCTAssertEqual(radio.voicePathStatus, .unsupported)
        radio.playRecording(clip, caption: "M1 CQ", settings: makeSettings())
        XCTAssertTrue(player.plays.isEmpty)
        XCTAssertNil(radio.nowSending)
    }

    func testPlayClaimsTheBadgeAndThePlayerClearsIt() {
        let radio = RadioController()
        let player = FakePlayer(); radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { $0 == "codec" ? "USB Audio CODEC" : nil }
        let settings = makeSettings()
        radio.connect(settings: settings); defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .readyOverDevice(name: "USB Audio CODEC"), "VOX on a sound card is ready")

        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        XCTAssertEqual(radio.nowSending, "M1 CQ")
        XCTAssertTrue(radio.isVoicePlaying)
        XCTAssertEqual(player.plays.count, 1)
        XCTAssertEqual(player.plays[0].1, "codec")
        XCTAssertEqual(player.plays[0].2, 0.5)
        XCTAssertEqual(player.plays[0].3, 90)
        XCTAssertFalse(player.plays[0].5, "VOX: no keyRadio closure")

        player.onEvent?(.finished)
        let done = expectation(description: "hop"); DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertNil(radio.nowSending)
        XCTAssertFalse(radio.isVoicePlaying)
    }

    func testFailureClearsTheBadgeAndShowsTheReasonInline() {
        let radio = RadioController()
        let player = FakePlayer(); radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        radio.connect(settings: settings); defer { radio.disconnect() }
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        player.onEvent?(.failed("no device"))
        let done = expectation(description: "hop"); DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertNil(radio.nowSending)
        XCTAssertEqual(radio.lastError?.summary, "Voice message not sent")
        XCTAssertTrue(radio.lastError?.detail.contains("no device") ?? false)
    }

    func testAbortStopsThePlayerAndClearsTheBadge() {
        let radio = RadioController()
        let player = FakePlayer(); radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        radio.connect(settings: settings); defer { radio.disconnect() }
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        radio.abortTransmission(settings: settings)
        XCTAssertEqual(player.stops, 1)
        XCTAssertNil(radio.nowSending)
        XCTAssertFalse(radio.isVoicePlaying)
    }

    func testNotReadyPathRefusesToPlay() {
        let radio = RadioController()
        let player = FakePlayer(); radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in nil }                // the device is gone
        let settings = makeSettings()
        radio.connect(settings: settings); defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .notReady(reason: RadioController.chooseOutputReason))
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        XCTAssertTrue(player.plays.isEmpty)
        XCTAssertNil(radio.nowSending)
    }

    func testRadioCommandPTTWithoutACapableDriverIsUnsupportedHere() {
        // Until ElecraftK3Driver conforms (its own commit), CAT PTT has nobody to key.
        let radio = RadioController()
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings(); settings.voicePTT = .radioCommand
        radio.connect(settings: settings); defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .unsupported)
    }
}
```

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement** in `RadioController.swift`:

Top-level, beside `RadioConnectionPhase`:
```swift
/// Whether recordings on this Mac can reach the connected radio, and how.
enum VoicePathStatus: Equatable, Sendable {
    /// This radio takes no audio from the Mac. Phone keys use its own memories if it has any.
    case unsupported
    /// Supported, but not set up — the reason is what the operator must fix.
    case notReady(reason: String)
    case readyOverNetwork
    case readyOverDevice(name: String)

    var isReady: Bool {
        switch self { case .readyOverNetwork, .readyOverDevice: true; default: false }
    }
}
```
Properties:
```swift
    private(set) var voicePathStatus: VoicePathStatus = .unsupported
    /// Built per play so a stale engine never survives a device change; tests hand in a fake.
    var makeVoicePlayer: () -> any VoicePlaying = { VoicePlayer(output: EngineAudioOutput()) }
    /// UID → the device's name if it is present now. Tests inject; the app asks CoreAudio.
    var resolveOutputDevice: (String) -> String? = { AudioDevices.device(uid: $0)?.name }
    private var voicePlayer: (any VoicePlaying)?
    private var streamer: (any AudioStreamTransmitCapable)?
    private var transmitControl: (any TransmitControlCapable)?
    /// Bumped per play; a terminal event from an older play is ignored.
    private var recordingGeneration = 0

    static let chooseOutputReason = "Choose the radio's audio output in Messages → Phone."
```
In `connect`, after `voiceDriver` wiring and before `start`: 
```swift
        transmitControl = newDriver as? any TransmitControlCapable
        if var s = newDriver as? any AudioStreamTransmitCapable {
            s.onTransmitAudioEvent = { [weak self] event in
                Task { @MainActor [weak self] in self?.recordingDidReport(event, generation: nil) }
            }
            streamer = s
        }
```
Hmm — the streamer's events carry no generation; instead keep `recordingGeneration` and treat streamer events as current while `streamer` is the active path. Simpler: `recordingDidReport(_ event:)` with a `voicePlaybackIsRecording` flag; ignore when not playing.

After `isConnected = true`: `refreshVoicePath(settings: settings)`.

Pure derivation + refresh:
```swift
    /// The truth table behind `voicePathStatus`, testable without a driver.
    static func voicePath(streams: Bool, keysOverCAT: Bool, ptt: VoicePTTMode, outputName: String?) -> VoicePathStatus {
        if streams { return .readyOverNetwork }
        guard keysOverCAT || ptt == .vox else { return .unsupported }
        guard let outputName else { return .notReady(reason: chooseOutputReason) }
        return .readyOverDevice(name: outputName)
    }

    /// Re-derive after connect and whenever the voice settings change.
    func refreshVoicePath(settings: AppSettings) {
        guard isConnected else { voicePathStatus = .unsupported; return }
        voicePathStatus = Self.voicePath(
            streams: streamer != nil,
            keysOverCAT: transmitControl != nil,
            ptt: settings.voicePTT,
            outputName: settings.voiceOutputDeviceUID.flatMap(resolveOutputDevice))
    }
```
Play / events / abort:
```swift
    /// Play a recording made on this Mac. Replaces one already playing.
    func playRecording(_ audio: VoiceAudio, caption: String, settings: AppSettings) {
        guard isConnected, voicePathStatus.isReady else { return }
        stopRecordingPlayback()
        recordingGeneration += 1
        let gen = recordingGeneration
        badgeBeforeVoiceClaim = nil
        sendingClearTask?.cancel(); sendingClearTask = nil
        nowSending = caption
        nowSendingIsVoice = true
        isVoicePlaying = true
        let level = Float(settings.voiceLevel)

        if let streamer {
            let audioForRadio: VoiceAudio
            do { audioForRadio = try AudioResampler.resample(audio, to: streamer.transmitSampleRate).scaled(by: level) }
            catch { recordingDidReport(.failed(error.localizedDescription), generation: gen); return }
            streamer.transmitAudio(audioForRadio)
            return
        }
        let player = makeVoicePlayer()
        voicePlayer = player
        let keyRadio: (@Sendable (Bool) -> Void)? = (settings.voicePTT == .radioCommand && transmitControl != nil)
            ? { [transmitControl] on in transmitControl?.setTransmit(on) } : nil
        player.play(audio, deviceUID: settings.voiceOutputDeviceUID, gain: level,
                    keyRadio: keyRadio, leadMs: settings.voicePTTLeadMs, tailMs: 100) { [weak self] event in
            Task { @MainActor [weak self] in self?.recordingDidReport(event, generation: gen) }
        }
    }

    /// One event from whichever path is playing. `generation` nil = the
    /// network path, which is single-instance and needs no stamp.
    func recordingDidReport(_ event: TransmitAudioEvent, generation: Int?) {
        guard isConnected, generation == nil || generation == recordingGeneration else { return }
        switch event {
        case .started: break
        case .finished, .stopped:
            endRecordingPlayback()
        case .failed(let reason):
            endRecordingPlayback()
            lastError = ConnectionError(summary: "Voice message not sent",
                                        detail: "The recording did not go out: \(reason)")
        }
    }

    private func endRecordingPlayback() {
        isVoicePlaying = false
        voicePlayer = nil
        if nowSendingIsVoice { nowSending = nil; nowSendingIsVoice = false }
    }

    private func stopRecordingPlayback() {
        voicePlayer?.stop()
        voicePlayer = nil
        streamer?.stopTransmitAudio()
    }
```
`abortTransmission`: add `stopRecordingPlayback()` and `isVoicePlaying = false` hmm — `isVoicePlaying` may also reflect the radio's DVR; keep the abort setting `isVoicePlaying = false` only for the recordings path: after `stopRecordingPlayback()` call `endRecordingPlayback()` guarded by `voicePlayer != nil || streamer != nil && wasPlaying`. Simplest: track `private var recordingIsPlaying = false` set true in `playRecording` and false in `endRecordingPlayback`; abort → `if recordingIsPlaying { endRecordingPlayback() }`. `disconnect`: `stopRecordingPlayback(); recordingIsPlaying = false; streamer = nil; transmitControl = nil; voicePathStatus = .unsupported`.

- [ ] **Step 4: Run `RadioControllerRecordingTests` and `RadioControllerVoiceTests` — PASS.**
- [ ] **Step 5: Commit** — `git commit -m "voice: RadioController — voice path status, playRecording, abort"`

### Task 10: `VoiceStore` — the app-side glue

**Files:**
- Create: `Sources/App/VoiceStore.swift`
- Test: `Tests/App/VoiceStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

@MainActor
final class VoiceStoreTests: XCTestCase {
    final class FakeRecorder: VoiceRecording, @unchecked Sendable {
        var started = 0; var result: VoiceAudio?
        var onLevel: (@Sendable (Float, TimeInterval) -> Void)?
        var onFull: (@Sendable () -> Void)?
        func start(deviceUID: String?, maxSeconds: TimeInterval,
                   onLevel: @escaping @Sendable (Float, TimeInterval) -> Void,
                   onFull: @escaping @Sendable () -> Void) throws {
            started += 1; self.onLevel = onLevel; self.onFull = onFull
        }
        func stop() -> VoiceAudio? { result }
    }

    private var folder: URL!
    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func tone(seconds: Double) -> VoiceAudio {
        VoiceAudio(sampleRate: 48_000, samples: (0..<Int(seconds * 48_000)).map { 0.5 * sinf(Float($0) * 0.13) })
    }

    private func waitForRender(_ store: VoiceStore, memory: Int, timeout: TimeInterval = 5) {
        let e = expectation(description: "rendered M\(memory)")
        Task { @MainActor in
            while store.rendered[memory] == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
            e.fulfill()
        }
        wait(for: [e], timeout: timeout)
    }

    func testRecordingWritesTrimsAndRenders() async throws {
        let recorder = FakeRecorder()
        // 0.3 s silence, 0.4 s tone, 0.3 s silence.
        var s = [Float](repeating: 0, count: 14_400); s += tone(seconds: 0.4).samples; s += [Float](repeating: 0, count: 14_400)
        recorder.result = VoiceAudio(sampleRate: 48_000, samples: s)
        let store = VoiceStore(library: VoiceLibrary(folder: folder), makeRecorder: { recorder })
        store.partyID = "txqp"

        try store.record(memory: 2, inputDeviceUID: nil)
        XCTAssertTrue(store.isRecording); XCTAssertEqual(store.recordingMemory, 2)
        store.stopRecording()
        XCTAssertFalse(store.isRecording)
        let clip = try XCTUnwrap(store.set[2])
        XCTAssertEqual(clip.duration, 1.0, accuracy: 1e-6)
        XCTAssertEqual(clip.trimStart, 0.3 - 0.12, accuracy: 0.01, "auto-trimmed with 120 ms of pad")
        XCTAssertEqual(clip.trimEnd, 0.7 + 0.12, accuracy: 0.01)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("txqp/M2.wav").path))
        waitForRender(store, memory: 2)
        XCTAssertEqual(store.rendered[2]!.duration, clip.trimmedDuration, accuracy: 0.002)
    }

    func testReloadOnPartyChangeAndTrimGainRenderThrough() throws {
        let library = VoiceLibrary(folder: folder)
        try AudioFileIO.write(tone(seconds: 2), to: library.fileURL(partyID: "alqp", fileName: "M1.wav"))
        var set = VoiceMessageSet()
        set[1] = VoiceClip(fileName: "M1.wav", duration: 2, trimStart: 0.5, trimEnd: 1.5, gainDB: -6.0206, recordedAt: Date())
        try library.save(set, partyID: "alqp")

        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "alqp"
        waitForRender(store, memory: 1)
        XCTAssertEqual(store.rendered[1]!.duration, 1.0, accuracy: 1e-3)
        XCTAssertEqual(store.rendered[1]!.peak, 0.25, accuracy: 0.02)
        XCTAssertEqual(store.waveforms[1]?.count, VoiceStore.waveformBins)

        store.partyID = "txqp"
        XCTAssertTrue(store.set.isEmpty); XCTAssertTrue(store.rendered.isEmpty)
    }

    func testEditsPersistAndDeleteRemoves() throws {
        let library = VoiceLibrary(folder: folder)
        try AudioFileIO.write(tone(seconds: 1), to: library.fileURL(partyID: "alqp", fileName: "M4.wav"))
        var set = VoiceMessageSet()
        set[4] = VoiceClip(fileName: "M4.wav", duration: 1, trimStart: 0, trimEnd: 1, gainDB: 0, recordedAt: Date())
        try library.save(set, partyID: "alqp")
        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "alqp"
        waitForRender(store, memory: 4)

        store.setTrim(memory: 4, start: 0.2, end: 0.6)
        store.normalize(memory: 4)
        XCTAssertEqual(try library.load(partyID: "alqp")[4]?.trimStart, 0.2)
        XCTAssertEqual(try library.load(partyID: "alqp")[4]?.gainDB ?? 0, 5.02, accuracy: 0.1, "0.5 peak → −1 dBFS")
        store.delete(memory: 4)
        XCTAssertNil(store.set[4])
        XCTAssertNil(try library.load(partyID: "alqp")[4])
        XCTAssertNil(store.rendered[4])
    }

    func testCopyMissingFromAnotherParty() throws {
        let library = VoiceLibrary(folder: folder)
        try AudioFileIO.write(tone(seconds: 1), to: library.fileURL(partyID: "alqp", fileName: "M3.wav"))
        var set = VoiceMessageSet()
        set[3] = VoiceClip(fileName: "M3.wav", duration: 1, trimStart: 0, trimEnd: 1, gainDB: 0, recordedAt: Date())
        try library.save(set, partyID: "alqp")
        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "txqp"
        XCTAssertEqual(store.copyMissing(from: "alqp"), 1)
        XCTAssertEqual(store.set.recordedMemories, [3])
        XCTAssertEqual(store.partiesWithRecordings, ["alqp", "txqp"])
    }
}
```

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation
import AVFAudio

/// The active party's recordings, for the editor and the flow: the set on
/// disk, each clip rendered (trim + gain) in memory, waveforms for the rows,
/// and the recorder/preview glue. One per document window.
@MainActor
@Observable
final class VoiceStore {
    static let maxRecordingSeconds: TimeInterval = 30
    static let autoTrimPad: TimeInterval = 0.12
    static let autoTrimThresholdDB: Float = -40
    static let waveformBins = 96

    let library: VoiceLibrary
    private let makeRecorder: () -> any VoiceRecording
    private var recorder: (any VoiceRecording)?
    private var previewOutput: (any AudioOutput)?

    var partyID: String? { didSet { if partyID != oldValue { reload() } } }
    private(set) var set = VoiceMessageSet()
    private(set) var rendered: [Int: VoiceAudio] = [:]
    private(set) var waveforms: [Int: [Float]] = [:]
    /// The last thing that went wrong, for the tab's inline line.
    private(set) var lastError: String?

    private(set) var isRecording = false
    private(set) var recordingMemory: Int?
    private(set) var inputLevel: Float = 0
    private(set) var recordingElapsed: TimeInterval = 0
    private(set) var previewingMemory: Int?

    private var renderTask: Task<Void, Never>?

    init(library: VoiceLibrary = VoiceLibrary(folder: VoiceLibrary.defaultFolder),
         makeRecorder: @escaping () -> any VoiceRecording = { EngineVoiceRecorder() }) {
        self.library = library
        self.makeRecorder = makeRecorder
    }

    var partiesWithRecordings: [String] { library.partiesWithRecordings() }

    // MARK: Loading and rendering

    func reload() {
        rendered = [:]; waveforms = [:]; lastError = nil
        guard let partyID else { set = VoiceMessageSet(); return }
        do { set = try library.load(partyID: partyID) }
        catch { set = VoiceMessageSet(); lastError = "Couldn't read this party's recordings: \(error.localizedDescription)" }
        renderAll()
    }

    private func renderAll() {
        renderTask?.cancel()
        guard let partyID else { return }
        let library = self.library, set = self.set
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            var out: [Int: VoiceAudio] = [:]; var waves: [Int: [Float]] = [:]
            for (memory, clip) in set.clips {
                if Task.isCancelled { return }
                guard let audio = try? AudioFileIO.read(library.fileURL(partyID: partyID, fileName: clip.fileName)) else { continue }
                let cut = audio.trimmed(from: clip.trimStart, to: clip.trimEnd).applyingGain(dB: clip.gainDB)
                out[memory] = cut
                waves[memory] = cut.waveform(bins: VoiceStore.waveformBins)
            }
            let final = out, finalWaves = waves
            await MainActor.run { [weak self] in
                guard let self, self.partyID == partyID, !Task.isCancelled else { return }
                self.rendered = final; self.waveforms = finalWaves
            }
        }
    }

    private func persist() {
        guard let partyID else { return }
        do { try library.save(set, partyID: partyID); lastError = nil }
        catch { lastError = "Couldn't save the recordings: \(error.localizedDescription)" }
    }

    // MARK: Recording

    func record(memory: Int, inputDeviceUID: String?) throws {
        stopPreview()
        let recorder = makeRecorder()
        try recorder.start(deviceUID: inputDeviceUID, maxSeconds: Self.maxRecordingSeconds,
                           onLevel: { [weak self] level, elapsed in
                               Task { @MainActor [weak self] in self?.inputLevel = level; self?.recordingElapsed = elapsed }
                           },
                           onFull: { [weak self] in Task { @MainActor [weak self] in self?.stopRecording() } })
        self.recorder = recorder
        isRecording = true; recordingMemory = memory; inputLevel = 0; recordingElapsed = 0
    }

    func stopRecording() {
        guard isRecording, let memory = recordingMemory, let partyID else { return }
        let audio = recorder?.stop()
        recorder = nil
        isRecording = false; recordingMemory = nil; inputLevel = 0
        guard let audio, !audio.isEmpty else { return }
        let fileName = VoiceLibrary.fileName(memory: memory)
        do { try AudioFileIO.write(audio, to: library.fileURL(partyID: partyID, fileName: fileName)) }
        catch { lastError = "Couldn't save the recording: \(error.localizedDescription)"; return }
        let voiced = audio.voicedRange(thresholdDB: Self.autoTrimThresholdDB, pad: Self.autoTrimPad)
        set[memory] = VoiceClip(fileName: fileName, duration: audio.duration,
                                trimStart: voiced?.lowerBound ?? 0, trimEnd: voiced?.upperBound ?? audio.duration,
                                gainDB: 0, recordedAt: Date())
        persist(); renderAll()
    }

    // MARK: Editing

    func setTrim(memory: Int, start: TimeInterval, end: TimeInterval) {
        guard var clip = set[memory] else { return }
        clip.trimStart = max(0, min(clip.duration, start))
        clip.trimEnd = max(clip.trimStart, min(clip.duration, end))
        set[memory] = clip; persist(); renderAll()
    }

    func setGain(memory: Int, dB: Float) {
        guard var clip = set[memory] else { return }
        clip.gainDB = dB; set[memory] = clip; persist(); renderAll()
    }

    /// Peak of the trimmed clip to −1 dBFS.
    func normalize(memory: Int) {
        guard let clip = set[memory], let partyID,
              let audio = try? AudioFileIO.read(library.fileURL(partyID: partyID, fileName: clip.fileName)) else { return }
        setGain(memory: memory, dB: audio.trimmed(from: clip.trimStart, to: clip.trimEnd).normalizationGainDB(targetDB: -1))
    }

    func autoTrim(memory: Int) {
        guard let clip = set[memory], let partyID,
              let audio = try? AudioFileIO.read(library.fileURL(partyID: partyID, fileName: clip.fileName)) else { return }
        let r = audio.voicedRange(thresholdDB: Self.autoTrimThresholdDB, pad: Self.autoTrimPad)
        setTrim(memory: memory, start: r?.lowerBound ?? 0, end: r?.upperBound ?? audio.duration)
    }

    func delete(memory: Int) {
        guard let partyID else { return }
        do { try library.remove(memory: memory, partyID: partyID) } catch { lastError = error.localizedDescription }
        set[memory] = nil; rendered[memory] = nil; waveforms[memory] = nil
    }

    func importFile(_ url: URL, memory: Int) {
        guard let partyID else { return }
        do {
            let audio = try AudioFileIO.read(url)
            let fileName = VoiceLibrary.fileName(memory: memory)
            try AudioFileIO.write(try AudioResampler.resample(audio, to: AudioFileIO.recordingSampleRate),
                                  to: library.fileURL(partyID: partyID, fileName: fileName))
            set[memory] = VoiceClip(fileName: fileName, duration: audio.duration, trimStart: 0,
                                    trimEnd: audio.duration, gainDB: 0, recordedAt: Date())
            persist(); renderAll()
        } catch { lastError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)" }
    }

    @discardableResult
    func copyMissing(from source: String) -> Int {
        guard let partyID else { return 0 }
        do {
            let n = try library.copyMissing(from: source, to: partyID)
            if n > 0 { reload() }
            return n
        } catch { lastError = error.localizedDescription; return 0 }
    }

    /// The whole file, untrimmed, for the trim popover.
    func fullAudio(memory: Int) -> VoiceAudio? {
        guard let clip = set[memory], let partyID else { return nil }
        return try? AudioFileIO.read(library.fileURL(partyID: partyID, fileName: clip.fileName))
    }

    // MARK: Preview on the Mac

    func preview(memory: Int) {
        stopPreview()
        guard let audio = rendered[memory] else { return }
        let output = EngineAudioOutput()
        previewOutput = output
        previewingMemory = memory
        do {
            try output.start(audio, deviceUID: nil, gain: 1) { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.previewOutput === output { self?.previewingMemory = nil; self?.previewOutput = nil }
                }
            }
        } catch { previewingMemory = nil; previewOutput = nil; lastError = error.localizedDescription }
    }

    func stopPreview() {
        previewOutput?.stop(); previewOutput = nil; previewingMemory = nil
    }
}
```

- [ ] **Step 4: `xcodegen generate`; run `VoiceStoreTests` — PASS.**
- [ ] **Step 5: Commit** — `git commit -m "voice: VoiceStore — the party's set, rendered, recorder and preview glue"`

### Task 11: The UI — `VoiceMessagesPane`, `MessagesEditor`, `MainView`

**Files:**
- Create: `Sources/UI/VoiceMessagesPane.swift`, `Sources/UI/VoiceTrimPopover.swift`
- Modify: `Sources/UI/MessagesEditor.swift`, `Sources/UI/MainView.swift`
- Test: `Tests/App/VoiceStatusTextTests.swift` (widen), `Tests/UI/VoicePaneKeysTests.swift`

- [ ] **Step 1: Failing tests** — status wording covers every path/source and stays neutral; the pane's key table.

```swift
// Tests/UI/VoicePaneKeysTests.swift
import XCTest
@testable import QSOPartyLogger

final class VoicePaneKeysTests: XCTestCase {
    func testDigitShortcutsCoverAllEightMemories() {
        for m in 1...8 {
            XCTAssertEqual(VoiceMessagesPane.recordKey(memory: m), KeyEquivalent(Character("\(m)")))
        }
    }
    func testStatusSentencesNameNoVendor() {
        let banned = ["k3", "kx3", "kx2", "flex", "icom", "yaesu", "kenwood", "elecraft", "dax", "4991", "smartsdr"]
        let texts = [
            VoiceMessagesPane.pathText(.unsupported, source: .recordings, radioHasMemories: false),
            VoiceMessagesPane.pathText(.unsupported, source: .recordings, radioHasMemories: true),
            VoiceMessagesPane.pathText(.notReady(reason: RadioController.chooseOutputReason), source: .recordings, radioHasMemories: false),
            VoiceMessagesPane.pathText(.readyOverNetwork, source: .recordings, radioHasMemories: false),
            VoiceMessagesPane.pathText(.readyOverDevice(name: "USB Audio CODEC"), source: .recordings, radioHasMemories: true),
            VoiceMessagesPane.pathText(.readyOverDevice(name: "USB Audio CODEC"), source: .radioMemories, radioHasMemories: true),
        ]
        for t in texts { for b in banned { XCTAssertFalse(t.lowercased().contains(b), "'\(t)' names \(b)") } }
        XCTAssertTrue(texts[3].contains("network"))
        XCTAssertTrue(texts[4].contains("USB Audio CODEC"))
    }
}
```
Add to `VoiceStatusTextTests.allStatusTexts` the new `MessagesEditor.voiceStatusText(...)` overload is unchanged (it keeps describing the radio's memories) — no change needed beyond compiling.

- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement the pane**

`VoiceMessagesPane.swift` — the phone tab's body. Signature and the pure helpers the tests pin:
```swift
import SwiftUI

/// The Messages editor's Phone tab: source, devices, level, eight recorder
/// rows, and the F-key mapping. Names and mappings ride the sheet's draft;
/// recordings save as they are made.
struct VoiceMessagesPane: View {
    @Bindable var store: VoiceStore
    @Bindable var settings: AppSettings
    var radio: RadioController
    let voiceStatus: VoiceKeyerStatus
    let editMode: OperatingMode
    /// Draft accessors, so the pane never owns the sheet's draft.
    let name: (Int) -> Binding<String>          // memory index 0-based
    let mapping: (Int) -> Binding<Int?>          // F-key index 0-based
    let pickerCaption: (Int) -> String           // memory 1-based
    let onPlayToRadio: (Int) -> Void             // memory 1-based

    @State private var trimming: Int?
    @State private var importing: Int?
    @State private var inputDevices: [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []

    static func recordKey(memory: Int) -> KeyEquivalent { KeyEquivalent(Character(String(memory))) }

    /// The one sentence under the rows. Neutral: no maker, no model, no port.
    nonisolated static func pathText(_ path: VoicePathStatus, source: PhoneMessageSource, radioHasMemories: Bool) -> String {
        if source == .radioMemories, radioHasMemories {
            return "Phone keys play the radio's own voice memories. Switch the source above to use these recordings."
        }
        switch path {
        case .unsupported:
            return radioHasMemories
                ? "This radio can't take audio from this Mac, so phone keys play its own voice memories."
                : "No radio that can take audio from this Mac is connected. Recordings can still be made and previewed."
        case .notReady(let reason):
            return "Recordings can't reach the radio yet: \(reason)"
        case .readyOverNetwork:
            return "Recordings play to the radio over its network connection; the radio is keyed for each message."
        case .readyOverDevice(let name):
            return "Recordings play to the radio through \(name); PTT by radio command or VOX as set above."
        }
    }
    …
}
```
Body outline (all real SwiftUI, no placeholders when written):
1. `if voiceStatus.isReady` → `Picker("Phone messages play from", selection: $settings.phoneMessageSource)` with `Text("Recordings on this Mac")` / `Text("The radio's voice memories")`, `.pickerStyle(.segmented)`; `.onChange` → `radio.refreshVoicePath(settings:)`.
2. Device row: `Picker("Microphone", selection: inputBinding)` over `inputDevices` (+ "System default" tag nil) with a `LevelMeter(level: store.inputLevel)` capsule; when `radio.voicePathStatus` is `.readyOverDevice`/`.notReady`: `Picker("Radio audio out", …outputDevices, "Not chosen" nil)`, `Picker("PTT", $settings.voicePTT)` (Radio command / VOX), `Stepper("Lead \(ms) ms", value: $settings.voicePTTLeadMs, in: 0...500, step: 10)`; always `Slider(value: $settings.voiceLevel, in: 0...1) { Text("Level") }`. Each `.onChange` → `radio.refreshVoicePath(settings:)`.
3. `HStack(alignment: .top)`: left `Grid` of 8 `memoryRow(m)`; right the F-key `Grid` (moved from `MessagesEditor`, using `mapping`/`pickerCaption`).
4. `memoryRow(m)`: `Text("M\(m)")`, `TextField("", text: name(m-1)).frame(width: 110)`, `WaveformView(bins: store.waveforms[m], recording: store.recordingMemory == m, level: store.inputLevel).frame(width: 120, height: 22)`, duration text (`"%.1f s"` of `set[m]?.trimmedDuration`, or "no recording", or elapsed while recording), buttons: record (`Button { toggleRecord(m) } label: { Image(systemName: store.recordingMemory == m ? "stop.circle.fill" : "record.circle") }.keyboardShortcut(Self.recordKey(memory: m), modifiers: .command).help("Record M\(m) (⌘\(m)); press again to stop")`), preview (`⌥⌘m`, `play.fill`/`stop.fill`), trim (`scissors`, `.popover(isPresented:)` → `VoiceTrimPopover`), play to radio (`antenna.radiowaves.left.and.right`, disabled unless `radio.voicePathStatus.isReady && store.rendered[m] != nil`), `Menu` (`ellipsis.circle`): Import…, Reveal in Finder, Delete.
5. Below: `Menu("Copy from another party…")` listing `store.partiesWithRecordings` minus the current; the `pathText` sentence; `store.lastError` in orange when present; "Recordings save as you make them." caption.
6. `.fileImporter(isPresented:, allowedContentTypes: [.audio])` → `store.importFile(url, memory:)`.
7. `.onAppear { refreshDevices() }` where `refreshDevices` reads `AudioDevices.inputDevices()/outputDevices()`.
8. `toggleRecord(m)`: if recording m → `store.stopRecording()`; else request mic access (`AVCaptureDevice.requestAccess(for: .audio)`) then `try store.record(memory: m, inputDeviceUID: settings.voiceInputDeviceUID)`, errors → `store.lastError` via a small `@State private var localError`.

`VoiceTrimPopover.swift`: `VoiceTrimPopover(store:, memory:)` — loads `store.fullAudio(memory:)` on appear, draws `WaveformShape` of the full clip with the trimmed region highlighted, two `Slider`s (start, end) bound to local state that call `store.setTrim` on release (`onEditingChanged`), buttons Play (Space via `.keyboardShortcut(.space, modifiers: [])`), Auto-trim (`store.autoTrim`), Normalize (`store.normalize`), Done.

`WaveformView`: a `Canvas` drawing `bins` as vertical bars; while recording it draws a live level bar instead.

- [ ] **Step 4: Wire `MessagesEditor`** — add `let voiceStore: VoiceStore`, `var radio: RadioController`, `let onPlayToRadio: (Int) -> Void`; in the phone branch replace the memory-name grid + F-key grid with `VoiceMessagesPane(store: voiceStore, settings: settings, radio: radio, voiceStatus: voiceStatus, editMode: editMode, name: nameBinding, mapping: memoryBinding, pickerCaption: voiceMemoryPickerCaption, onPlayToRadio: onPlayToRadio)`; keep `Text(Self.voiceStatusText(voiceStatus, bank: voiceBank))` under it only when `voiceStatus != .unsupported`. Add `init(document:settings:voiceStatus:voiceBank:voiceStore:radio:onPlayToRadio:initialClass:)` with `initialClass: ModeClass = .cw` seeding `editClass`. Widen `.frame(minWidth: 860, minHeight: 560, alignment: .topLeading)`.

- [ ] **Step 5: Wire `MainView`**
  - `@State private var voiceStore = VoiceStore()`; `@State private var messagesEditorClass: ModeClass = .cw`.
  - `.sheet(isPresented: $showMessagesEditor) { MessagesEditor(document:…, voiceStore: voiceStore, radio: radio, onPlayToRadio: playRecordingToRadio, initialClass: messagesEditorClass) }`.
  - `onAppear`: `voiceStore.partyID = document.log.partyID`; `.onChange(of: document.log.partyID) { voiceStore.partyID = document.log.partyID }` (beside `applyDefaultDocumentName`); `.onChange(of: voiceStore.rendered) { flow.voiceRecordings = voiceStore.rendered }`; `.onChange(of: settings.voiceOutputDeviceUID) { radio.refreshVoicePath(settings: settings) }` and the same for `voicePTT` and `phoneMessageSource`.
  - `operatingContext` gains `phoneSource: phoneSource` where:
    ```swift
    private var phoneSource: EntryFlow.PhoneSource {
        switch settings.phoneMessageSource {
        case .radioMemories: return .radioMemories
        case .recordings:
            switch radio.voicePathStatus {
            case .unsupported: return .radioMemories
            case .notReady: return .recordings(ready: false)
            case .readyOverNetwork, .readyOverDevice: return .recordings(ready: true)
            }
        }
    }
    ```
  - `messageKeys`: `.recording` caption active; `.silent` on phone caption "—".
  - `transmit`: `case .recording(_, let audio, let caption): radio.playRecording(audio, caption: caption, settings: settings)`.
  - `MessagesRow(enabled:)`: `radio.isConnected && (currentModeClass == .cw || (currentModeClass == .phone && phoneKeysEnabled))` with `phoneKeysEnabled = (phoneSource == .radioMemories && radio.voiceStatus.isReady) || phoneSource == .recordings(ready: true)`.
  - `startRepeat`: replace `voiceReady` with `phoneKeysEnabled`.
  - `playRecordingToRadio(memory:)`: `if let audio = voiceStore.rendered[memory] { radio.playRecording(audio, caption: document.log.messages.voiceMemoryCaption(memory), settings: settings) }`.
  - Toolbar: label "Messages"; add a hidden `Button("Voice Messages") { messagesEditorClass = .phone; showMessagesEditor = true }.keyboardShortcut("v", modifiers: [.command, .shift]).opacity(0).accessibilityHidden(true)` in the toolbar item group's background (the pattern `MessagesRow` uses for ⌘R); the visible button sets `messagesEditorClass = .cw`.
  - `RadioController.connect` already refreshes the path; also call `radio.refreshVoicePath(settings:)` in `.onChange(of: radio.isConnected)`.

- [ ] **Step 6: `xcodegen generate`; build; run `VoicePaneKeysTests`, `VoiceStatusTextTests`, then the whole suite — all PASS.**
- [ ] **Step 7: Commit** — `git commit -m "voice: the Messages editor's Phone tab records, trims and plays; MainView dispatches recordings"`

### Task 12: Entitlement, usage string, docs, CLAUDE.md, .gitignore

**Files:**
- Modify: `project.yml`, `Resources/Info.plist` (regenerated), `Resources/QSOPartyLogger.entitlements` (regenerated), `README.md`, `CLAUDE.md`, `.gitignore`

- [ ] **Step 1:** In `project.yml` add under `info.properties`: `NSMicrophoneUsageDescription: "Voice messages are recorded here and played to your radio."`, under `entitlements.properties`: `com.apple.security.device.audio-input: true` with a comment. Add `build-logs/` to `.gitignore`. Run `xcodegen generate` and confirm both files changed (`git diff --stat`).
- [ ] **Step 2: README** — in "Radio control and CW" replace the two "Phone keys from the radio's own voice memories…" paragraphs with: recordings on this Mac are the default phone source (record/trim/normalize/import/copy-from in Messages → Phone; per party; the level meter and play-to-radio; PTT by radio command or VOX with lead; ⌘1–⌘8 / ⌥⌘1–⌥⌘8; a second key replaces the clip; Esc; repeat CQ off the real end); the radio's own memories stay the option with the existing caveats. Keyboard table: `F1`–`F8` row mentions recordings; add rows for `⇧⌘V`, `⌘1`–`⌘8`, `⌥⌘1`–`⌥⌘8`. Update the "**2530 unit tests**" line to the new count and the coverage sentence ("…the voice recorder's model and DSP, the sound-card keying sequence…"). Quick start step 2 unchanged.
- [ ] **Step 3: CLAUDE.md** layout table: add `Sources/Core/Voice/` — "`VoiceAudio` DSP, `VoiceClip`/`VoiceMessageSet`, `VoiceLibrary` (per-party recordings on disk)" and `Sources/Hardware/Voice/` — "transport protocols, `VoicePlayer` keying sequence, recorder, file IO, resampler, device list". Rule 5 sentence: "**Voice: recordings on the Mac are the default phone source, played by the app which keys the radio; the radio's own memories are the option (Article 11 as amended 2026-08-15).** Never key on connect."
- [ ] **Step 4:** Full suite → count → README. Commit — `git commit -m "voice: entitlement, usage string, README, CLAUDE.md, test count"` — this closes Commit A. Article 10 grep must return nothing:
  `grep -rniE "k3|kx3|kx2|flex|icom|yaesu|kenwood|elecraft|ci-v" Sources/App Sources/UI | grep -vE ':[0-9]+: *(//|\*)' | grep -vE ':[0-9]+: *case [A-Za-z]+ = "'`

---

## Commit B — Elecraft: `TransmitControlCapable`

### Task 13: `ElecraftK3Driver` keys over CAT

**Files:**
- Modify: `Sources/Hardware/Radio/ElecraftK3Driver.swift`
- Test: `Tests/Hardware/K3ProtocolTests.swift` (append), `Tests/App/RadioControllerRecordingTests.swift` (flip one)

- [ ] **Step 1: Failing tests** — append to `K3ProtocolTests` (use its existing mock transport helper):
```swift
    // MARK: Transmit control for Mac-side recordings (Pgmrs Ref G5: TX, RX)

    func testSetTransmitOnWritesTXAndOffWritesRX() {
        let transport = MockTransport()      // the class the file already uses
        let driver = ElecraftK3Driver()
        driver.start(transport: transport)
        transport.written = []
        driver.setTransmit(true)
        XCTAssertEqual(transport.writtenText, "TX;")
        driver.setTransmit(false)
        XCTAssertEqual(transport.writtenText, "TX;RX;")
    }

    func testDriverIsTransmitControlCapableAndNotAStreamer() {
        XCTAssertNotNil(ElecraftK3Driver() as? any TransmitControlCapable)
        XCTAssertNil(ElecraftK3Driver() as? any AudioStreamTransmitCapable)
    }
```
And in `RadioControllerRecordingTests` rename/flip `testRadioCommandPTTWithoutACapableDriverIsUnsupportedHere` to `testRadioCommandPTTIsReadyOnADriverThatKeysOverCAT` asserting `.readyOverDevice(name: "USB Audio CODEC")` and, after `playRecording`, `player.plays[0].5 == true` (keyRadio present).

- [ ] **Step 2: Run — the K3 tests fail to compile (no `setTransmit`), the controller test fails red.**
- [ ] **Step 3: Implement** — header comment gains the sentence "Recordings made on the Mac play through the sound card, and this driver keys the radio around them over CAT (`TX;`/`RX;`, Programmer's Reference G5) — `TransmitControlCapable`."; add `static let cmdTransmit = "TX;"` and `static let cmdReceive = "RX;"` (and make `cmdStopVoiceMessage` read `cmdReceive`); add:
```swift
extension ElecraftK3Driver: TransmitControlCapable {
    /// `TX;` "Same as activating PTT or using the XMIT switch"; `RX;`
    /// "Terminates transmit in all modes" (Pgmrs Ref G5).
    func setTransmit(_ on: Bool) {
        currentTransport()?.write(on ? Self.cmdTransmit : Self.cmdReceive)
    }
}
```
- [ ] **Step 4: Run `K3ProtocolTests`, `RadioControllerRecordingTests`, `RadioRegistryTests` — PASS.**
- [ ] **Step 5: Docs** — README: a "### Playing recordings through a K3" subsection after "Wiring a K3 for direct keying": LINE IN ← Mac audio out; `MAIN:MIC SEL` = LINE IN or `MIC+LIN` ON; level 6–10 dB under clipping, set with the ALC meter and the app's Level; PTT by `TX;`/`RX;` (no VOX needed; VOX available); K3S/KX3/KX2: see their manuals for the input jack. PROVENANCE: a "Radio protocols — Elecraft transmit control and line input" bullet citing G5 (`TX`, `RX`) and Owner's Manual D10 with the fetch date and the excerpts file. Test count in README.
- [ ] **Step 6: Commit** — `git commit -m "elecraft: TransmitControlCapable — TX;/RX; around Mac-side recordings"`

---

## Commit C — Flex: `AudioStreamTransmitCapable`

### Task 14: `DAXPacketizer` — the VITA-49 bytes

**Files:**
- Create: `Sources/Hardware/Radio/FlexDAXPacketizer.swift`
- Test: `Tests/Hardware/FlexDAXPacketizerTests.swift`

- [ ] **Step 1: Failing tests**
```swift
import XCTest
@testable import QSOPartyLogger

/// The packet FlexLib 3.2.37's DAXTXAudioStream sends, byte for byte — see
/// docs/research/flexlib_3_2_37_dax_tx_excerpts.txt.
final class FlexDAXPacketizerTests: XCTestCase {
    private func be32(_ d: Data, _ at: Int) -> UInt32 {
        (UInt32(d[at]) << 24) | (UInt32(d[at + 1]) << 16) | (UInt32(d[at + 2]) << 8) | UInt32(d[at + 3])
    }

    func testOnePacketHeaderAndIDs() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0.25, count: 128))
        let packets = FlexDAXPacketizer.packets(for: audio, streamID: 0x8400_0001, startingSequence: 5)
        XCTAssertEqual(packets.count, 1)
        let p = packets[0]
        XCTAssertEqual(p.count, 1052, "263 words")
        XCTAssertEqual(p[0], 0x18, "IF data with stream (1<<4) | class id (1<<3), no trailer")
        XCTAssertEqual(p[1], 0xD5, "TSI other (3<<6) | TSF sample count (1<<4) | count 5")
        XCTAssertEqual(be32(p, 0) & 0xFFFF, 263)
        XCTAssertEqual(be32(p, 4), 0x8400_0001, "stream id")
        XCTAssertEqual(be32(p, 8), 0x001C_2D, "OUI")
        XCTAssertEqual(be32(p, 12), 0x534C_03E3, "information class | packet class")
        XCTAssertEqual(be32(p, 16), 0); XCTAssertEqual(be32(p, 20), 0); XCTAssertEqual(be32(p, 24), 0, "timestamps zero")
        // First stereo pair: 0.25 as big-endian float32 = 0x3E800000, in L and R.
        XCTAssertEqual(be32(p, 28), 0x3E80_0000); XCTAssertEqual(be32(p, 32), 0x3E80_0000)
    }

    func testSequenceWrapsAt16AndCountsPerPacket() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0, count: 128 * 20))
        let packets = FlexDAXPacketizer.packets(for: audio, streamID: 1, startingSequence: 14)
        XCTAssertEqual(packets.count, 20)
        XCTAssertEqual(packets.map { $0[1] & 0x0F }, [14, 15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 1])
    }

    func testLastPacketIsZeroPaddedAndAShortClipYieldsOnePacket() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [1.0, -1.0, 0.5])
        let packets = FlexDAXPacketizer.packets(for: audio, streamID: 1, startingSequence: 0)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(be32(packets[0], 28), 0x3F80_0000)               // 1.0 L
        XCTAssertEqual(be32(packets[0], 32), 0x3F80_0000)               // 1.0 R
        XCTAssertEqual(be32(packets[0], 36), 0xBF80_0000)               // -1.0
        XCTAssertEqual(be32(packets[0], 28 + 3 * 8), 0, "frame 3 onward is silence")
        XCTAssertEqual(be32(packets[0], 1052 - 4), 0)
    }

    func testSamplesAreClippedToFullScale() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [2.0, -3.0])
        let p = FlexDAXPacketizer.packets(for: audio, streamID: 1, startingSequence: 0)[0]
        XCTAssertEqual(be32(p, 28), 0x3F80_0000)
        XCTAssertEqual(be32(p, 36), 0xBF80_0000)
    }

    func testPacketIntervalIs128FramesAt24k() {
        XCTAssertEqual(FlexDAXPacketizer.framesPerPacket, 128)
        XCTAssertEqual(FlexDAXPacketizer.sampleRate, 24_000)
        XCTAssertEqual(FlexDAXPacketizer.packetInterval, 128.0 / 24_000, accuracy: 1e-12)
    }
}
```
- [ ] **Step 2: Run — compile failure.**
- [ ] **Step 3: Implement**
```swift
import Foundation

/// The VITA-49 IF-data packet a DAX transmit client sends the radio, exactly
/// as FlexLib 3.2.37's `DAXTXAudioStream` builds it (banked excerpts in
/// docs/research/flexlib_3_2_37_dax_tx_excerpts.txt): 128 frames of stereo
/// float32, big-endian, class 0x03E3, sequence count mod 16, no trailer,
/// zero timestamps. Pure — the driver paces and sends what this returns.
enum FlexDAXPacketizer {
    static let sampleRate = 24_000.0
    static let framesPerPacket = 128
    static var packetInterval: TimeInterval { Double(framesPerPacket) / sampleRate }

    static let oui: UInt32 = 0x001C2D
    static let informationClass: UInt16 = 0x534C
    static let packetClass: UInt16 = 0x03E3
    /// 7 header words + 256 payload words.
    static let packetWords: UInt16 = 7 + UInt16(framesPerPacket * 2)

    static func packets(for audio: VoiceAudio, streamID: UInt32, startingSequence: Int) -> [Data] {
        let frames = audio.samples
        let count = max(1, Int((Double(frames.count) / Double(framesPerPacket)).rounded(.up)))
        var seq = startingSequence & 0x0F
        var out: [Data] = []
        out.reserveCapacity(count)
        for p in 0..<count {
            var d = Data(capacity: Int(packetWords) * 4)
            d.append(0x10 | 0x08)                                     // IF data w/ stream | class id
            d.append(UInt8(0xC0 | 0x10 | UInt8(seq)))                 // TSI other | TSF sample count | count
            appendBE16(&d, packetWords)
            appendBE32(&d, streamID)
            appendBE32(&d, oui)
            appendBE16(&d, informationClass)
            appendBE16(&d, packetClass)
            appendBE32(&d, 0)                                          // integer timestamp
            appendBE32(&d, 0); appendBE32(&d, 0)                       // fractional timestamp
            for i in 0..<framesPerPacket {
                let idx = p * framesPerPacket + i
                let s = idx < frames.count ? max(-1, min(1, frames[idx])) : 0
                let bits = s.bitPattern
                appendBE32(&d, bits); appendBE32(&d, bits)             // L, R
            }
            out.append(d)
            seq = (seq + 1) & 0x0F
        }
        return out
    }

    private static func appendBE16(_ d: inout Data, _ v: UInt16) { d.append(UInt8(v >> 8)); d.append(UInt8(v & 0xFF)) }
    private static func appendBE32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v >> 24)); d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8(v & 0xFF))
    }
}
```
- [ ] **Step 4: `xcodegen generate`; run — PASS.** **Step 5: Commit** — `git commit -m "flex: DAX packetizer — the VITA-49 transmit audio packet, byte for byte"`

### Task 15: `UDPSender` and `NetworkTransport`

**Files:**
- Create: `Sources/Hardware/Network/UDPSender.swift`
- Modify: `Sources/Hardware/Network/TCPTransport.swift` (conform to `NetworkTransport`, expose `hostName`)

- [ ] **Step 1: Write**
```swift
import Foundation

/// A transport that reached the radio over IP, so a driver can open a second,
/// datagram channel to the same host. `TCPTransport` conforms; a mock in tests can too.
protocol NetworkTransport: SerialTransport {
    var hostName: String { get }
}

/// What the Flex driver needs from a UDP socket, behind a protocol so tests
/// record packets instead of sending them.
protocol UDPSending: AnyObject {
    var localPort: UInt16 { get }
    func send(_ data: Data)
    func close()
}

/// A connected BSD UDP socket. Connected (not bound) so the kernel picks a
/// free local port and the sandbox's network-client entitlement suffices; the
/// port is read back with getsockname so it can be registered with the radio.
final class UDPSender: UDPSending, @unchecked Sendable {
    private let fd: Int32
    let localPort: UInt16

    enum UDPError: Error, LocalizedError {
        case resolve(String), socket(Int32), connect(Int32)
        var errorDescription: String? {
            switch self {
            case .resolve(let host): "Could not resolve \(host) for the audio stream."
            case .socket(let e), .connect(let e): "Could not open the audio stream socket: \(String(cString: strerror(e)))"
            }
        }
    }

    init(host: String, port: UInt16) throws {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM, ai_protocol: IPPROTO_UDP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else { throw UDPError.resolve(host) }
        defer { freeaddrinfo(info) }
        let s = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
        guard s >= 0 else { throw UDPError.socket(errno) }
        guard connect(s, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0 else {
            let e = errno; Darwin.close(s); throw UDPError.connect(e)
        }
        var addr = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(s, $0, &len) }
        }
        fd = s
        localPort = UInt16(bigEndian: addr.sin_port)
    }

    func send(_ data: Data) {
        data.withUnsafeBytes { buf in _ = Darwin.send(fd, buf.baseAddress, buf.count, 0) }
    }

    func close() { Darwin.close(fd) }
}
```
In `TCPTransport`: `final class TCPTransport: NetworkTransport, @unchecked Sendable`, store `let hostName: String` from `init(host:port:)`.
- [ ] **Step 2: Build; commit** — `git commit -m "flex: UDPSender and NetworkTransport"`

### Task 16: `FlexRadioDriver` streams recordings

**Files:**
- Create: `Sources/Hardware/Radio/FlexDAXStreamer.swift` (the pacing thread)
- Modify: `Sources/Hardware/Radio/FlexRadioDriver.swift`
- Test: `Tests/Hardware/FlexRadioDriverTests.swift` (append), `Tests/Hardware/FlexDAXStreamerTests.swift`

- [ ] **Step 1: Failing tests** — streamer:
```swift
import XCTest
@testable import QSOPartyLogger

final class FlexDAXStreamerTests: XCTestCase {
    final class Sink: UDPSending, @unchecked Sendable {
        let lock = NSLock(); var packets: [(Data, UInt64)] = []
        var localPort: UInt16 { 4991 }
        func send(_ data: Data) { lock.withLock { packets.append((data, DispatchTime.now().uptimeNanoseconds)) } }
        func close() {}
    }

    func testSendsEveryPacketAtTheIntervalThenReportsFinished() {
        let sink = Sink()
        let packets = (0..<6).map { Data([UInt8($0)]) }
        let done = expectation(description: "finished")
        let streamer = FlexDAXStreamer(sender: sink, intervalSeconds: 0.005)
        streamer.stream(packets, onFirstPacket: {}, onFinished: { done.fulfill() })
        wait(for: [done], timeout: 2)
        XCTAssertEqual(sink.packets.map { $0.0[0] }, [0, 1, 2, 3, 4, 5])
        let gaps = zip(sink.packets, sink.packets.dropFirst()).map { Double($1.1 - $0.1) / 1e6 }
        XCTAssertTrue(gaps.allSatisfy { $0 > 3 && $0 < 20 }, "≈5 ms apart, got \(gaps)")
    }

    func testStopEndsEarlyAndNeverReportsFinished() {
        let sink = Sink()
        let packets = (0..<200).map { Data([UInt8($0)]) }
        var finished = false
        let streamer = FlexDAXStreamer(sender: sink, intervalSeconds: 0.005)
        let started = expectation(description: "first")
        streamer.stream(packets, onFirstPacket: { started.fulfill() }, onFinished: { finished = true })
        wait(for: [started], timeout: 1)
        streamer.stop()
        let sent = sink.lock.withLock { sink.packets.count }
        usleep(50_000)
        XCTAssertEqual(sink.lock.withLock { sink.packets.count }, sent, "nothing after stop")
        XCTAssertLessThan(sent, 200)
        XCTAssertFalse(finished)
    }
}
```
Driver tests (append to `FlexRadioDriverTests`; that file's mock transport records writes — extend it to conform to `NetworkTransport` with `hostName = "10.0.0.5"`):
```swift
    // MARK: Transmit audio over DAX (see docs/research/voice_transports.md)

    final class FakeUDP: UDPSending, @unchecked Sendable {
        var localPort: UInt16 = 51234; var sent: [Data] = []; var closed = 0
        func send(_ data: Data) { sent.append(data) }
        func close() { closed += 1 }
    }

    private func connectedDriver() -> (FlexRadioDriver, MockNetworkTransport, FakeUDP) {
        let transport = MockNetworkTransport(); let udp = FakeUDP()
        let driver = FlexRadioDriver()
        driver.makeUDPSender = { host, port in
            XCTAssertEqual(host, "10.0.0.5"); XCTAssertEqual(port, 4991); return udp
        }
        driver.start(transport: transport)
        transport.feed("H1A2B3C4\n")
        transport.feed("S0|slice 0 in_use=1 RF_frequency=14.250000 mode=USB active=1 tx=1 dax=0\n")
        transport.feed("S0|transmit dax=0\n")
        transport.written = []
        return (driver, transport, udp)
    }
    private let clip = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0.1, count: 256))

    func testStartSubscribesToDAX() {
        let transport = MockNetworkTransport()
        FlexRadioDriver().start(transport: transport)
        XCTAssertTrue(transport.commands.contains("sub dax all"))
    }

    func testFirstPlaySetsUpTheStreamThenKeysStreamsAndUnkeys() {
        let (driver, transport, udp) = connectedDriver()
        var events: [TransmitAudioEvent] = []
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        XCTAssertEqual(transport.commands, ["client udpport 51234", "dax audio set 1 slice=0 tx=1", "stream create type=dax_tx"])
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|0|0x84000001\n")
        transport.feed("S1A2B3C4|stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1\n")
        // Now it keys and streams.
        let done = expectation(description: "finished")
        driver.onTransmitAudioEvent = { events.append($0); if $0 == .finished { done.fulfill() } }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(transport.commands.suffix(4), ["transmit set dax=1", "xmit 1", "xmit 0", "transmit set dax=0"])
        XCTAssertEqual(events, [.started, .finished])
        // 120 ms lead ≈ 22 packets, 2 clip packets, 100 ms tail ≈ 19 packets.
        XCTAssertGreaterThan(udp.sent.count, 40)
        XCTAssertTrue(udp.sent.allSatisfy { $0.count == 1052 })
    }

    func testSecondPlaySkipsSetup() {
        let (driver, transport, _) = connectedDriver()
        driver.transmitAudio(clip)
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|0|0x84000001\n")
        transport.feed("S1A2B3C4|stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1\n")
        let done = expectation(description: "first"); driver.onTransmitAudioEvent = { if $0 == .finished { done.fulfill() } }
        wait(for: [done], timeout: 5)
        transport.written = []
        let done2 = expectation(description: "second"); driver.onTransmitAudioEvent = { if $0 == .finished { done2.fulfill() } }
        driver.transmitAudio(clip)
        wait(for: [done2], timeout: 5)
        XCTAssertEqual(transport.commands, ["transmit set dax=1", "xmit 1", "xmit 0", "transmit set dax=0"])
    }

    func testDAXAlreadyOnIsLeftOn() {
        let (driver, transport, _) = connectedDriver()
        transport.feed("S0|transmit dax=1\n")
        driver.transmitAudio(clip)
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|0|0x84000001\n")
        transport.feed("S1A2B3C4|stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1\n")
        let done = expectation(description: "done"); driver.onTransmitAudioEvent = { if $0 == .finished { done.fulfill() } }
        wait(for: [done], timeout: 5)
        XCTAssertFalse(transport.commands.contains("transmit set dax=1"))
        XCTAssertFalse(transport.commands.contains("transmit set dax=0"))
    }

    func testTXSliceWithADAXChannelUsesItWithoutReassigning() {
        let (driver, transport, _) = connectedDriver()
        transport.feed("S0|slice 0 dax=3\n")
        driver.transmitAudio(clip)
        XCTAssertTrue(transport.commands.contains("dax audio set 3 tx=1"))
    }

    func testRefusedStreamNeverKeysAndReportsTheCode() {
        let (driver, transport, _) = connectedDriver()
        var events: [TransmitAudioEvent] = []
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|50000064|\n")
        XCTAssertEqual(events, [.failed("The radio refused the transmit audio stream (0x50000064 — no UDP port registered).")])
        XCTAssertFalse(transport.commands.contains("xmit 1"))
    }

    func testNoTXConfirmationWithinTheWindowFailsWithoutKeying() {
        let (driver, transport, _) = connectedDriver()
        driver.streamConfirmTimeout = 0.2
        let failed = expectation(description: "failed")
        driver.onTransmitAudioEvent = { if case .failed = $0 { failed.fulfill() } }
        driver.transmitAudio(clip)
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|0|0x84000001\n")
        // No `tx=1` status ever arrives.
        wait(for: [failed], timeout: 2)
        XCTAssertFalse(transport.commands.contains("xmit 1"))
    }

    func testStopMidClipUnkeysAndReportsStopped() {
        let (driver, transport, _) = connectedDriver()
        let longClip = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0.1, count: 24_000 * 3))
        var events: [TransmitAudioEvent] = []
        let started = expectation(description: "started")
        driver.onTransmitAudioEvent = { events.append($0); if $0 == .started { started.fulfill() } }
        driver.transmitAudio(longClip)
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|0|0x84000001\n")
        transport.feed("S1A2B3C4|stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1\n")
        wait(for: [started], timeout: 3)
        driver.stopTransmitAudio()
        XCTAssertEqual(transport.commands.suffix(2), ["xmit 0", "transmit set dax=0"])
        XCTAssertEqual(events, [.started, .stopped])
    }

    func testStopRemovesTheStreamAndClosesTheSocket() {
        let (driver, transport, udp) = connectedDriver()
        driver.transmitAudio(clip)
        transport.reply(to: "stream create type=dax_tx", "R\(transport.seq(of: "stream create type=dax_tx"))|0|0x84000001\n")
        driver.stop()
        XCTAssertTrue(transport.commands.contains("stream remove 0x84000001"))
        XCTAssertEqual(udp.closed, 1)
    }

    func testNoSocketUntilTheFirstPlay() {
        let transport = MockNetworkTransport(); var made = 0
        let driver = FlexRadioDriver(); driver.makeUDPSender = { _, _ in made += 1; return FakeUDP() }
        driver.start(transport: transport)
        XCTAssertEqual(made, 0)
        XCTAssertFalse(transport.commands.contains { $0.hasPrefix("client udpport") })
    }

    func testPureParsers() {
        XCTAssertEqual(FlexRadioDriver.parseHandle("H1A2B3C4"), 0x1A2B3C4)
        XCTAssertNil(FlexRadioDriver.parseHandle("V1.4.0.0"))
        let r = FlexRadioDriver.parseReply("R12|50000064|")
        XCTAssertEqual(r?.seq, 12); XCTAssertEqual(r?.code, 0x50000064); XCTAssertEqual(r?.message, "")
        XCTAssertEqual(FlexRadioDriver.parseReply("R3|0|0x84000001|OK")?.message, "0x84000001")
        let s = FlexRadioDriver.parseStreamStatus("stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1")
        XCTAssertEqual(s?.id, 0x84000001); XCTAssertEqual(s?.type, "dax_tx"); XCTAssertEqual(s?.clientHandle, 0x1A2B3C4); XCTAssertEqual(s?.tx, true)
        XCTAssertEqual(FlexRadioDriver.parseStreamStatus("stream 0x84000001 removed")?.removed, true)
        XCTAssertEqual(FlexRadioDriver.parseTransmitDAX("transmit dax=1 rfpower=50"), true)
        XCTAssertNil(FlexRadioDriver.parseTransmitDAX("transmit rfpower=50"))
        let u = FlexRadioDriver.parseSlice("slice 0 tx=1 dax=2")
        XCTAssertEqual(u?.tx, true); XCTAssertEqual(u?.daxChannel, 2)
        XCTAssertEqual(FlexRadioDriver.replyMeaning(0x50000064), "no UDP port registered")
        XCTAssertNil(FlexRadioDriver.replyMeaning(0x12345678))
    }
```
`MockNetworkTransport` (in the test file): records `written: [Data]`, `commands` = the `C<seq>|` bodies in order, `feed(_ line:)` calls `onReceive`, `seq(of:)` finds the sequence number of a command body, `reply(to:_:)` feeds the given line. `hostName = "10.0.0.5"`.

- [ ] **Step 2: Run — compile failures.**
- [ ] **Step 3: Implement `FlexDAXStreamer`**
```swift
import Foundation

/// Sends prepared packets one every `interval` on a dedicated thread with
/// absolute deadlines (the keyer's `sleepUntil` discipline), so a long clip
/// does not drift. `stop()` ends it between packets; `onFinished` is called
/// only when every packet went out.
final class FlexDAXStreamer: @unchecked Sendable {
    private let sender: any UDPSending
    private let interval: TimeInterval
    private let lock = NSLock()
    private var stopped = false
    private var thread: Thread?

    init(sender: any UDPSending, intervalSeconds: TimeInterval) {
        self.sender = sender; self.interval = intervalSeconds
    }

    func stream(_ packets: [Data], onFirstPacket: @escaping @Sendable () -> Void, onFinished: @escaping @Sendable () -> Void) {
        lock.withLock { stopped = false }
        let t = Thread { [self] in
            var deadline = DispatchTime.now().uptimeNanoseconds
            let step = UInt64(interval * 1_000_000_000)
            for (i, packet) in packets.enumerated() {
                if lock.withLock({ stopped }) { return }
                sender.send(packet)
                if i == 0 { onFirstPacket() }
                deadline += step
                sleepUntil(uptimeNanos: deadline)
            }
            if !lock.withLock({ stopped }) { onFinished() }
        }
        t.name = "org.b5n.QSOPartyLogger.dax"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() { lock.withLock { stopped = true } }

    private func sleepUntil(uptimeNanos: UInt64) {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= uptimeNanos { return }
            let remaining = uptimeNanos - now
            if remaining > 1_500_000 { usleep(UInt32((remaining - 1_000_000) / 1_000)) }
            else if remaining > 50_000 { usleep(20) }
        }
    }
}
```
- [ ] **Step 4: Implement the driver** — new stored state under the lock: `clientHandle: UInt32?`, `txSliceIndex: Int?`, `txSliceDAXChannel: Int?` (per slice: add `tx: Bool?`, `daxChannel: Int?` to `SliceState`/`SliceUpdate`), `transmitDAXOn: Bool?`, `udp: (any UDPSending)?`, `daxStreamID: UInt32?`, `daxStreamTX = false`, `pendingStreamCreateSeq: Int?`, `pendingClip: VoiceAudio?`, `streamer: FlexDAXStreamer?`, `daxWasOffBeforePlay = false`; injectables `var makeUDPSender: (String, UInt16) throws -> any UDPSending = { try UDPSender(host: $0, port: $1) }`, `var streamConfirmTimeout: TimeInterval = 2`; constants `static let daxUDPPort: UInt16 = 4991`, `static let leadSeconds = 0.12`, `static let tailSeconds = 0.10`. Command builders: `cmdClientUDPPort(_:)`, `cmdDAXAudioSetTX(channel:slice:)` → `"dax audio set \(ch)" + (slice.map { " slice=\($0)" } ?? "") + " tx=1"`, `cmdStreamCreateDAXTX = "stream create type=dax_tx"`, `cmdStreamRemove(_:)` → `"stream remove 0x\(String(id, radix: 16, uppercase: true))"`, `cmdTransmitDAX(_:)`, `cmdXmit(_:)`. Parsers as the test names them; `sendCommand` returns its sequence number. `handle(line:)`: `H` → handle; `R` → `parseReply` → if seq == pendingStreamCreateSeq: code 0 with a hex message → stream id (then `checkReadyToStream()`), non-zero → fail with `replyMeaning`; status `stream …` → if type == dax_tx and clientHandle matches (or ours is unknown) record id/tx; `transmit` → dax; slice → tx/dax. `start` adds `sub dax all`. `transmitAudio`: stop any current; store `pendingClip`; if no udp: make sender, `client udpport`, `dax audio set …`, `stream create` (record seq) and start a `streamConfirmTimeout` timer that fails if not `daxStreamTX`; else `checkReadyToStream()`. `checkReadyToStream()`: needs `daxStreamID != nil && daxStreamTX && pendingClip != nil` → build packets = silence(lead) + clip + silence(tail) via `FlexDAXPacketizer.packets(streamID:startingSequence: nextSeq)`; if `transmitDAXOn != true` → `transmit set dax=1`, remember to restore; `xmit 1`; streamer.stream(onFirstPacket: `.started` — after the lead packets? report `.started` on the first *clip* packet: simplest is `.started` on the first packet); onFinished → `xmit 0`, restore dax, `.finished`. `stopTransmitAudio`: streamer.stop(); if streaming: `xmit 0`, restore dax, `.stopped`; else if pending (setup phase): clear pending, `.stopped`. `stop()`: streamer.stop(); `stream remove` if id; udp.close(); clear all.

  `replyMeaning(_:)`: the wiki's table — `0x50000064: "no UDP port registered"`, `0x50000025: "client stream id not found"`, `0x5000002C: "incorrect number of parameters"`, `0x50000059: "invalid stream id"`, `0x5000003D: "transmit not supported in this radio"`, `0x50000042: "not ready to transmit"`, `0x50000043: "no transmitter"`, `0x50000065: "invalid DAX channel"`, else nil; failure text `"The radio refused the transmit audio stream (0x%08X%@)."` with ` — <meaning>` when known.

- [ ] **Step 5: `xcodegen generate`; run `FlexDAXStreamerTests`, `FlexRadioDriverTests`, `RadioRegistryTests` — PASS.** Then `RadioControllerRecordingTests`: add `testNetworkPathIsReadyOnAStreamingDriver` — connect with `radioID = "flex-6000"`, `tcpHost = "127.0.0.1"` (the TCP connect fails asynchronously; `isConnected` is still true), assert `voicePathStatus == .readyOverNetwork`. Whole suite green.
- [ ] **Step 6: Docs** — README "Connecting a Flex": a paragraph on phone messages over the network (nothing to wire; the app registers itself, sets DAX as the transmit source for each message and puts it back; SmartSDR's DAX button will light while a message plays; the TX slice; the first message after connect may take a moment while the stream is set up; if the radio refuses, the reason shows in the radio bar). PROVENANCE: "Radio protocols — Flex transmit audio (DAX)" bullet listing the wiki pages, FlexLib 3.2.37 excerpts, and the staff answer, with fetch dates and the OPEN QUESTIONS pointer. Test count. `docs/research/flex_smartsdr_tcpip_api_cw.txt`'s KNOWN GAP paragraph unchanged.
- [ ] **Step 7: Commit** — `git commit -m "flex: AudioStreamTransmitCapable — recordings over DAX, keyed with xmit"`

---

## Finishing

- [ ] Full suite green (summary shows `failedTests: 0`), README test count equals `totalTestCount`.
- [ ] Article 10 grep clean.
- [ ] `git log --oneline master..HEAD` shows the docs commit, the amendment, and the three behaviour commit groups.
- [ ] Merge into master with `git merge --no-ff worktree-voice-messages -m "merge: voice messages recorded on the Mac"` from the main checkout only after checking `git status` there is clean and master has not moved (`git rev-parse master` unchanged from `0c98734…`).
