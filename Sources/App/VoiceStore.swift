import Foundation
import Observation

/// The active party's recordings, for the editor and the flow: the set on
/// disk, each clip rendered (trim + gain) in memory, waveforms for the rows,
/// and the recorder/preview glue. One per document window.
///
/// Recordings save as they are made — this is not part of the Messages
/// editor's Save/Cancel draft. A recording is an action, like Locate in
/// Contest Setup, and the file on disk is the operator's work the moment the
/// red button stops.
@MainActor
@Observable
final class VoiceStore {
    nonisolated static let maxRecordingSeconds: TimeInterval = 30
    /// What the auto-trim keeps on each side of the voice, so a clip does not
    /// start mid-consonant.
    nonisolated static let autoTrimPad: TimeInterval = 0.12
    nonisolated static let autoTrimThresholdDB: Float = -40
    /// Read by the render task off the main actor, hence `nonisolated`.
    nonisolated static let waveformBins = 96

    let library: VoiceLibrary
    private let makeRecorder: () -> any VoiceRecording
    private var recorder: (any VoiceRecording)?
    private var previewOutput: (any AudioOutput)?

    /// The party whose set this is. Setting it reloads; nil empties.
    var partyID: String? {
        didSet { if partyID != oldValue { reload() } }
    }
    private(set) var set = VoiceMessageSet()
    /// Memory number → the clip as it will go on the air (trimmed, gained).
    private(set) var rendered: [Int: VoiceAudio] = [:]
    private(set) var waveforms: [Int: [Float]] = [:]
    /// The last thing that went wrong, for the tab's inline line. Cleared by
    /// the next thing that goes right.
    private(set) var lastError: String?

    private(set) var isRecording = false
    private(set) var recordingMemory: Int?
    /// The microphone's latest peak, 0…1, while recording.
    private(set) var inputLevel: Float = 0
    private(set) var recordingElapsed: TimeInterval = 0
    private(set) var previewingMemory: Int?

    private var renderTask: Task<Void, Never>?

    init(library: VoiceLibrary = VoiceLibrary(folder: VoiceLibrary.defaultFolder),
         makeRecorder: @escaping () -> any VoiceRecording = { EngineVoiceRecorder() }) {
        self.library = library
        self.makeRecorder = makeRecorder
    }

    /// Party ids with recordings, for the "Copy from…" menu.
    var partiesWithRecordings: [String] { library.partiesWithRecordings() }

    // MARK: Loading and rendering

    func reload() {
        renderTask?.cancel()
        rendered = [:]
        waveforms = [:]
        lastError = nil
        guard let partyID else {
            set = VoiceMessageSet()
            return
        }
        do {
            set = try library.load(partyID: partyID)
        } catch {
            set = VoiceMessageSet()
            lastError = "Couldn't read this party's recordings: \(error.localizedDescription)"
        }
        renderAll()
    }

    /// Read, trim and gain every clip off the main actor, then publish the
    /// lot at once. A party change mid-render is detected by the tag.
    private func renderAll() {
        renderTask?.cancel()
        guard let partyID else { return }
        let library = self.library
        let set = self.set
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            var out: [Int: VoiceAudio] = [:]
            var waves: [Int: [Float]] = [:]
            for (memory, clip) in set.clips {
                if Task.isCancelled { return }
                guard let audio = try? AudioFileIO.read(library.fileURL(partyID: partyID, fileName: clip.fileName))
                else { continue }
                let cut = audio.trimmed(from: clip.trimStart, to: clip.trimEnd).applyingGain(dB: clip.gainDB)
                out[memory] = cut
                waves[memory] = cut.waveform(bins: VoiceStore.waveformBins)
            }
            let rendered = out
            let waveforms = waves
            await MainActor.run { [weak self] in
                guard let self, self.partyID == partyID, !Task.isCancelled else { return }
                self.rendered = rendered
                self.waveforms = waveforms
            }
        }
    }

    private func persist() {
        guard let partyID else { return }
        do {
            try library.save(set, partyID: partyID)
            lastError = nil
        } catch {
            lastError = "Couldn't save the recordings: \(error.localizedDescription)"
        }
    }

    // MARK: Recording

    /// Start recording into `memory`. Throws when the microphone cannot be
    /// opened; the tab shows the reason.
    func record(memory: Int, inputDeviceUID: String?) throws {
        stopPreview()
        if isRecording { stopRecording() }
        let recorder = makeRecorder()
        try recorder.start(
            deviceUID: inputDeviceUID, maxSeconds: Self.maxRecordingSeconds,
            onLevel: { [weak self] level, elapsed in
                Task { @MainActor [weak self] in
                    self?.inputLevel = level
                    self?.recordingElapsed = elapsed
                }
            },
            onFull: { [weak self] in
                Task { @MainActor [weak self] in self?.stopRecording() }
            }
        )
        self.recorder = recorder
        isRecording = true
        recordingMemory = memory
        inputLevel = 0
        recordingElapsed = 0
    }

    /// Stop, write the WAV, auto-trim, register the clip and re-render.
    func stopRecording() {
        guard isRecording, let memory = recordingMemory else { return }
        let audio = recorder?.stop()
        recorder = nil
        isRecording = false
        recordingMemory = nil
        inputLevel = 0
        guard let partyID, let audio, !audio.isEmpty else { return }
        let fileName = VoiceLibrary.fileName(memory: memory)
        do {
            try AudioFileIO.write(audio, to: library.fileURL(partyID: partyID, fileName: fileName))
        } catch {
            lastError = "Couldn't save the recording: \(error.localizedDescription)"
            return
        }
        // A silent capture keeps the whole clip; the row will say so.
        let voiced = audio.voicedRange(thresholdDB: Self.autoTrimThresholdDB, pad: Self.autoTrimPad)
        set[memory] = VoiceClip(
            fileName: fileName, duration: audio.duration,
            trimStart: voiced?.lowerBound ?? 0, trimEnd: voiced?.upperBound ?? audio.duration,
            gainDB: 0, recordedAt: Date()
        )
        persist()
        renderAll()
    }

    // MARK: Editing

    func setTrim(memory: Int, start: TimeInterval, end: TimeInterval) {
        guard var clip = set[memory] else { return }
        clip.trimStart = max(0, min(clip.duration, start))
        clip.trimEnd = max(clip.trimStart, min(clip.duration, end))
        set[memory] = clip
        persist()
        renderAll()
    }

    func setGain(memory: Int, dB: Float) {
        guard var clip = set[memory] else { return }
        clip.gainDB = dB
        set[memory] = clip
        persist()
        renderAll()
    }

    /// Peak of the trimmed clip to −1 dBFS.
    func normalize(memory: Int) {
        guard let clip = set[memory], let audio = fullAudio(memory: memory) else { return }
        setGain(memory: memory,
                dB: audio.trimmed(from: clip.trimStart, to: clip.trimEnd).normalizationGainDB(targetDB: -1))
    }

    /// Redo the silence trim on the whole file.
    func autoTrim(memory: Int) {
        guard set[memory] != nil, let audio = fullAudio(memory: memory) else { return }
        let range = audio.voicedRange(thresholdDB: Self.autoTrimThresholdDB, pad: Self.autoTrimPad)
        setTrim(memory: memory, start: range?.lowerBound ?? 0, end: range?.upperBound ?? audio.duration)
    }

    func delete(memory: Int) {
        guard let partyID else { return }
        do {
            try library.remove(memory: memory, partyID: partyID)
        } catch {
            lastError = error.localizedDescription
        }
        set[memory] = nil
        rendered[memory] = nil
        waveforms[memory] = nil
    }

    /// Any file `AVAudioFile` reads, converted to the recording rate and
    /// registered untrimmed — the operator trims what they imported.
    func importFile(_ url: URL, memory: Int) {
        guard let partyID else { return }
        do {
            let audio = try AudioFileIO.read(url)
            let fileName = VoiceLibrary.fileName(memory: memory)
            try AudioFileIO.write(try AudioResampler.resample(audio, to: AudioFileIO.recordingSampleRate),
                                  to: library.fileURL(partyID: partyID, fileName: fileName))
            set[memory] = VoiceClip(fileName: fileName, duration: audio.duration, trimStart: 0,
                                    trimEnd: audio.duration, gainDB: 0, recordedAt: Date())
            persist()
            renderAll()
        } catch {
            lastError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Fill this party's empty memories from another party's set. Returns how
    /// many were copied.
    @discardableResult
    func copyMissing(from source: String) -> Int {
        guard let partyID else { return 0 }
        do {
            let copied = try library.copyMissing(from: source, to: partyID)
            if copied > 0 { reload() }
            return copied
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    /// The whole file, untrimmed and ungained — what the trim popover draws.
    func fullAudio(memory: Int) -> VoiceAudio? {
        guard let clip = set[memory], let partyID else { return nil }
        return try? AudioFileIO.read(library.fileURL(partyID: partyID, fileName: clip.fileName))
    }

    // MARK: Preview on the Mac

    /// Play the rendered clip on the system default output — the operator's
    /// speakers, never the radio.
    func preview(memory: Int) {
        stopPreview()
        guard let audio = rendered[memory] else { return }
        let output = EngineAudioOutput()
        previewOutput = output
        previewingMemory = memory
        do {
            try output.start(audio, deviceUID: nil, gain: 1) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.previewOutput === output else { return }
                    self.previewingMemory = nil
                    self.previewOutput = nil
                }
            }
        } catch {
            previewingMemory = nil
            previewOutput = nil
            lastError = error.localizedDescription
        }
    }

    func stopPreview() {
        previewOutput?.stop()
        previewOutput = nil
        previewingMemory = nil
    }
}
