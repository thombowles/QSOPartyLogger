import Foundation
import Observation

/// Where the radio link stands, as one value the radio bar can render.
/// Top-level (not nested in `RadioController`) so nonisolated UI helpers can
/// touch it — a type nested in a `@MainActor` class inherits the isolation.
enum RadioConnectionPhase: Sendable {
    /// No transport. The button reads "Connect".
    case disconnected
    /// Transport is up, nothing heard yet, validation clock still running.
    case waitingForRadio
    /// The validation window elapsed without a word from the radio. The
    /// link stays up — a late answer still promotes to `.connected`.
    case unresponsive
    /// The radio has actually answered — the only state that earns
    /// a "Disconnect" button.
    case connected
}

/// A connection problem, shaped for the radio bar: `summary` fits inline,
/// `detail` feeds the tooltip.
struct RadioConnectionError: Equatable, Sendable {
    var summary: String
    var detail: String
}

/// Whether recordings on this Mac can reach the connected radio, and how.
/// Top-level for the same reason `RadioConnectionPhase` is: the editor's
/// status wording is a nonisolated pure function of it.
enum VoicePathStatus: Equatable, Sendable {
    /// This radio takes no audio from the Mac. Phone keys use its own
    /// memories if it has any, and the editor says so.
    case unsupported
    /// Supported, but not set up — the reason is what the operator must fix.
    case notReady(reason: String)
    /// Ready over the radio's own network connection.
    case readyOverNetwork
    /// Ready through a sound card, to the named output device.
    case readyOverDevice(name: String)

    var isReady: Bool {
        switch self {
        case .readyOverNetwork, .readyOverDevice: true
        case .unsupported, .notReady: false
        }
    }
}

/// Glue between the hardware layer and SwiftUI: connection lifecycle, live
/// radio state, and CW sending over the selected backend.
@MainActor
@Observable
final class RadioController {

    typealias ConnectionPhase = RadioConnectionPhase
    typealias ConnectionError = RadioConnectionError

    private(set) var isConnected = false
    private(set) var radioState: RadioState?
    private(set) var lastError: ConnectionError?
    /// How long a silent radio gets before `.unresponsive` — app-layer
    /// policy, not a per-radio constant. Tunable so tests need not wait 4 s.
    var validationWindow: TimeInterval = 4
    /// Set by the validation task when the window closes unanswered.
    private var validationExpired = false

    /// The error shown when the validation window closes unanswered —
    /// separated out so the wording is testable without a transport.
    static func unresponsiveError(target: String, isNetwork: Bool) -> ConnectionError {
        let networkHint = isNetwork
            ? " If macOS asked about finding devices on the local network, allow it (System "
                + "Settings → Privacy & Security → Local Network → QSO Party Logger)."
            : ""
        return ConnectionError(
            summary: "Radio not answering",
            detail: "Connected to \(target), but the radio isn't answering. "
                + "Check power, cable/network, and settings. The connection stays up — the "
                + "frequency display will light up as soon as the radio responds.\(networkHint)"
        )
    }

    /// Pure phase derivation — the truth table behind `connectionPhase`.
    /// A radio that has answered is connected even if the validation clock
    /// ran out first: a late answer wins.
    static func phase(
        transportUp: Bool, radioAnswered: Bool, validationExpired: Bool
    ) -> ConnectionPhase {
        guard transportUp else { return .disconnected }
        if radioAnswered { return .connected }
        return validationExpired ? .unresponsive : .waitingForRadio
    }

    var connectionPhase: ConnectionPhase {
        Self.phase(
            transportUp: isConnected,
            radioAnswered: radioState != nil,
            validationExpired: validationExpired
        )
    }
    private(set) var nowSending: String?
    /// Keyer speed the radio last reported (its front-panel speed knob) —
    /// observed by the UI to sync `AppSettings.wpm`.
    private(set) var radioReportedWPM: Int?
    /// What the connected radio can do about voice memories. `.unsupported`
    /// until a driver says otherwise, which is the honest default: a driver
    /// that does not conform never reports, and never claims a capability.
    private(set) var voiceStatus: VoiceKeyerStatus = .unsupported
    /// True while the radio reports a voice message actually playing.
    private(set) var isVoicePlaying = false
    /// The message bank the radio was last observed in, or nil on a radio with
    /// no banks. Shown rather than corrected: the app leaves the bank where the
    /// last play put it, which changes what the front panel's buttons address.
    private(set) var voiceBank: Int?

    /// Whether recordings on this Mac can reach the connected radio, and how.
    /// `.unsupported` until a driver offers a path — the same honest default
    /// as `voiceStatus`.
    private(set) var voicePathStatus: VoicePathStatus = .unsupported
    /// Built per play so a stale engine never survives a device change; tests
    /// hand in a fake.
    var makeVoicePlayer: () -> any VoicePlaying = { VoicePlayer(output: EngineAudioOutput()) }
    /// UID → the device's name if it is present now. Tests inject; the app
    /// asks CoreAudio.
    var resolveOutputDevice: (String) -> String? = { AudioDevices.device(uid: $0)?.name }
    /// The reason shown while the sound-card path has no device chosen.
    static let chooseOutputReason = "Choose the radio's audio output in Messages → Phone."

    var availablePorts: [SerialPortInfo] = []

    private var transport: (any SerialTransport)?
    private var driver: (any RadioDriver)?
    private var directKeyer: CWKeyer?
    private var internalKeyer: RadioInternalKeyer?
    private var voiceDriver: (any VoiceMessageCapable)?
    /// The two ways a recording reaches the radio; at most one is non-nil,
    /// and both are nil on a radio that takes no audio from the Mac.
    private var streamer: (any AudioStreamTransmitCapable)?
    private var transmitControl: (any TransmitControlCapable)?
    private var voicePlayer: (any VoicePlaying)?
    /// True from `playRecording` until its terminal event — the recordings
    /// path's own flag, so an abort can end it without touching the radio's
    /// DVR bookkeeping.
    private var recordingIsPlaying = false
    /// Bumped per play; a terminal event stamped with an older generation
    /// belongs to a play that was replaced and is ignored.
    private var recordingGeneration = 0
    private var sendingClearTask: Task<Void, Never>?
    /// Which path owns `nowSending`, so the CW timer and the radio's real
    /// end-of-playback signal cannot clear each other's badge.
    private var nowSendingIsVoice = false
    /// What `nowSending` (and `nowSendingIsVoice`) held before the most
    /// recent voice claim, so a `.busy` refusal can put it back. The press
    /// that got refused never actually claimed anything — the *previous*
    /// play is still the one pending or on the air. Every other write to the
    /// badge discards this, so a stale slot can never be restored over
    /// newer state.
    private var badgeBeforeVoiceClaim: (text: String?, isVoice: Bool)?
    private var validationTask: Task<Void, Never>?
    private(set) var connectedDescriptor: RadioDescriptor?

    /// True while the radio reports TX, or while the app is sending a macro.
    /// A rig in QSK drops its TX flag between CW elements — first seen on a K3,
    /// but a property of QSK rather than of that model — which made the badge
    /// flicker mid-macro. Holding it for the estimated send duration is
    /// unconditional: no radio is special-cased here, and one that reports TX
    /// continuously is unaffected, since it is transmitting either way.
    var isTransmitting: Bool {
        (radioState?.isTransmitting ?? false) || nowSending != nil
    }

    init() {
        refreshPorts()
    }

    func refreshPorts() {
        availablePorts = SerialPortEnumerator.availablePorts()
    }

    func clearError() {
        lastError = nil
    }

    func connect(settings: AppSettings) {
        disconnect()
        guard let descriptor = RadioRegistry.descriptor(id: settings.radioID) else {
            lastError = ConnectionError(
                summary: "Unknown radio",
                detail: "No radio matches the saved id '\(settings.radioID)'. "
                    + "Pick a radio in the radio bar and connect again."
            )
            return
        }

        let newTransport: any SerialTransport
        switch descriptor.connection {
        case .serial:
            guard !settings.portPath.isEmpty else {
                lastError = ConnectionError(
                    summary: "No serial port selected",
                    detail: "Choose a serial port in the radio bar, then Connect. "
                        + "The ⟳ button rescans if the adapter was just plugged in."
                )
                return
            }
            let newPort = SerialPort(path: settings.portPath)
            do {
                try newPort.open(baudRate: settings.baudRate)
            } catch {
                lastError = ConnectionError(
                    summary: "Couldn't open port",
                    detail: error.localizedDescription
                )
                return
            }
            newTransport = newPort

        case .network(let defaultPort):
            let host = settings.tcpHost.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else {
                lastError = ConnectionError(
                    summary: "No radio address",
                    detail: "Enter the radio's IP address or hostname in the radio bar, "
                        + "then Connect."
                )
                return
            }
            let port = (1...65535).contains(settings.tcpPort) ? UInt16(settings.tcpPort) : defaultPort
            let tcp = TCPTransport(host: host, port: port)
            tcp.onDisconnect = { [weak self] reason in
                Task { @MainActor [weak self] in
                    self?.transportDidDisconnect(reason: reason)
                }
            }
            try? tcp.open(baudRate: 0)  // connects asynchronously; validation reports failures
            newTransport = tcp
        }

        let newDriver = descriptor.makeDriver()
        newDriver.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.driverDidReportState(state)
            }
        }
        newDriver.onKeyerSpeedChange = { [weak self] wpm in
            Task { @MainActor [weak self] in
                self?.radioReportedWPM = wpm
            }
        }
        // Voice memories are an optional capability: a driver either conforms
        // or the radio has none. Nothing is stubbed (Article 11). Wired
        // before `start()` — like the two callbacks above — because `start`
        // writes `OM;` immediately and the driver only fires on a *change*,
        // so a reply that beat a later assignment would be lost for good.
        if var voice = newDriver as? any VoiceMessageCapable {
            voice.onVoiceKeyerStatusChange = { [weak self] status in
                Task { @MainActor [weak self] in self?.voiceDidChangeStatus(status) }
            }
            voice.onVoicePlaybackChange = { [weak self] playing in
                Task { @MainActor [weak self] in self?.voiceDidChangePlayback(playing) }
            }
            voice.onVoiceMessageDropped = { [weak self] memory, reason in
                Task { @MainActor [weak self] in self?.voiceMessageWasDropped(memory, reason) }
            }
            voice.onVoiceBankChange = { [weak self] bank in
                Task { @MainActor [weak self] in self?.voiceDidChangeBank(bank) }
            }
            voiceDriver = voice
        }
        // The two ways a recording made here can reach the radio. Optional
        // capabilities like the one above: a driver conforms to one, or the
        // radio takes no audio from the Mac and the phone keys say so. Wired
        // before `start()` for the same reason the voice callbacks are.
        transmitControl = newDriver as? any TransmitControlCapable
        if let streaming = newDriver as? any AudioStreamTransmitCapable {
            streaming.onTransmitAudioEvent = { [weak self] event in
                Task { @MainActor [weak self] in self?.recordingDidReport(event, generation: nil) }
            }
            streamer = streaming
        }

        newDriver.start(transport: newTransport)

        // A radio with key lines is keyed directly and only directly; one
        // without them keys through its own keyer (Article 11). Exactly one of
        // these two is built, and `RadioRegistryTests` proves no descriptor
        // can be registered that would build both or neither.
        if descriptor.supportsDirectKeying {
            let keyer = CWKeyer(transport: newTransport, config: settings.keyerLineConfig, wpm: settings.wpm)
            keyer.onSending = { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.nowSending = text
                    // A chunk from a queued CW send may start while the voice
                    // path still (wrongly) thinks it owns the badge — every
                    // writer of `nowSending` must also claim `nowSendingIsVoice`,
                    // or a later voice end-of-playback signal would clear this
                    // chunk's badge instead of leaving it alone.
                    self?.nowSendingIsVoice = false
                    self?.badgeBeforeVoiceClaim = nil
                }
            }
            keyer.onFinished = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // A send that began while this hop was in flight owns the
                    // badge now — only the genuinely idle keyer clears it.
                    guard self.directKeyer?.isIdle == true else { return }
                    self.nowSending = nil
                }
            }
            directKeyer = keyer
        }

        transport = newTransport
        driver = newDriver
        internalKeyer = (newDriver as? any InternalKeyerDriver).map {
            RadioInternalKeyer(driver: $0, wpm: settings.wpm)
        }
        connectedDescriptor = descriptor
        isConnected = true
        refreshVoicePath(settings: settings)

        // Every connect gets the response check. A TCP connection to the
        // wrong IP "succeeds" silently, and an opened serial port with a
        // powered-off radio looks identical — the phase (and the bar) must
        // say which link actually proved out.
        startValidation(settings: settings)
    }

    /// Auto-connect on document open. Silently does nothing when the target
    /// isn't configured (or a serial port isn't currently present); otherwise
    /// connects — and `connect` verifies the radio actually answers.
    func autoConnect(settings: AppSettings) {
        guard !isConnected else { return }
        guard let descriptor = RadioRegistry.descriptor(id: settings.radioID) else { return }
        switch descriptor.connection {
        case .serial:
            refreshPorts()
            guard !settings.portPath.isEmpty,
                  availablePorts.contains(where: { $0.path == settings.portPath }) else { return }
        case .network:
            guard !settings.tcpHost.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        }

        connect(settings: settings)
    }

    /// The transport dropped out from under us (TCP reset, remote close).
    /// Tear down first, then record why: `disconnect()` wipes the slate, and
    /// an involuntary drop is the one story that must survive it. A late
    /// callback after a deliberate disconnect is not news and stays silent.
    func transportDidDisconnect(reason: String) {
        guard isConnected else { return }
        disconnect()
        lastError = ConnectionError(
            summary: "Connection lost",
            detail: "Radio connection lost: \(reason)"
        )
    }

    /// Single funnel for driver state updates. The first word from the radio
    /// is what "connected" means, so it also retires any silence warning.
    /// Updates already in flight when the link went down are dropped — they
    /// must not resurrect the frequency display or wipe a loss error.
    func driverDidReportState(_ state: RadioState) {
        guard isConnected else { return }
        radioState = state
        lastError = nil
    }

    private func startValidation(settings: AppSettings) {
        guard isConnected else { return }
        let target: String = switch connectedDescriptor?.connection {
        case .network:
            "\(settings.tcpHost.trimmingCharacters(in: .whitespaces)):\(settings.tcpPort)"
        default:
            (settings.portPath as NSString).lastPathComponent
        }
        let isNetwork = if case .network = connectedDescriptor?.connection { true } else { false }

        validationTask?.cancel()
        // Serial radios: first poll at +0.2 s, repeating 0.5 s. Network
        // radios: status arrives right after the subscribe. The default 4 s
        // window is generous for both.
        let deadline = Date().addingTimeInterval(validationWindow)
        validationTask = Task { [weak self] in
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, !Task.isCancelled, self.isConnected else { return }
                if self.radioState != nil { return }  // validated — radio is talking
            }
            guard let self, !Task.isCancelled, self.isConnected, self.radioState == nil else { return }
            self.validationExpired = true
            self.lastError = Self.unresponsiveError(target: target, isNetwork: isNetwork)
        }
    }

    func disconnect() {
        validationTask?.cancel()
        validationTask = nil
        // A recording still playing comes down before the driver goes: the
        // player unkeys through `transmitControl`, which must still exist.
        stopRecordingPlayback()
        recordingIsPlaying = false
        directKeyer?.shutdown()
        directKeyer = nil
        internalKeyer = nil
        driver?.stop()
        driver = nil
        voiceDriver = nil
        streamer = nil
        transmitControl = nil
        voicePathStatus = .unsupported
        transport?.close()
        transport = nil
        connectedDescriptor = nil
        isConnected = false
        radioState = nil
        // A deliberate disconnect is a clean slate — Cancel on a silent radio
        // must not leave its warning behind. Involuntary drops re-set their
        // error *after* calling this (`transportDidDisconnect`).
        lastError = nil
        validationExpired = false
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = nil
        radioReportedWPM = nil
        voiceStatus = .unsupported
        isVoicePlaying = false
        voiceBank = nil
        nowSendingIsVoice = false
        badgeBeforeVoiceClaim = nil
    }

    /// Estimated on-air duration of a message at the current speed — used to
    /// schedule the next repeat-CQ transmission for either keyer backend.
    func estimatedSendDuration(_ text: String, settings: AppSettings) -> TimeInterval {
        KeyerTiming.totalDurationMs(text: text, wpm: settings.wpm) / 1000.0
    }

    /// The one way this radio sends CW. There is no preference to consult:
    /// `connect` built whichever of the two the radio can use, and never both
    /// (Article 11).
    private func activeSender(_ settings: AppSettings) -> (any CWSender)? {
        directKeyer ?? internalKeyer
    }

    // MARK: Frequency / mode control (spots, typed QSY commands)

    func setFrequency(kHz: Double) {
        driver?.setFrequency(hz: Int((kHz * 1000).rounded()))
    }

    func setMode(rawMode: String) {
        driver?.setMode(rawMode: rawMode)
    }

    func sendCW(_ text: String, settings: AppSettings) {
        guard isConnected else { return }
        guard let sender = activeSender(settings) else { return }
        sender.wpm = settings.wpm
        sender.send(text)

        nowSending = text
        // A CW send after a voice send must reclaim the badge from the voice
        // path — otherwise the radio's next end-of-playback signal clears
        // this CW badge early (`voiceDidChangePlayback`).
        nowSendingIsVoice = false
        badgeBeforeVoiceClaim = nil
        sendingClearTask?.cancel()
        sendingClearTask = nil

        // The direct keyer reports real completion, and must: once speed can
        // change part-way through a message, no duration computed at send time
        // is still true when the message ends. The radio's own keyer offers no
        // completion signal, so there the estimate is the best there is.
        guard sender !== directKeyer else { return }

        let duration = estimatedSendDuration(text, settings: settings) + 0.2
        sendingClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.nowSending = nil
        }
    }

    /// The driver's answer to "what can this radio do about voice memories."
    /// A named handler — like `driverDidReportState` — rather than an inline
    /// assignment on `onVoiceKeyerStatusChange`, so a test can simulate the
    /// driver confirming readiness without a transport that actually talks
    /// back. Dropped once disconnected, for the same reason
    /// `driverDidReportState` is: a report already in flight when the
    /// operator disconnects must not revive state on a controller that has
    /// already been told to forget the radio.
    func voiceDidChangeStatus(_ status: VoiceKeyerStatus) {
        guard isConnected else { return }
        voiceStatus = status
    }

    /// The message bank the radio was last observed in. Named for the same
    /// reason `voiceDidChangeStatus` is: a disconnect guard, and a seam a
    /// test can call directly.
    func voiceDidChangeBank(_ bank: Int) {
        guard isConnected else { return }
        voiceBank = bank
    }

    /// Play one of the radio's recorded voice memories. `memory` is
    /// range-checked here, not just trusted from the caller (`EntryFlow`
    /// range-checks too, but this controller owns the badge it is about to
    /// set, and a memory the driver silently discards — no callback either
    /// way — would otherwise leave that badge stuck forever with nothing to
    /// clear it).
    func playVoiceMessage(memory: Int, caption: String) {
        guard isConnected, voiceStatus.isReady,
              memory >= 1, memory <= voiceStatus.memoryCount else { return }
        // Local state commits before the driver call, not after: the driver
        // can refuse synchronously (`.busy`), and that refusal's restore
        // must find a snapshot of what came *before* this claim — not rely
        // on the `Task { @MainActor }` hop to keep the ordering safe.
        badgeBeforeVoiceClaim = (nowSending, nowSendingIsVoice)
        // No timer, unlike CW: the radio reports the end of playback for real,
        // so the badge is cleared by the radio rather than by an estimate.
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = caption
        nowSendingIsVoice = true
        voiceDriver?.playVoiceMessage(memory: memory)
    }

    func voiceDidChangePlayback(_ playing: Bool) {
        guard isConnected else { return }
        // While a recording from this Mac is on the air, `isVoicePlaying` and
        // the badge belong to that path; the radio's own recorder is idle and
        // its poll must not end them early.
        guard !recordingIsPlaying else { return }
        isVoicePlaying = playing
        if !playing, nowSendingIsVoice {
            nowSending = nil
            nowSendingIsVoice = false
            badgeBeforeVoiceClaim = nil
        }
    }

    /// A requested memory did not go out. Only one of the two reasons is worth
    /// interrupting the operator for. Dropped once disconnected — the same
    /// guard `driverDidReportState` uses — so a late report cannot raise an
    /// error banner, or touch a badge, after the operator has already walked
    /// away: a deliberate disconnect is a clean slate, and this must not
    /// contradict `transportDidDisconnect`'s own "Connection lost" story
    /// with a stale "Voice memory not sent" of its own.
    func voiceMessageWasDropped(_ memory: Int, _ reason: VoiceMessageDropReason) {
        guard isConnected else { return }
        switch reason {
        case .busy:
            // `.busy` is ordinary fast typing — a second press while one is
            // still in flight. The press that got refused never actually
            // claimed anything: put back what it optimistically overwrote,
            // because the *previous* play — still pending, still the one on
            // the air — is what the badge should be showing.
            if let previous = badgeBeforeVoiceClaim {
                nowSending = previous.text
                nowSendingIsVoice = previous.isVoice
            }
        case .unconfirmed:
            // Only clear if the voice path still owns the badge — a CW send
            // that claimed it in the meantime must not be wiped by a bank
            // confirmation that arrives too late to mean anything anymore.
            if nowSendingIsVoice {
                nowSending = nil
                nowSendingIsVoice = false
            }
            lastError = ConnectionError(
                summary: "Voice memory not sent",
                detail: "The radio didn't confirm its message bank in time, so M\(memory) "
                    + "was not transmitted — nothing went on the air. Press again to retry."
            )
        }
        badgeBeforeVoiceClaim = nil
    }

    // MARK: Recordings on this Mac

    /// The truth table behind `voicePathStatus`, testable without a driver.
    /// The network path needs nothing else; the sound-card path needs an
    /// output device and either a driver that keys over CAT or VOX.
    static func voicePath(
        streams: Bool, keysOverCAT: Bool, ptt: VoicePTTMode, outputName: String?
    ) -> VoicePathStatus {
        if streams { return .readyOverNetwork }
        guard keysOverCAT || ptt == .vox else { return .unsupported }
        guard let outputName else { return .notReady(reason: chooseOutputReason) }
        return .readyOverDevice(name: outputName)
    }

    /// Re-derive after connect and whenever the voice settings change — the
    /// view calls it from `onChange` of the device, PTT and source prefs.
    func refreshVoicePath(settings: AppSettings) {
        guard isConnected else {
            voicePathStatus = .unsupported
            return
        }
        voicePathStatus = Self.voicePath(
            streams: streamer != nil,
            keysOverCAT: transmitControl != nil,
            ptt: settings.voicePTT,
            outputName: settings.voiceOutputDeviceUID.flatMap(resolveOutputDevice)
        )
    }

    /// Play a recording made on this Mac. Replaces one already playing — a
    /// voice keyer interrupts, because the station that answered mid-CQ is
    /// what the next key is for. The flow resolved `audio`; this only chooses
    /// the path and owns the badge.
    func playRecording(_ audio: VoiceAudio, caption: String, settings: AppSettings) {
        guard isConnected, voicePathStatus.isReady else { return }
        stopRecordingPlayback()
        recordingGeneration += 1
        let generation = recordingGeneration
        recordingIsPlaying = true
        // The same claim `playVoiceMessage` makes, minus the busy-restore:
        // this path never refuses synchronously.
        badgeBeforeVoiceClaim = nil
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = caption
        nowSendingIsVoice = true
        isVoicePlaying = true
        let level = Float(settings.voiceLevel)

        if let streamer {
            let forRadio: VoiceAudio
            do {
                forRadio = try AudioResampler.resample(audio, to: streamer.transmitSampleRate).scaled(by: level)
            } catch {
                recordingDidReport(.failed(error.localizedDescription), generation: nil)
                return
            }
            streamer.transmitAudio(forRadio)
            return
        }

        let player = makeVoicePlayer()
        voicePlayer = player
        // The player keys from its own thread; the drivers are thread-safe
        // (every one is `@unchecked Sendable` behind a lock) and the protocol
        // says so, which is what lets the closure be `@Sendable`.
        var keyRadio: (@Sendable (Bool) -> Void)?
        if settings.voicePTT == .radioCommand, let control = transmitControl {
            keyRadio = { on in control.setTransmit(on) }
        }
        player.play(audio, deviceUID: settings.voiceOutputDeviceUID, gain: level,
                    keyRadio: keyRadio, leadMs: settings.voicePTTLeadMs, tailMs: 100) { [weak self] event in
            Task { @MainActor [weak self] in self?.recordingDidReport(event, generation: generation) }
        }
    }

    /// One event from whichever path is playing. `generation` nil = the
    /// network path, which is single-instance and needs no stamp; a stamped
    /// event from a play that was since replaced is ignored, so it cannot
    /// clear the badge the new play owns.
    func recordingDidReport(_ event: TransmitAudioEvent, generation: Int?) {
        guard isConnected, recordingIsPlaying,
              generation == nil || generation == recordingGeneration else { return }
        switch event {
        case .started:
            break
        case .finished, .stopped:
            endRecordingPlayback()
        case .failed(let reason):
            endRecordingPlayback()
            lastError = ConnectionError(
                summary: "Voice message not sent",
                detail: "The recording did not go out: \(reason)"
            )
        }
    }

    private func endRecordingPlayback() {
        recordingIsPlaying = false
        isVoicePlaying = false
        voicePlayer = nil
        if nowSendingIsVoice {
            nowSending = nil
            nowSendingIsVoice = false
        }
        badgeBeforeVoiceClaim = nil
    }

    /// Bring a recording down now: the player unkeys before it reports, and
    /// the streamer likewise. The terminal event they then send is ignored
    /// (`recordingIsPlaying` is false) — the caller decides what happens next.
    private func stopRecordingPlayback() {
        guard recordingIsPlaying || voicePlayer != nil else { return }
        recordingIsPlaying = false
        voicePlayer?.stop()
        voicePlayer = nil
        streamer?.stopTransmitAudio()
    }

    /// Esc. Stops CW, the radio's own voice memory, and a recording playing
    /// from this Mac — `RX;` on a radio with voice memories is documented to
    /// terminate message play as well as a keyed transmission, and the
    /// recording paths unkey before they report. Unconditional: each handle
    /// is already nil on a radio that lacks that path, so gating on a status
    /// on top of that would buy nothing.
    func abortTransmission(settings: AppSettings) {
        activeSender(settings)?.abort()
        voiceDriver?.stopVoiceMessage()
        let wasPlayingRecording = recordingIsPlaying
        stopRecordingPlayback()
        if wasPlayingRecording { isVoicePlaying = false }
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = nil
        nowSendingIsVoice = false
        badgeBeforeVoiceClaim = nil
    }

    /// Push a speed change out immediately — it has to reach a message already
    /// on the air, not wait for the next one (Article 11).
    ///
    /// Both senders are told, whichever is active, and exactly one of them
    /// carries the change to the radio — so no radio is sent the same speed
    /// twice and none is left unsent.
    func syncWPM(_ wpm: Int, settings: AppSettings) {
        directKeyer?.wpm = wpm
        if let internalKeyer {
            // Its setter forwards to the driver: a radio keying from its own
            // keyer has to hear this while the message is still going out.
            internalKeyer.wpm = wpm
        } else {
            // Nothing keys from the radio's keyer here, but its speed still
            // drives the paddles and the front-panel display — keep them in
            // step so the operator sees one number, not two.
            driver?.setKeyerSpeed(wpm: wpm)
        }
    }

    func updateKeyerConfig(settings: AppSettings) {
        directKeyer?.updateConfig(settings.keyerLineConfig)
    }
}
