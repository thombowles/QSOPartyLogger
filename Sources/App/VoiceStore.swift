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
    /// The auto-trim's threshold: this far under the clip's own peak, judged
    /// over 10 ms windows, never lower than the floor — so breath and room
    /// noise before the first word are trimmed, and a quiet recording is not
    /// mistaken for a voice.
    nonisolated static let autoTrimRelativeToPeakDB: Float = 25
    nonisolated static let autoTrimFloorDB: Float = -45
    nonisolated static let autoTrimWindow: TimeInterval = 0.01
    /// Read by the render task off the main actor, hence `nonisolated`.
    nonisolated static let waveformBins = 96

    /// Where the recordings live: the operator's iCloud folder when one is
    /// chosen (so the other Macs see them), else this Mac's Application
    /// Support. Re-evaluated on every reload, so choosing a folder later
    /// moves them there.
    enum Location: Equatable, Sendable {
        case cloudFolder(path: String)
        case thisMac
    }

    private(set) var library: VoiceLibrary
    private(set) var location: Location
    /// A library handed in (tests) is never relocated.
    private let pinnedLibrary: Bool
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

    /// `library` nil = follow the iCloud folder setting (the app); a library
    /// given (tests) is used as-is and never relocated.
    init(library: VoiceLibrary? = nil,
         makeRecorder: @escaping () -> any VoiceRecording = { EngineVoiceRecorder() }) {
        if let library {
            self.library = library
            self.location = .thisMac
            self.pinnedLibrary = true
        } else {
            let preferred = Self.preferredLibrary()
            self.library = preferred.library
            self.location = preferred.location
            self.pinnedLibrary = false
        }
        self.makeRecorder = makeRecorder
    }

    /// The iCloud folder's `Voice` subfolder when one is chosen, else this
    /// Mac's Application Support.
    private static func preferredLibrary() -> (library: VoiceLibrary, location: Location) {
        if let cloud = CloudMirror.activeFolder() {
            return (VoiceLibrary(folder: cloud.appendingPathComponent("Voice", isDirectory: true)),
                    .cloudFolder(path: CloudMirror.folderDisplayPath ?? cloud.path))
        }
        return (VoiceLibrary(folder: VoiceLibrary.defaultFolder), .thisMac)
    }

    /// The location may have changed since the last look (an iCloud folder
    /// chosen mid-session): switch to it, and bring the sets this Mac already
    /// holds along — once, whole, never overwriting a set the folder has.
    private func relocateIfNeeded() {
        guard !pinnedLibrary else { return }
        let preferred = Self.preferredLibrary()
        library = preferred.library
        location = preferred.location
        let legacy = VoiceLibrary(folder: VoiceLibrary.defaultFolder)
        guard library.folder != legacy.folder else { return }
        do {
            _ = try library.adoptSets(from: legacy)
        } catch {
            lastError = "Couldn't move the recordings to the iCloud folder: \(error.localizedDescription)"
        }
    }

    /// Party ids with recordings, for the "Copy from…" menu.
    var partiesWithRecordings: [String] { library.partiesWithRecordings() }

    /// The folder the files are in, for the tab and for Reveal in Finder.
    var locationDescription: Location { location }

    // MARK: Loading and rendering

    func reload() {
        renderTask?.cancel()
        rendered = [:]
        waveforms = [:]
        lastError = nil
        relocateIfNeeded()
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
            var missing = 0
            for (memory, clip) in set.clips {
                if Task.isCancelled { return }
                let url = library.fileURL(partyID: partyID, fileName: clip.fileName)
                guard let audio = try? AudioFileIO.read(url) else {
                    // Not there yet — iCloud may still be bringing it down.
                    library.requestDownloadIfPlaceholder(url)
                    missing += 1
                    continue
                }
                let cut = audio.trimmed(from: clip.trimStart, to: clip.trimEnd).applyingGain(dB: clip.gainDB)
                out[memory] = cut
                waves[memory] = cut.waveform(bins: VoiceStore.waveformBins)
            }
            let rendered = out
            let waveforms = waves
            let retry = missing > 0
            await MainActor.run { [weak self] in
                guard let self, self.partyID == partyID, !Task.isCancelled else { return }
                self.rendered = rendered
                self.waveforms = waveforms
                // One more look a few seconds later, for files iCloud is
                // still downloading; after that the operator reopens the tab.
                if retry, self.renderRetries < 3 {
                    self.renderRetries += 1
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        guard let self, self.partyID == partyID else { return }
                        self.renderAll()
                    }
                } else if !retry {
                    self.renderRetries = 0
                }
            }
        }
    }

    private var renderRetries = 0

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
        let voiced = audio.voicedRange(relativeToPeakDB: Self.autoTrimRelativeToPeakDB, floorDB: Self.autoTrimFloorDB,
                                        window: Self.autoTrimWindow, pad: Self.autoTrimPad)
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
        let range = audio.voicedRange(relativeToPeakDB: Self.autoTrimRelativeToPeakDB, floorDB: Self.autoTrimFloorDB,
                                        window: Self.autoTrimWindow, pad: Self.autoTrimPad)
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
