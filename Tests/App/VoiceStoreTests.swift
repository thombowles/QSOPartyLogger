import XCTest
@testable import QSOPartyLogger

/// The store behind the Phone tab: recording writes, trims and renders; a
/// party change reloads; edits persist; copy-from fills the gaps. A fake
/// recorder stands in for the microphone; the files are real WAVs in a temp
/// folder, written and read through `AudioFileIO`.
@MainActor
final class VoiceStoreTests: XCTestCase {

    final class FakeRecorder: VoiceRecording, @unchecked Sendable {
        var started = 0
        var result: VoiceAudio?
        var lastDevice: String??
        var onLevel: (@Sendable (Float, TimeInterval) -> Void)?
        var onFull: (@Sendable () -> Void)?

        func start(deviceUID: String?, maxSeconds: TimeInterval,
                   onLevel: @escaping @Sendable (Float, TimeInterval) -> Void,
                   onFull: @escaping @Sendable () -> Void) throws {
            started += 1
            lastDevice = .some(deviceUID)
            self.onLevel = onLevel
            self.onFull = onFull
        }

        func stop() -> VoiceAudio? { result }
    }

    nonisolated(unsafe) private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func tone(seconds: Double) -> VoiceAudio {
        VoiceAudio(sampleRate: 48_000, samples: (0..<Int(seconds * 48_000)).map { 0.5 * sinf(Float($0) * 0.13) })
    }

    /// Rendering happens off the main actor; wait, bounded, for a memory to land.
    private func waitForRender(_ store: VoiceStore, memory: Int, present: Bool = true, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while (store.rendered[memory] != nil) != present, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: Recording

    func testRecordingWritesTrimsAndRenders() async throws {
        let recorder = FakeRecorder()
        // 0.3 s silence, 0.4 s tone, 0.3 s silence.
        var s = [Float](repeating: 0, count: 14_400)
        s += tone(seconds: 0.4).samples
        s += [Float](repeating: 0, count: 14_400)
        recorder.result = VoiceAudio(sampleRate: 48_000, samples: s)
        let store = VoiceStore(library: VoiceLibrary(folder: folder), makeRecorder: { recorder })
        store.partyID = "txqp"

        try store.record(memory: 2, inputDeviceUID: "mic-9")
        XCTAssertTrue(store.isRecording)
        XCTAssertEqual(store.recordingMemory, 2)
        XCTAssertEqual(recorder.lastDevice, .some("mic-9"))
        recorder.onLevel?(0.7, 0.25)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.inputLevel, 0.7)
        XCTAssertEqual(store.recordingElapsed, 0.25)

        store.stopRecording()
        XCTAssertFalse(store.isRecording)
        XCTAssertNil(store.recordingMemory)
        let clip = try XCTUnwrap(store.set[2])
        XCTAssertEqual(clip.duration, 1.0, accuracy: 1e-6)
        XCTAssertEqual(clip.trimStart, 0.3 - VoiceStore.autoTrimPad, accuracy: 0.01, "auto-trimmed with pad")
        XCTAssertEqual(clip.trimEnd, 0.7 + VoiceStore.autoTrimPad, accuracy: 0.01)
        XCTAssertEqual(clip.fileName, "M2.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("txqp/M2.wav").path))
        // Persisted at once — the sidecar keeps whole seconds on the date, so
        // compare what the row and the player read.
        let persisted = try XCTUnwrap(VoiceLibrary(folder: folder).load(partyID: "txqp")[2])
        XCTAssertEqual(persisted.fileName, clip.fileName)
        XCTAssertEqual(persisted.trimStart, clip.trimStart)
        XCTAssertEqual(persisted.trimEnd, clip.trimEnd)
        XCTAssertEqual(persisted.duration, clip.duration)
        await waitForRender(store, memory: 2)
        XCTAssertEqual(store.rendered[2]!.duration, clip.trimmedDuration, accuracy: 0.002)
    }

    func testTheRecorderFillingUpStopsTheRecording() async throws {
        let recorder = FakeRecorder()
        recorder.result = tone(seconds: 0.2)
        let store = VoiceStore(library: VoiceLibrary(folder: folder), makeRecorder: { recorder })
        store.partyID = "txqp"
        try store.record(memory: 1, inputDeviceUID: nil)
        recorder.onFull?()
        let deadline = Date().addingTimeInterval(2)
        while store.isRecording, Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(store.isRecording)
        XCTAssertNotNil(store.set[1])
    }

    func testAnEmptyCaptureRecordsNothing() throws {
        let recorder = FakeRecorder()
        recorder.result = nil
        let store = VoiceStore(library: VoiceLibrary(folder: folder), makeRecorder: { recorder })
        store.partyID = "txqp"
        try store.record(memory: 1, inputDeviceUID: nil)
        store.stopRecording()
        XCTAssertNil(store.set[1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("txqp/M1.wav").path))
    }

    // MARK: Loading and rendering

    func testReloadOnPartyChangeAndTrimGainRenderThrough() async throws {
        let library = VoiceLibrary(folder: folder)
        try AudioFileIO.write(tone(seconds: 2), to: library.fileURL(partyID: "alqp", fileName: "M1.wav"))
        var set = VoiceMessageSet()
        set[1] = VoiceClip(fileName: "M1.wav", duration: 2, trimStart: 0.5, trimEnd: 1.5,
                           gainDB: -6.0206, recordedAt: Date())
        try library.save(set, partyID: "alqp")

        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "alqp"
        await waitForRender(store, memory: 1)
        XCTAssertEqual(store.rendered[1]!.duration, 1.0, accuracy: 1e-3)
        XCTAssertEqual(store.rendered[1]!.peak, 0.25, accuracy: 0.02)
        XCTAssertEqual(store.waveforms[1]?.count, VoiceStore.waveformBins)

        store.partyID = "txqp"
        XCTAssertTrue(store.set.isEmpty)
        XCTAssertTrue(store.rendered.isEmpty)
        XCTAssertTrue(store.waveforms.isEmpty)
    }

    func testAnUnreadableSidecarIsReportedNotReplaced() throws {
        let library = VoiceLibrary(folder: folder)
        try FileManager.default.createDirectory(at: library.setFolder(partyID: "alqp"), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: library.sidecarURL(partyID: "alqp"))
        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "alqp"
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.set.isEmpty)
        XCTAssertEqual(try String(contentsOf: library.sidecarURL(partyID: "alqp"), encoding: .utf8), "nope")
    }

    // MARK: Editing

    func testEditsPersistAndDeleteRemoves() async throws {
        let library = VoiceLibrary(folder: folder)
        try AudioFileIO.write(tone(seconds: 1), to: library.fileURL(partyID: "alqp", fileName: "M4.wav"))
        var set = VoiceMessageSet()
        set[4] = VoiceClip(fileName: "M4.wav", duration: 1, trimStart: 0, trimEnd: 1, gainDB: 0, recordedAt: Date())
        try library.save(set, partyID: "alqp")
        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "alqp"
        await waitForRender(store, memory: 4)

        store.setTrim(memory: 4, start: 0.2, end: 0.6)
        XCTAssertEqual(try library.load(partyID: "alqp")[4]?.trimStart, 0.2)
        XCTAssertEqual(try library.load(partyID: "alqp")[4]?.trimEnd, 0.6)
        store.setTrim(memory: 4, start: 0.9, end: 0.1)
        XCTAssertEqual(store.set[4]?.trimmedDuration, 0, "an inverted trim collapses rather than inverting")

        store.setTrim(memory: 4, start: 0, end: 1)
        store.normalize(memory: 4)
        XCTAssertEqual(try library.load(partyID: "alqp")[4]?.gainDB ?? 0, 5.02, accuracy: 0.1, "0.5 peak → −1 dBFS")
        store.setGain(memory: 4, dB: -3)
        XCTAssertEqual(store.set[4]?.gainDB, -3)

        store.autoTrim(memory: 4)
        XCTAssertEqual(store.set[4]?.trimStart ?? 9, 0, accuracy: 1e-6, "a tone from the top has nothing to trim")

        XCTAssertNotNil(store.fullAudio(memory: 4))
        store.delete(memory: 4)
        XCTAssertNil(store.set[4])
        XCTAssertNil(try library.load(partyID: "alqp")[4])
        XCTAssertNil(store.rendered[4])
        XCTAssertNil(store.fullAudio(memory: 4))
    }

    func testImportResamplesAndRegisters() async throws {
        let library = VoiceLibrary(folder: folder)
        let source = folder.appendingPathComponent("import-src.wav")
        try AudioFileIO.write(VoiceAudio(sampleRate: 44_100, samples: (0..<44_100).map { 0.3 * sinf(Float($0) * 0.2) }), to: source)
        let store = VoiceStore(library: library, makeRecorder: { FakeRecorder() })
        store.partyID = "txqp"
        store.importFile(source, memory: 6)
        let clip = try XCTUnwrap(store.set[6])
        XCTAssertEqual(clip.duration, 1, accuracy: 0.01)
        XCTAssertEqual(try AudioFileIO.read(library.fileURL(partyID: "txqp", fileName: "M6.wav")).sampleRate,
                       AudioFileIO.recordingSampleRate)
        await waitForRender(store, memory: 6)
        XCTAssertNotNil(store.rendered[6])
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
        XCTAssertEqual(store.copyMissing(from: "alqp"), 0, "nothing left to fill")
    }
}
