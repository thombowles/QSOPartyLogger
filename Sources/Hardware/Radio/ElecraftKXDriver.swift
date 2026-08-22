import Foundation

/// Elecraft KX3 / KX2 CAT driver — the portables, keyed **through the radio's
/// own keyer** over CAT. Speaks `ElecraftProtocol` over an `ElecraftSession`,
/// exactly as `ElecraftK3Driver` does; the whole difference is CW.
///
/// This is the one serial radio in the app that is not keyed on a control
/// line, and it is not a preference (Article 11 leaves no room for one). A KX's
/// CAT jack is its ACC jack, whose pinout is tip = RX data, ring 1 = TX data,
/// **ring 2 = key *out*** for amplifiers, sleeve = ground — so no key line
/// reaches the app through the cable it opens, and the article's
/// `InternalKeyerDriver` arm is the only one available. (The radio *can* be
/// line-keyed: `MENU:CW KEY1 = HAND` makes the KEY jack "an input for an
/// external keying device (keyer, computer, etc.)" — but that is a second wire
/// on a second port, which this app cannot assume exists. The K3's
/// `CONFIG:PTT-KEY` has no counterpart here.) The reasoning, the sources and
/// the open questions are in `docs/research/kx_cw_keying.md`.
///
/// Written against the **Programmer's Reference, Rev. G5** (Feb. 20 2019),
/// banked as `docs/research/k3_programmers_reference_g5.txt`, plus the **KX2
/// Owner's Manual Rev. B2** and **KX3 Owner's Manual Rev. C5** for the jacks
/// and the front panel.
///
/// Voice is unchanged from the rest of the family: two built-in memories played
/// by tapping MSG then a digit (`VoiceMessageCapable`), and `TX;`/`RX;` around
/// a recording the Mac plays through a sound card (`TransmitControlCapable`).
final class ElecraftKXDriver: RadioDriver, InternalKeyerDriver, VoiceMessageCapable,
                              TransmitControlCapable, @unchecked Sendable {

    static let baudRates = ElecraftProtocol.baudRates

    /// `IF`/`KS`/`IC` as everywhere, plus `KY` — the CW buffer's state, which
    /// is what lets a message stalled on a full buffer start moving again
    /// without the driver spinning on the port. See `pump()`.
    static let pollCommands = ElecraftProtocol.pollCommands + cmdPollBuffer

    private let lock = NSLock()
    private let session = ElecraftSession(queueLabel: "org.b5n.QSOPartyLogger.kxpoll")

    var onStateChange: (@Sendable (RadioState) -> Void)?
    var onKeyerSpeedChange: (@Sendable (Int) -> Void)?
    var onVoiceKeyerStatusChange: (@Sendable (VoiceKeyerStatus) -> Void)?
    var onVoicePlaybackChange: (@Sendable (Bool) -> Void)?
    /// Never fired. A KX needs no state confirmed before it plays a memory —
    /// there are no banks to get wrong — so no play is ever refused.
    var onVoiceMessageDropped: (@Sendable (Int, VoiceMessageDropReason) -> Void)?
    /// Never fired: a KX has no message banks, so it has no bank to report.
    var onVoiceBankChange: (@Sendable (Int) -> Void)?

    private var lastState: RadioState?
    private var lastWPM: Int?
    /// Which of the two answered. Only `OM` can say, and until it does the
    /// safe assumption is the model with *more* capability, since the one
    /// difference is a mode a KX2 will simply ignore.
    private var model: ElecraftModel = .kx3
    private var voiceStatus: VoiceKeyerStatus = .unsupported
    private var lastVoicePlaying: Bool?
    private var askedOptionsAfterFirstIF = false

    /// Text still to be handed to the radio, already cut to packet size.
    private var pendingChunks: [String] = []
    /// True while a `KY;` query is outstanding for a chunk that is waiting on
    /// buffer space. Nothing is written while this is set.
    private var awaitingBuffer = false

    // MARK: Lifecycle

    func start(transport: any SerialTransport) {
        session.start(
            transport: transport,
            setup: ElecraftProtocol.setupCommands,
            pollCommands: Self.pollCommands
        ) { [weak self] response in
            self?.handle(response: response)
        }
    }

    func stop() {
        session.stop()
        lock.lock()
        lastState = nil
        lastWPM = nil
        model = .kx3
        voiceStatus = .unsupported
        lastVoicePlaying = nil
        askedOptionsAfterFirstIF = false
        pendingChunks.removeAll()
        awaitingBuffer = false
        lock.unlock()
    }

    // MARK: CW — the radio's own keyer (pure builders, unit tested)

    /// "`KY*[text];` where `*` is normally a BLANK and `[text]` is 0 to 24
    /// characters" (Pgmrs Ref G5).
    static let maxTextCharacters = 24

    /// **Always the blank form, never `KYW`.** G5: "If `*` is a W (for
    /// 'wait'), processing of any following host commands will be delayed
    /// until the current message has been sent … e.g., KS (keyer speed)."
    /// Deferring a speed change is exactly what Article 11 forbids, so the
    /// wait form is not merely unused here — it must never be built.
    static func cmdSendText(_ chunk: String) -> String { "KY \(chunk);" }

    /// `KY;` GET — "KYn; where n is 0 (CW text buffer not full) or 1 (buffer
    /// full)."
    static let cmdPollBuffer = "KY;"

    /// True when the radio says its CW buffer is full. Nil for anything that
    /// is not a `KY` status — including the bare `KY;` this driver itself
    /// writes, which is three characters and must never be read as an answer.
    ///
    /// K2 extended mode adds a third value, 2, meaning the buffer is empty
    /// *and* the previous string has finished sending; it is read the same way
    /// as 0 here, because both mean "there is room".
    static func parseKY(_ response: String) -> Bool? {
        guard response.hasPrefix("KY"), response.count >= 4 else { return nil }
        switch Array(response)[2] {
        case "0", "2": return false
        case "1": return true
        default: return nil
        }
    }

    /// Cut a message into packets the radio will accept whole.
    ///
    /// Breaks on the last space inside the window when there is one, and keeps
    /// that space at the end of the chunk it closes — a break that dropped it
    /// would run two words together on the air. A single word longer than a
    /// packet has to be cut somewhere, and is cut at the limit rather than
    /// discarded.
    static func chunks(for text: String) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return [] }

        var remaining = Substring(cleaned)
        var chunks: [String] = []
        while !remaining.isEmpty {
            guard remaining.count > maxTextCharacters else {
                chunks.append(String(remaining))
                break
            }
            let windowEnd = remaining.index(remaining.startIndex, offsetBy: maxTextCharacters)
            let window = remaining[remaining.startIndex..<windowEnd]
            let breakAt = window.lastIndex(of: " ").map { remaining.index(after: $0) } ?? windowEnd
            chunks.append(String(remaining[remaining.startIndex..<breakAt]))
            remaining = remaining[breakAt...]
        }
        return chunks
    }

    func sendInternalKeyerText(_ text: String) {
        let chunks = Self.chunks(for: text)
        guard !chunks.isEmpty else { return }
        lock.lock()
        pendingChunks.append(contentsOf: chunks)
        let idle = !awaitingBuffer
        lock.unlock()
        // A send arriving while an earlier one waits on buffer space simply
        // queues behind it; the `KY0;` that releases the wait will pump it.
        if idle { pump() }
    }

    func stopInternalKeyer() {
        lock.lock()
        pendingChunks.removeAll()
        awaitingBuffer = false
        lock.unlock()
        // `RX;` — "Terminates transmit in all modes, including message play and
        // repeating messages" (Pgmrs Ref G5).
        //
        // **Article 3 — what the reference does not say:** it states that RX
        // terminates *transmit*, not that it empties the KY buffer. Dropping
        // our own queue above is what guarantees nothing further of ours
        // reaches the radio; whether a partly-sent packet still inside the
        // radio is discarded is unverified, and is recorded as an open
        // question in docs/research/kx_cw_keying.md.
        session.write(ElecraftProtocol.cmdReceive)
    }

    /// Hand the next packet over, and ask about the buffer only when there is
    /// something waiting behind it.
    private func pump() {
        lock.lock()
        guard !pendingChunks.isEmpty else {
            awaitingBuffer = false
            lock.unlock()
            return
        }
        let chunk = pendingChunks.removeFirst()
        let more = !pendingChunks.isEmpty
        awaitingBuffer = more
        lock.unlock()
        session.write(Self.cmdSendText(chunk) + (more ? Self.cmdPollBuffer : ""))
    }

    // MARK: Frequency, mode, speed

    func setFrequency(hz: Int) {
        session.write(ElecraftProtocol.cmdSetFrequency(hz: hz))
    }

    func setMode(rawMode: String) {
        let (freq, model) = lock.withLock { (lastState?.frequencyHz ?? 14_000_000, self.model) }
        guard let cmd = ElecraftProtocol.cmdSetMode(rawMode: rawMode, frequencyHz: freq, model: model)
        else { return }
        session.write(cmd)
    }

    /// The radio's own keyer speed — which on this radio is also the app's,
    /// since the radio does the element timing. Sent the moment the operator
    /// asks, never queued behind a message in flight (Article 11): the blank
    /// `KY` form is chosen precisely so this is not deferred.
    func setKeyerSpeed(wpm: Int) {
        session.write(ElecraftProtocol.cmdSetKeyerSpeed(wpm: wpm))
    }

    // MARK: Transmit control (recordings played through a sound card)

    func setTransmit(_ on: Bool) {
        session.write(on ? ElecraftProtocol.cmdTransmit : ElecraftProtocol.cmdReceive)
    }

    // MARK: Voice memories (Tables 8 and 8A)

    /// Tap MSG, then tap the digit. Switch code 11 is MSG on both models, and
    /// 19 and 27 are digits 1 and 2 on both — the KX2's Table 8A and the KX3's
    /// Table 8 agree on every code used here, which is what lets one driver
    /// serve them.
    static let cmdPlayMemory: [Int: String] = [1: "SWT11;SWT19;", 2: "SWT11;SWT27;"]

    func playVoiceMessage(memory: Int) {
        lock.lock()
        let status = voiceStatus
        let isKX = model.isKX
        lock.unlock()
        // Not `(1...status.memoryCount).contains` — a count of zero (no `OM`
        // answered yet) would form `1...0` and trap.
        guard isKX, memory >= 1, memory <= status.memoryCount,
              let command = Self.cmdPlayMemory[memory] else { return }
        session.write(command)
    }

    func stopVoiceMessage() {
        session.write(ElecraftProtocol.cmdReceive)
    }

    // MARK: RX plumbing

    private func handle(response: String) {
        if let state = ElecraftProtocol.parseIF(response) {
            lock.lock()
            let changed = state != lastState
            lastState = state
            let needsOptions = !askedOptionsAfterFirstIF
            askedOptionsAfterFirstIF = true
            lock.unlock()
            if changed { onStateChange?(state) }
            // The query at `start` can arrive before the radio is listening.
            // The first `IF` is the moment it proves otherwise — ask once more.
            if needsOptions { session.write(ElecraftProtocol.cmdPollOptions) }
            return
        }
        if let om = ElecraftProtocol.parseOM(response) {
            // A K3 answering on this descriptor is *not* claimed: this driver
            // taps the KX switch codes, and a K3's memories are banked and
            // belong to the other driver. Reporting no memories is the honest
            // answer, and it leaves the phone keys inert rather than playing
            // the wrong thing (Article 11).
            let status = om.model.isKX ? om.voice : .unsupported
            lock.lock()
            let changed = status != voiceStatus
            model = om.model
            voiceStatus = status
            lock.unlock()
            if changed { onVoiceKeyerStatusChange?(status) }
            return
        }
        if let ic = ElecraftProtocol.parseIC(response) {
            lock.lock()
            // nil means "nothing observed yet", not "was playing" — so the
            // first `IC` of a session is silent when it reports idle, while a
            // first observation of *playing* is still news.
            let changed = ic.playing != (lastVoicePlaying ?? false)
            lastVoicePlaying = ic.playing
            lock.unlock()
            if changed { onVoicePlaybackChange?(ic.playing) }
            return
        }
        if let full = Self.parseKY(response) {
            // Room in the buffer: hand over the next packet. Full: wait. The
            // poll carries `KY;`, so a wait always ends — at worst one poll
            // interval later — without this driver spinning on the port.
            if !full { pump() }
            return
        }
        if let wpm = ElecraftProtocol.parseKS(response) {
            lock.lock()
            let changed = wpm != lastWPM
            lastWPM = wpm
            lock.unlock()
            if changed { onKeyerSpeedChange?(wpm) }
        }
    }
}
