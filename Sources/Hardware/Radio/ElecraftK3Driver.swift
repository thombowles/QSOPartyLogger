import Foundation

/// Which radio in the family answered. The one place a per-model difference
/// lives, because both the memory count and the play sequence depend on it.
enum ElecraftModel: Equatable, Sendable {
    case k3
    case kx3
    case kx2
}

/// Elecraft K3/K3S/KX3/KX2 CAT driver. ASCII commands terminated with ';' at
/// 38400-8N1 (default). Response formats verified against the Elecraft
/// **Programmer's Reference revisions F2 and G5** (identical for these
/// commands), banked as `docs/research/k3_programmers_reference_g5.txt`.
///
/// The K3 has a perfectly good keyer of its own, and this driver deliberately
/// does not use it: a K3 exposes key lines, so the app keys it directly and
/// only directly (Article 11), which is what makes Esc abort mid-character and
/// makes CW speed changeable mid-message without depending on firmware. `KS`
/// remains, because the radio's own keyer speed still drives the paddles and
/// the front-panel display.
///
/// Voice is the other way round: `VoiceMessageCapable` plays the radio's own
/// recordings, because there is no key line for audio and Article 11 keeps
/// voice on the radio rather than piping Mac audio at it.
final class ElecraftK3Driver: RadioDriver, VoiceMessageCapable, @unchecked Sendable {

    static let baudRates = [4800, 9600, 19200, 38400]

    private let lock = NSLock()
    private var transport: (any SerialTransport)?
    private var pollTimer: (any DispatchSourceTimer)?
    private var rxBuffer = ""
    private let pollQueue = DispatchQueue(label: "org.b5n.QSOPartyLogger.k3poll", qos: .userInitiated)

    var onStateChange: (@Sendable (RadioState) -> Void)?
    /// Fired when the radio reports a keyer speed different from the last
    /// one seen — turning the K3's front-panel speed knob updates the app.
    var onKeyerSpeedChange: (@Sendable (Int) -> Void)?
    var onVoiceKeyerStatusChange: (@Sendable (VoiceKeyerStatus) -> Void)?
    var onVoicePlaybackChange: (@Sendable (Bool) -> Void)?
    var onVoiceMessageDropped: (@Sendable (Int, VoiceMessageDropReason) -> Void)?
    var onVoiceBankChange: (@Sendable (Int) -> Void)?

    private var lastState: RadioState?
    private var lastWPM: Int?

    private var model: ElecraftModel = .k3
    private var voiceStatus: VoiceKeyerStatus = .unsupported
    private var lastVoicePlaying: Bool?
    /// The bank the radio has actually been *observed* in, not the one we hope
    /// it is in. Nil until an `IC` has been seen.
    ///
    /// **The rule the whole voice path rests on: this is nil whenever a toggle
    /// may have executed unobserved.** A tap is only ever issued against a
    /// non-nil reading, so anything that could have moved the bank behind our
    /// back — an abort mid-window, a play dropped without confirmation — clears
    /// it, and the next play asks before it assumes.
    private var confirmedBank: Int?
    /// A memory waiting for the bank to confirm before it is tapped.
    private var pendingVoiceMemory: Int?
    /// `IC` responses evaluated since the bank change was requested.
    private var bankConfirmAttempts = 0
    /// Whether the bank change for `pendingVoiceMemory` has already been asked
    /// for. An unobserved bank is asked about (`IC;`) before it is ever toggled
    /// — a toggle is a guess, and guessing which bank the radio is in is how
    /// the wrong recording reaches the air.
    private var bankToggleRequested = false
    /// Whether the options query has been repeated after the radio first
    /// answered. The query at `start` can arrive before the radio is listening,
    /// in which case it is simply lost and the radio reads as having no voice
    /// recorder for the rest of the session; the first `IF` is the moment it
    /// proves otherwise, so that is when to ask again.
    ///
    /// **Nothing retries beyond that.** If the second query is lost too, the
    /// session runs with no voice keyer until the operator reconnects. The
    /// window is far narrower than the first — the link has already answered by
    /// then — so a third attempt buys little for the polling it costs.
    private var askedOptionsAfterFirstIF = false

    // MARK: Lifecycle

    func start(transport: any SerialTransport) {
        lock.lock()
        self.transport = transport
        lock.unlock()

        transport.onReceive = { [weak self] data in
            self?.ingest(data)
        }
        // AI0 = deterministic polling; K31 = K3 extended response mode;
        // OM = which model answered and which option modules are fitted.
        transport.write(Self.cmdAutoInfoOff + Self.cmdExtendedMode + Self.cmdPollOptions)

        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        lock.lock()
        pollTimer = timer
        lock.unlock()
    }

    func stop() {
        lock.lock()
        pollTimer?.cancel()
        pollTimer = nil
        transport = nil
        lastState = nil
        lastWPM = nil
        rxBuffer = ""
        voiceStatus = .unsupported
        model = .k3
        lastVoicePlaying = nil
        confirmedBank = nil
        pendingVoiceMemory = nil
        bankConfirmAttempts = 0
        bankToggleRequested = false
        askedOptionsAfterFirstIF = false
        lock.unlock()
    }

    private func poll() {
        currentTransport()?.write(Self.pollCommands)
    }

    private func currentTransport() -> (any SerialTransport)? {
        lock.lock()
        defer { lock.unlock() }
        return transport
    }

    // MARK: Commands (pure builders — unit tested)

    static let cmdPollIF = "IF;"
    static let cmdPollKS = "KS;"
    static let cmdAutoInfoOff = "AI0;"
    static let cmdExtendedMode = "K31;"
    static let cmdPollOptions = "OM;"
    static let cmdPollIcons = "IC;"

    /// IF = freq/mode/TX; KS = keyer speed; IC = icons, which carry the voice
    /// playback flag and the message bank.
    static let pollCommands = cmdPollIF + cmdPollKS + cmdPollIcons

    /// K3 M1–M4 tap (Table 7). Memories 5–8 are bank 2's M1–M4.
    static let cmdPlayK3Memory: [Int: String] = [1: "SWT21;", 2: "SWT31;", 3: "SWT35;", 4: "SWT39;"]
    /// KX3/KX2: tap MSG, then tap the digit (Tables 8 and 8A). Codes 19 and 27
    /// are digits 1 and 2 on both models.
    static let cmdPlayKXMemory: [Int: [String]] = [1: ["SWT11;", "SWT19;"], 2: ["SWT11;", "SWT27;"]]
    /// K3 REC hold — selects voice bank 1 or 2. The bank is stored separately
    /// per mode group, so this cannot disturb the operator's CW memory bank.
    static let cmdSelectBank = "SWH37;"
    /// Documented to terminate transmit in all modes, message play included.
    static let cmdStopVoiceMessage = "RX;"

    static func cmdSetFrequency(hz: Int) -> String {
        String(format: "FA%011d;", max(0, hz))
    }

    static func cmdSetKeyerSpeed(wpm: Int) -> String {
        String(format: "KS%03d;", min(50, max(8, wpm)))
    }

    /// MD command for an app mode; "SSB" resolves to the conventional
    /// sideband for the frequency (USB at/above 10 MHz, LSB below).
    static func cmdSetMode(rawMode: String, frequencyHz: Int) -> String? {
        let digit: Character? = switch rawMode.uppercased() {
        case "CW": "3"
        case "USB": "2"
        case "LSB": "1"
        case "SSB": frequencyHz >= 10_000_000 ? "2" : "1"
        case "RTTY", "DIGI": "6"
        case "AM": "5"
        case "FM": "4"
        default: nil
        }
        return digit.map { "MD\($0);" }
    }

    func setFrequency(hz: Int) {
        currentTransport()?.write(Self.cmdSetFrequency(hz: hz))
    }

    func setMode(rawMode: String) {
        lock.lock()
        let freq = lastState?.frequencyHz ?? 14_000_000
        lock.unlock()
        guard let cmd = Self.cmdSetMode(rawMode: rawMode, frequencyHz: freq) else { return }
        currentTransport()?.write(cmd)
    }

    /// Sets the radio's own keyer speed — the paddles and the front-panel
    /// display, not the app's keying, which is done on the key line. Sent the
    /// moment the operator asks so the two never disagree (Article 11).
    func setKeyerSpeed(wpm: Int) {
        currentTransport()?.write(Self.cmdSetKeyerSpeed(wpm: wpm))
    }

    // MARK: Voice memories

    func playVoiceMessage(memory: Int) {
        // One coherent snapshot: `confirmedBank` and `pendingVoiceMemory` must
        // describe the same instant, or the refusal below could be decided
        // against a bank reading from either side of an `IC`.
        lock.lock()
        let status = voiceStatus
        let model = self.model
        let confirmed = confirmedBank
        let alreadyPending = pendingVoiceMemory != nil
        lock.unlock()

        // Not `(1...status.memoryCount).contains` — a count of zero (no
        // recorder, or no `OM` answered yet) would form `1...0` and trap.
        guard memory >= 1, memory <= status.memoryCount else { return }

        // One play at a time. While a bank change this driver requested is
        // still unconfirmed, the observed bank does not describe the bank a tap
        // would land in — writes are FIFO, so a tap issued now arrives *after*
        // the toggle. Rather than reason about that, refuse: a refused press
        // that says so beats a press that plays the wrong recording
        // (Article 11).
        if alreadyPending {
            onVoiceMessageDropped?(memory, .busy)
            return
        }

        switch model {
        case .kx3, .kx2:
            guard let commands = Self.cmdPlayKXMemory[memory] else { return }
            currentTransport()?.write(commands.joined())

        case .k3:
            let wantedBank = memory <= 4 ? 1 : 2
            guard let tap = Self.cmdPlayK3Memory[memory <= 4 ? memory : memory - 4] else { return }
            if confirmed == wantedBank {
                currentTransport()?.write(tap)
                return
            }
            // The cached bank is up to one poll old, so it is not evidence.
            // Hold the tap until an `IC` confirms the bank — wrong audio on the
            // air is worse than silence (Article 11). A bank we have never
            // observed is asked about; only a bank observed to be *wrong* is
            // toggled.
            lock.lock()
            pendingVoiceMemory = memory
            bankConfirmAttempts = 0
            bankToggleRequested = confirmed != nil
            lock.unlock()
            currentTransport()?.write(
                confirmed == nil ? Self.cmdPollIcons : Self.cmdSelectBank + Self.cmdPollIcons
            )
        }
    }

    func stopVoiceMessage() {
        lock.lock()
        // An abort can land between a toggle and its confirmation, and `RX;`
        // stops audio without undoing a bank change — so the toggle may well
        // have taken effect and the last `IC` no longer describes the radio.
        // Forget it: the next play then asks rather than tapping on a reading
        // this abort invalidated.
        if bankToggleRequested { confirmedBank = nil }
        pendingVoiceMemory = nil
        bankToggleRequested = false
        lock.unlock()
        currentTransport()?.write(Self.cmdStopVoiceMessage)
    }

    // MARK: Response parsing (pure — unit tested)

    /// `IF[f]*****+yyyyrx*00tmvspbd1*;` — freq at [2..12], TX flag at 28, mode at 29.
    static func parseIF(_ response: String) -> RadioState? {
        let chars = Array(response)
        guard chars.count >= 31, chars[0] == "I", chars[1] == "F" else { return nil }
        guard let freq = Int(String(chars[2..<13])) else { return nil }
        guard let mode = K3Mode(rawValue: chars[29]) else { return nil }
        return RadioState(
            frequencyHz: freq,
            rawMode: mode.rawMode,
            isTransmitting: chars[28] == "1"
        )
    }

    /// `FAnnnnnnnnnnn;` → Hz.
    static func parseFA(_ response: String) -> Int? {
        guard response.hasPrefix("FA"), response.count >= 13 else { return nil }
        return Int(String(Array(response)[2..<13]))
    }

    /// `MDn;` → mode.
    static func parseMD(_ response: String) -> K3Mode? {
        guard response.hasPrefix("MD"), response.count >= 3 else { return nil }
        return K3Mode(rawValue: Array(response)[2])
    }

    /// `KSnnn;` → WPM.
    static func parseKS(_ response: String) -> Int? {
        guard response.hasPrefix("KS"), response.count >= 5 else { return nil }
        return Int(String(Array(response)[2..<5]))
    }

    /// `OM` — installed option modules, and on the KX models a product
    /// identifier. Both variants carry a 12-character field; the reference
    /// prints the K3 example with a space after `OM`, so one is tolerated.
    ///
    /// K3/K3S: `APXSDFfLVR--`, index 4 = `D` when the KDVR3 recorder is fitted.
    /// KX3/KX2: `APF---TBXI0n`, where `0n` is `01` for a KX2 and `02` for a KX3
    /// — neither has a `D` position, because the recorder is built in.
    ///
    /// **The KX branch also insists index 4 is not `D`, which the discriminator
    /// does not strictly need.** The reference reserves the K3's trailing dashes
    /// "for future module letters and product ID", so a later K3 could report an
    /// identifier where only a KX reports one today. The two families play a
    /// memory with different command sequences, so a K3 read as a KX would be
    /// sent bytes from the wrong table. No KX can carry a `D` at index 4 — it is
    /// a reserved dash there — so this rejects nothing real, and it keeps a
    /// recorder-equipped K3 resolving as a K3 whatever lands in 10–11.
    static func parseOM(_ response: String) -> (model: ElecraftModel, voice: VoiceKeyerStatus)? {
        guard response.hasPrefix("OM") else { return nil }
        var body = response.dropFirst(2)
        if body.hasSuffix(";") { body = body.dropLast() }
        let field = Array(body.trimmingCharacters(in: .whitespaces))
        guard field.count >= 12 else { return nil }

        if field[4] != "D", field[10] == "0" {
            if field[11] == "1" { return (.kx2, .available(count: 2)) }
            if field[11] == "2" { return (.kx3, .available(count: 2)) }
        }
        return (.k3, field[4] == "D" ? .available(count: 8) : .notInstalled)
    }

    /// `ICabcde;` — five 8-bit flag bytes. Byte a bit B2 is "MSG is playing"
    /// and bit B3 is the message bank (0 = bank 1). B7 is always 1 so that no
    /// control character reaches the host, which is why this reads unicode
    /// scalar values rather than `asciiValue`: the transport decodes ISO
    /// Latin-1, so every byte becomes exactly one scalar in 0x00...0xFF.
    static func parseIC(_ response: String) -> (playing: Bool, bank: Int)? {
        let scalars = Array(response.unicodeScalars)
        guard scalars.count >= 8, scalars[0] == "I", scalars[1] == "C" else { return nil }
        let a = scalars[2].value
        return (playing: (a >> 2) & 1 == 1, bank: (a >> 3) & 1 == 1 ? 2 : 1)
    }

    // MARK: RX plumbing

    private func ingest(_ data: Data) {
        guard let text = String(data: data, encoding: .isoLatin1) else { return }
        lock.lock()
        rxBuffer += text
        var responses: [String] = []
        while let sep = rxBuffer.firstIndex(of: ";") {
            responses.append(String(rxBuffer[..<sep]) + ";")
            rxBuffer = String(rxBuffer[rxBuffer.index(after: sep)...])
        }
        // Guard against garbage floods with no terminator.
        if rxBuffer.count > 4096 { rxBuffer = "" }
        lock.unlock()

        for response in responses {
            handle(response: response)
        }
    }

    private func handle(response: String) {
        if let state = Self.parseIF(response) {
            lock.lock()
            let changed = state != lastState
            lastState = state
            lock.unlock()
            if changed {
                onStateChange?(state)
            }
            lock.lock()
            let needsOptions = !askedOptionsAfterFirstIF
            askedOptionsAfterFirstIF = true
            lock.unlock()
            if needsOptions { currentTransport()?.write(Self.cmdPollOptions) }
            return
        }
        if let om = Self.parseOM(response) {
            lock.lock()
            let changed = om.voice != voiceStatus
            model = om.model
            voiceStatus = om.voice
            lock.unlock()
            if changed { onVoiceKeyerStatusChange?(om.voice) }
            return
        }
        if let ic = Self.parseIC(response) {
            handleIcons(ic)
            return
        }
        if let wpm = Self.parseKS(response) {
            lock.lock()
            let changed = wpm != lastWPM
            lastWPM = wpm
            lock.unlock()
            if changed {
                onKeyerSpeedChange?(wpm)
            }
        }
    }

    /// What one `IC` response resolved a pending play into. The decision is
    /// made inside a single locked section and acted on after the lock is
    /// released, so no state can shift between deciding and committing.
    private enum PendingVoiceOutcome {
        /// Keep waiting — nothing to send.
        case wait
        /// The bank is confirmed. Tap this.
        case tap(String)
        /// The bank is now *observed* to be wrong. Ask for the other one.
        case requestBank
        /// The window closed with no confirmation. Nothing was transmitted.
        case dropped(Int)
    }

    /// One `IC` response: the real playback signal, and the bank confirmation
    /// a pending bank-2 memory is waiting on.
    private func handleIcons(_ ic: (playing: Bool, bank: Int)) {
        lock.lock()
        // `lastVoicePlaying` starts nil (nothing observed yet, not "was
        // playing"), so comparing straight against it would make the very
        // first `IC` of a session read as a change whenever it reports "not
        // playing" — `false != nil` — even though nothing has actually
        // transitioned. Falling back to `false` treats "nothing observed" the
        // same as "not playing" for this comparison, so that first `IC` is
        // silent when it agrees. A first observation of *true* still reports:
        // that really is new information the app never asked for.
        let playbackChanged = ic.playing != (lastVoicePlaying ?? false)
        let bankChanged = ic.bank != confirmedBank
        let hasBanks = model == .k3
        lastVoicePlaying = ic.playing
        confirmedBank = ic.bank
        let outcome = resolvePendingVoice(bank: ic.bank)
        lock.unlock()

        // The transport write comes first, before the observers below. An abort
        // landing between the decision and the write emits `RX;` ahead of a tap
        // that is already committed to; keeping the observers after it makes
        // that window a few instructions instead of however long arbitrary
        // app-layer work takes.
        switch outcome {
        case .wait:
            break
        case .tap(let tap):
            currentTransport()?.write(tap)
        case .requestBank:
            currentTransport()?.write(Self.cmdSelectBank + Self.cmdPollIcons)
        case .dropped(let memory):
            // The only producer of `.dropped` is the exhausted confirmation
            // window, so this is always the reportable kind.
            onVoiceMessageDropped?(memory, .unconfirmed)
        }

        if playbackChanged { onVoicePlaybackChange?(ic.playing) }
        // Only the banked model reports a bank; a KX has none to report.
        if bankChanged, hasBanks { onVoiceBankChange?(ic.bank) }
    }

    /// Advance the pending play by one observation, reading *and* committing in
    /// one pass while the lock is held.
    ///
    /// Guaranteed: the decision is atomic against `stopVoiceMessage`, so a play
    /// already aborted when this runs can never be tapped, and no two
    /// observations can both resolve the same pending memory.
    ///
    /// **Not** guaranteed: the resulting write is outside the critical section,
    /// so an abort landing between the decision and the write still emits `RX;`
    /// ahead of a tap already committed to. `handleIcons` keeps that window to a
    /// few instructions; closing it needs the write serialised behind the lock
    /// or a generation counter, neither of which is worth the risk here.
    ///
    /// - Precondition: `lock` is held.
    private func resolvePendingVoice(bank: Int) -> PendingVoiceOutcome {
        guard let pending = pendingVoiceMemory else { return .wait }
        let wantedBank = pending <= 4 ? 1 : 2

        if bank == wantedBank {
            pendingVoiceMemory = nil
            bankToggleRequested = false
            guard let tap = Self.cmdPlayK3Memory[pending <= 4 ? pending : pending - 4] else {
                return .wait
            }
            return .tap(tap)
        }

        // First evidence that a change is needed at all: the bank was never
        // observed, only asked about. Now it has been seen to be wrong, so
        // toggling is a correction rather than a guess. The confirmation
        // window starts here, with the toggle.
        if !bankToggleRequested {
            bankToggleRequested = true
            bankConfirmAttempts = 0
            return .requestBank
        }

        // Never toggle twice: a second `SWH37;` would land back where we
        // started. The window exists only to absorb a poll response that was
        // already in flight when the change was requested.
        bankConfirmAttempts += 1
        guard bankConfirmAttempts >= 2 else { return .wait }
        pendingVoiceMemory = nil
        bankToggleRequested = false
        // Deliberate insurance, not a known failure — do not optimise away.
        // By FIFO the `IC;` appended to the toggle is answered after it, so two
        // samples agreeing on the old bank really should mean the toggle never
        // took. But that is a *timing* argument, and timing arguments are what
        // break first behind a USB-serial adapter doing its own buffering. The
        // cost of being wrong is the one outcome Article 11 forbids; the cost
        // of this line is one extra `IC;` on a path that has already failed.
        confirmedBank = nil
        return .dropped(pending)
    }
}
