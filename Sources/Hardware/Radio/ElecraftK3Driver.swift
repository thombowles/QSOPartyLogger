import Foundation

/// Elecraft K3/K3S/KX3/KX2 CAT driver. Speaks `ElecraftProtocol` over an
/// `ElecraftSession`; everything below is what this radio *does* with it.
///
/// The K3 has a perfectly good keyer of its own, and this driver deliberately
/// does not use it: a K3 exposes key lines — `CONFIG:PTT-KEY` (menu 103) routes
/// its own serial port's DTR/RTS to the key line inside the radio — so the app
/// keys it directly and only directly (Article 11), which is what makes Esc
/// abort mid-character and makes CW speed changeable mid-message without
/// depending on firmware. `KS` remains, because the radio's own keyer speed
/// still drives the paddles and the front-panel display.
///
/// Voice has two paths on this family, and the app picks (Article 11 as
/// amended 2026-08-15). Recordings made on the Mac play through a sound card
/// into the radio's line input, and this driver keys the radio around them
/// over CAT — `TransmitControlCapable`, `TX;`/`RX;` (Programmer's Reference
/// G5: "Same as activating PTT or using the XMIT switch"). The radio's own
/// recorder remains the option: `VoiceMessageCapable` plays its memories.
final class ElecraftK3Driver: RadioDriver, VoiceMessageCapable, TransmitControlCapable, @unchecked Sendable {

    static let baudRates = ElecraftProtocol.baudRates

    private let lock = NSLock()
    private let session = ElecraftSession(queueLabel: "org.b5n.QSOPartyLogger.k3poll")

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
        session.start(
            transport: transport,
            setup: ElecraftProtocol.setupCommands,
            pollCommands: ElecraftProtocol.pollCommands
        ) { [weak self] response in
            self?.handle(response: response)
        }
    }

    func stop() {
        session.stop()
        lock.lock()
        lastState = nil
        lastWPM = nil
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

    // MARK: Commands this radio owns (the rest live in `ElecraftProtocol`)

    /// K3 M1–M4 tap (Table 7). Memories 5–8 are bank 2's M1–M4.
    static let cmdPlayK3Memory: [Int: String] = [1: "SWT21;", 2: "SWT31;", 3: "SWT35;", 4: "SWT39;"]
    /// KX3/KX2: tap MSG, then tap the digit (Tables 8 and 8A). Codes 19 and 27
    /// are digits 1 and 2 on both models.
    static let cmdPlayKXMemory: [Int: [String]] = [1: ["SWT11;", "SWT19;"], 2: ["SWT11;", "SWT27;"]]
    /// K3 REC hold — selects voice bank 1 or 2. The bank is stored separately
    /// per mode group, so this cannot disturb the operator's CW memory bank.
    static let cmdSelectBank = "SWH37;"
    /// `RX` stops a memory playing, and unkeys after a recording from the Mac.
    static let cmdStopVoiceMessage = ElecraftProtocol.cmdReceive

    func setFrequency(hz: Int) {
        session.write(ElecraftProtocol.cmdSetFrequency(hz: hz))
    }

    func setMode(rawMode: String) {
        let freq = lock.withLock { lastState?.frequencyHz ?? 14_000_000 }
        guard let cmd = ElecraftProtocol.cmdSetMode(rawMode: rawMode, frequencyHz: freq) else { return }
        session.write(cmd)
    }

    /// Sets the radio's own keyer speed — the paddles and the front-panel
    /// display, not the app's keying, which is done on the key line. Sent the
    /// moment the operator asks so the two never disagree (Article 11).
    func setKeyerSpeed(wpm: Int) {
        session.write(ElecraftProtocol.cmdSetKeyerSpeed(wpm: wpm))
    }

    // MARK: Transmit control (recordings played through a sound card)

    /// Key or unkey the radio around a recording the Mac is playing into its
    /// line input. Nothing else here changes: the recorder's own state
    /// machine below is untouched, and `RX;` is the same byte string that
    /// stops a memory, so an abort needs no second command.
    func setTransmit(_ on: Bool) {
        session.write(on ? ElecraftProtocol.cmdTransmit : ElecraftProtocol.cmdReceive)
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
            session.write(commands.joined())

        case .k3:
            let wantedBank = memory <= 4 ? 1 : 2
            guard let tap = Self.cmdPlayK3Memory[memory <= 4 ? memory : memory - 4] else { return }
            if confirmed == wantedBank {
                session.write(tap)
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
            session.write(
                confirmed == nil
                    ? ElecraftProtocol.cmdPollIcons
                    : Self.cmdSelectBank + ElecraftProtocol.cmdPollIcons
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
        session.write(Self.cmdStopVoiceMessage)
    }

    // MARK: RX plumbing

    private func handle(response: String) {
        if let state = ElecraftProtocol.parseIF(response) {
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
            if needsOptions { session.write(ElecraftProtocol.cmdPollOptions) }
            return
        }
        if let om = ElecraftProtocol.parseOM(response) {
            lock.lock()
            let changed = om.voice != voiceStatus
            model = om.model
            voiceStatus = om.voice
            lock.unlock()
            if changed { onVoiceKeyerStatusChange?(om.voice) }
            return
        }
        if let ic = ElecraftProtocol.parseIC(response) {
            handleIcons(ic)
            return
        }
        if let wpm = ElecraftProtocol.parseKS(response) {
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
            session.write(tap)
        case .requestBank:
            session.write(Self.cmdSelectBank + ElecraftProtocol.cmdPollIcons)
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
