import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// The Messages editor's Phone tab: where phone keys get their audio, the
/// devices and level, eight recorder rows, and the F-key mapping. Names and
/// mappings ride the sheet's draft (Save/Cancel); recordings save as they are
/// made, and the tab says so.
///
/// Radio-neutral throughout (Article 10): no maker, model, protocol or port
/// in anything drawn here — `VoicePaneKeysTests` pins the status wording.
struct VoiceMessagesPane: View {
    @Bindable var store: VoiceStore
    @Bindable var settings: AppSettings
    var radio: RadioController
    /// The connected radio's own recorder, for the source picker and the
    /// "not on this radio" marks in the F-key pickers.
    let voiceStatus: VoiceKeyerStatus
    let editMode: OperatingMode
    /// Draft accessors, so the pane never owns the sheet's draft.
    let name: (Int) -> Binding<String>          // memory index, 0-based
    let mapping: (Int) -> Binding<Int?>          // F-key index, 0-based
    let pickerCaption: (Int) -> String           // memory, 1-based
    /// Play memory N to the radio, exactly as an F-key would.
    let onPlayToRadio: (Int) -> Void

    @State private var trimming: Int?
    @State private var importing: Int?
    @State private var inputDevices: [AudioDevice] = []
    @State private var outputDevices: [AudioDevice] = []
    @State private var localError: String?
    @State private var showDetails = false

    // MARK: Pure helpers (tested)

    /// ⌘1–⌘8 record; ⌥⌘1–⌥⌘8 preview.
    nonisolated static func recordKey(memory: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(memory)))
    }

    /// The one sentence under the rows. Neutral: no maker, no model, no port.
    nonisolated static func pathText(_ path: VoicePathStatus, source: PhoneMessageSource,
                                     radioHasMemories: Bool) -> String {
        if source == .radioMemories, radioHasMemories {
            return "Phone keys play the radio's own voice memories. Switch the source above "
                + "to use these recordings."
        }
        switch path {
        case .unsupported:
            return radioHasMemories
                ? "This radio can't take audio from this Mac, so phone keys play its own "
                    + "voice memories."
                : "No radio that can take audio from this Mac is connected. Recordings can "
                    + "still be made and previewed."
        case .notReady(let reason):
            return "Recordings can't reach the radio yet: \(reason)"
        case .readyOverNetwork:
            return "Recordings play to the radio over its network connection; the radio is "
                + "keyed for each message."
        case .readyOverDevice(let name):
            return "Recordings play to the radio through \(name); PTT by radio command or "
                + "VOX, as set above."
        }
    }

    nonisolated static func durationText(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "no recording" }
        return seconds > 0 ? String(format: "%.1f s", seconds) : "silent"
    }

    // MARK: Body

    private var path: VoicePathStatus { radio.voicePathStatus }

    /// The sound-card controls apply when the path is, or could be, a device.
    private var showsDeviceControls: Bool {
        switch path {
        case .readyOverDevice, .notReady: true
        case .readyOverNetwork, .unsupported: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if voiceStatus.isReady {
                sourceRow
            }
            deviceRows
            HStack(alignment: .top, spacing: 24) {
                memoriesColumn
                fKeysColumn
            }
            footer
        }
        .onAppear(perform: refreshDevices)
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: [.audio]) { result in
            guard let memory = importing else { return }
            importing = nil
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                store.importFile(url, memory: memory)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private var sourceRow: some View {
        Picker("Phone messages play from", selection: $settings.phoneMessageSource) {
            Text("Recordings on this Mac").tag(PhoneMessageSource.recordings)
            Text("The radio's voice memories").tag(PhoneMessageSource.radioMemories)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Recordings made here are the default. The radio's own recorder stays available "
              + "wherever it reports memories.")
    }

    @ViewBuilder
    private var deviceRows: some View {
        HStack(spacing: 12) {
            Picker("Microphone", selection: $settings.voiceInputDeviceUID) {
                Text("System default").tag(String?.none)
                ForEach(inputDevices) { device in
                    Text(device.name).tag(String?.some(device.uid))
                }
            }
            .frame(maxWidth: 260)
            LevelMeter(level: store.isRecording ? store.inputLevel : 0)
                .frame(width: 80, height: 8)
                .help("Microphone level while recording")
            Slider(value: $settings.voiceLevel, in: 0...1) {
                Text("Level")
            }
            .frame(width: 180)
            .help("Transmit audio level for recordings, both to a sound card and over the network — set "
                  + "it against the radio's ALC with ⇢ Radio")
        }
        if showsDeviceControls {
            HStack(spacing: 12) {
                Picker("Radio audio out", selection: $settings.voiceOutputDeviceUID) {
                    Text("Not chosen").tag(String?.none)
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                }
                .frame(maxWidth: 260)
                .onChange(of: settings.voiceOutputDeviceUID) { radio.refreshVoicePath(settings: settings) }
                Picker("PTT", selection: $settings.voicePTT) {
                    Text("Radio command").tag(VoicePTTMode.radioCommand)
                    Text("VOX").tag(VoicePTTMode.vox)
                }
                .frame(maxWidth: 220)
                .onChange(of: settings.voicePTT) { radio.refreshVoicePath(settings: settings) }
                Stepper(value: $settings.voicePTTLeadMs, in: 0...500, step: 10) {
                    Text("Lead \(settings.voicePTTLeadMs) ms")
                        .monospacedDigit()
                }
                .disabled(settings.voicePTT != .radioCommand)
                .help("Silence between keying the radio and the first sample")
            }
        }
    }

    private var memoriesColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice memories — recorded here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                ForEach(1...MessageSets.voiceMemorySlots, id: \.self) { memory in
                    memoryRow(memory)
                }
            }
        }
    }

    private func memoryRow(_ memory: Int) -> some View {
        let clip = store.set[memory]
        let recordingThis = store.recordingMemory == memory
        return GridRow {
            Text("M\(memory)")
                .font(.callout.weight(.bold))
                .frame(width: 30, alignment: .trailing)
            TextField("", text: name(memory - 1))
                .frame(width: 100)
            WaveformView(bins: store.waveforms[memory], recording: recordingThis, level: store.inputLevel)
                .frame(width: 110, height: 22)
            Text(recordingThis
                 ? String(format: "%.1f s", store.recordingElapsed)
                 : Self.durationText(clip?.trimmedDuration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            HStack(spacing: 2) {
                Button {
                    toggleRecord(memory)
                } label: {
                    Image(systemName: recordingThis ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(recordingThis ? .red : .primary)
                }
                .keyboardShortcut(Self.recordKey(memory: memory), modifiers: .command)
                .help(recordingThis ? "Stop recording (⌘\(memory), Space or Return)"
                                    : "Record M\(memory) (⌘\(memory)); press again to stop. Stops by itself after 30 s.")
                .shortcutHint("⌘\(memory)")

                Button {
                    if store.previewingMemory == memory { store.stopPreview() } else { store.preview(memory: memory) }
                } label: {
                    Image(systemName: store.previewingMemory == memory ? "stop.fill" : "play.fill")
                }
                .keyboardShortcut(Self.recordKey(memory: memory), modifiers: [.command, .option])
                .disabled(store.rendered[memory] == nil)
                .help("Play M\(memory) on this Mac (⌥⌘\(memory))")
                .shortcutHint("⌥⌘\(memory)")

                Button {
                    trimming = memory
                } label: {
                    Image(systemName: "scissors")
                }
                .disabled(clip == nil)
                .help("Trim, auto-trim, normalize")
                .popover(isPresented: Binding(get: { trimming == memory }, set: { if !$0 { trimming = nil } })) {
                    VoiceTrimPopover(store: store, memory: memory)
                }

                Button {
                    onPlayToRadio(memory)
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                .disabled(!path.isReady || store.rendered[memory] == nil)
                .help("Play M\(memory) to the radio — keys the transmitter, exactly as the F-key does")

                Menu {
                    Button("Import…") { importing = memory }
                    Button("Reveal in Finder") { reveal(memory) }
                        .disabled(clip == nil)
                    Divider()
                    Button("Delete", role: .destructive) { store.delete(memory: memory) }
                        .disabled(clip == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.borderless)
        }
    }

    private var fKeysColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("F-keys — which memory each one plays")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(0..<MessagesDraft.slotCount, id: \.self) { index in
                    GridRow {
                        Text("F\(index + 1)")
                            .font(.callout.weight(.bold))
                            .frame(width: 30, alignment: .trailing)
                        Picker("", selection: mapping(index)) {
                            Text("—").tag(Int?.none)
                            ForEach(1...MessageSets.voiceMemorySlots, id: \.self) { memory in
                                Text(pickerCaption(memory)).tag(Int?.some(memory))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200, alignment: .leading)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                let others = store.partiesWithRecordings.filter { $0 != store.partyID }
                Menu("Copy from another party…") {
                    ForEach(others, id: \.self) { party in
                        Button(party.uppercased()) { store.copyMissing(from: party) }
                    }
                }
                .fixedSize()
                .disabled(others.isEmpty)
                .help("Fill this party's empty memories from another party's recordings — TU, AGN? and 73 are the same everywhere")
                Text("Recordings save as you make them; names and F-keys save with the sheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(Self.pathText(path, source: settings.phoneMessageSource, radioHasMemories: voiceStatus.isReady))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.locationText(store.locationDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = localError ?? store.lastError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if path == .readyOverNetwork {
                DisclosureGroup("Details — what the radio said", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScrollView {
                            Text(radio.voiceLog.isEmpty ? "Nothing yet — play a memory to the radio."
                                                        : radio.voiceLog.joined(separator: "\n"))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        HStack {
                            Button("Refresh") { radio.refreshVoiceLog() }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(radio.voiceLog.joined(separator: "\n"), forType: .string)
                            }
                            .disabled(radio.voiceLog.isEmpty)
                        }
                        .controlSize(.small)
                    }
                }
                .font(.caption)
                .onChange(of: showDetails) { if showDetails { radio.refreshVoiceLog() } }
            }
        }
    }

    /// Where the files are, and whether the other Macs see them.
    nonisolated static func locationText(_ location: VoiceStore.Location) -> String {
        switch location {
        case .cloudFolder(let path):
            "Recordings live in your iCloud folder (\(path)/Voice), so your other Macs see them once "
                + "iCloud has synced."
        case .thisMac:
            "Recordings live on this Mac only. Choose an iCloud folder (toolbar → iCloud) and they move "
                + "there, for your other Macs."
        }
    }

    // MARK: Actions

    private func refreshDevices() {
        inputDevices = AudioDevices.inputDevices()
        outputDevices = AudioDevices.outputDevices()
    }

    private func toggleRecord(_ memory: Int) {
        if store.recordingMemory == memory {
            store.stopRecording()
            return
        }
        localError = nil
        Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                localError = "Microphone access is off. Allow it in System Settings → Privacy & Security → "
                    + "Microphone → QSO Party Logger, then record again."
                return
            }
            do {
                try store.record(memory: memory, inputDeviceUID: settings.voiceInputDeviceUID)
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func reveal(_ memory: Int) {
        guard let clip = store.set[memory], let partyID = store.partyID else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.library.fileURL(partyID: partyID, fileName: clip.fileName)])
    }
}

/// A capsule that fills with the level — the microphone meter.
struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level > 0.9 ? Color.red : level > 0.6 ? Color.orange : Color.green)
                    .frame(width: max(0, geometry.size.width * CGFloat(min(1, level))))
            }
        }
        .accessibilityLabel("Level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// The trimmed clip's peaks as bars; a live level bar while recording.
struct WaveformView: View {
    let bins: [Float]?
    let recording: Bool
    let level: Float

    var body: some View {
        Canvas { context, size in
            let background = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3)
            context.fill(background, with: .color(.primary.opacity(0.06)))
            if recording {
                let width = size.width * CGFloat(min(1, level))
                context.fill(Path(CGRect(x: 0, y: 0, width: width, height: size.height)),
                             with: .color(.red.opacity(0.7)))
                return
            }
            guard let bins, !bins.isEmpty else { return }
            let step = size.width / CGFloat(bins.count)
            for (i, peak) in bins.enumerated() {
                let h = max(1, CGFloat(min(1, peak)) * size.height)
                let rect = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: max(1, step - 1), height: h)
                context.fill(Path(rect), with: .color(.accentColor.opacity(0.8)))
            }
        }
    }
}
