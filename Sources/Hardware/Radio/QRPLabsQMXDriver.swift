import Foundation

/// QRP Labs QMX+ / QMX CAT driver. ASCII commands terminated with `;`, over the
/// radio's USB Virtual COM port. Written against the QRP Labs **QMX CAT
/// programming manual, firmware 1_04_004** (revision history entry
/// "1_04_004 23-Jul-2026"; the page footers still read 1_04_003), with the
/// keying and serial-port behaviour from the **QMX operating manual, firmware
/// 1_04_004**. One driver serves the whole series — the CAT manual's own
/// subtitle is "For ALL QMX-series transceivers", and nothing below depends on
/// which bands a given unit was built for.
///
/// The command set is "a subset of the Kenwood TS-480/TS-440 CAT command set",
/// so `IF` carries the same field layout the K3 driver parses. Four things
/// about *this* radio shape the code, and each is why a line here differs from
/// the obvious one:
///
/// - **Never send a carriage return.** The CAT manual: QMX "interprets an
///   incoming carriage return character as a trigger to switch the serial port
///   to terminal mode". A stray CR does not fail a command, it takes the port
///   out of CAT for the rest of the session. Every command below ends in `;`
///   and nothing else.
/// - **`MD8;` is a transmission, not a mode.** The MD list runs 1/2/3/5/6/7/8/9
///   and 8 "activates SWR Tune mode", so no app mode may resolve to it — and an
///   `IF` that reports 8 is not an operating mode to stamp on a QSO either.
///   There is no 4: a QMX has no FM.
/// - **`KY` appends to an 80-character circular buffer**, and a message that
///   would overflow it "will simply be ignored and error code ?; returned" —
///   silently, mid-word, which in a contest is a mangled call. Text is chunked
///   and paced against the radio's own `KY;` buffer status instead of blasted.
/// - **Keyer text is the fallback path** (Article 11). A QMX keys from DTR on
///   its own USB port — operating manual, CW menu, "Key from USB DTR" — so
///   `supportsDirectKeying` is true and this driver's `KY` handling is what an
///   operator gets only if they choose it.
final class QRPLabsQMXDriver: RadioDriver, @unchecked Sendable {

    /// The CAT link is a USB Virtual COM port, where the rate is decoration:
    /// "the baud rate 9600 is unimportant because it is irrelevant to the USB
    /// Virtual COM Port which is a virtual port over USB, not a real physical
    /// serial port" (operating manual, WSJT-X setup). The picker still has to
    /// offer something, so it offers rates from the radio's *own* documented
    /// list (the "Serial 1 baud" menu), defaulting to that menu's own default.
    static let baudRates = [4800, 9600, 19200, 38400, 115200]

    /// Per-`KY` payload ceiling, in characters. `KY0;` promises the 80-byte
    /// buffer is "not more than 75% full" — at most 60 used, so at least 20
    /// free — and the buffer only drains between the radio's answer and our
    /// write, never grows, since this driver is its only writer. 20 is
    /// therefore the largest chunk that can never be the one that overflows.
    static let keyerChunkLimit = 20

    private let lock = NSLock()
    private var transport: (any SerialTransport)?
    private var pollTimer: (any DispatchSourceTimer)?
    private var rxBuffer = ""
    private var pendingKeyerChunks: [String] = []
    private let pollQueue = DispatchQueue(label: "org.b5n.QSOPartyLogger.qmxpoll", qos: .userInitiated)

    var onStateChange: (@Sendable (RadioState) -> Void)?
    /// Fired when the radio reports a keyer speed different from the last one
    /// seen — clicking Select and turning the encoder updates the app.
    var onKeyerSpeedChange: (@Sendable (Int) -> Void)?
    private var lastState: RadioState?
    private var lastWPM: Int?

    // MARK: Lifecycle

    func start(transport: any SerialTransport) {
        lock.lock()
        self.transport = transport
        pendingKeyerChunks = []
        lock.unlock()

        transport.onReceive = { [weak self] data in
            self?.ingest(data)
        }
        // AI0 = auto-info off, so every IF we see is one we asked for. The
        // radio's other AI modes push an unsolicited IF every 1.5 s, which
        // would race the poll loop's own answers through one buffer.
        transport.write(Self.cmdAutoInfoOff)

        // 0.5 s matches the other serial driver and is what the band map's VFO
        // marker needs. The operating manual suggests a 10 s poll for WSJT-X
        // and calls the default "rather chatty with QMX which probably is not
        // a problem" — a logger has to be chatty to track a knob.
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
        pendingKeyerChunks = []
        lock.unlock()
    }

    private func poll() {
        // IF = freq/mode/TX; KS = keyer speed (bidirectional speed sync). KY
        // asks the radio how much room is left in its send buffer, and is only
        // worth asking while there is more of a message waiting to go in.
        let hasQueue = lock.withLock { !pendingKeyerChunks.isEmpty }
        let commands = Self.cmdPollIF + Self.cmdPollKS + (hasQueue ? Self.cmdPollKY : "")
        currentTransport()?.write(commands)
    }

    private func currentTransport() -> (any SerialTransport)? {
        lock.withLock { transport }
    }

    // MARK: Commands (pure builders — unit tested)

    static let cmdPollIF = "IF;"
    static let cmdPollKS = "KS;"
    static let cmdPollKY = "KY;"
    static let cmdAutoInfoOff = "AI0;"

    /// `RX;` "immediately puts the radio into receive mode", which is the only
    /// documented way to cut a `KY` message short outside TS-480 compatibility
    /// mode. What the manual does *not* say is whether it also empties the send
    /// buffer, so abort additionally drops everything this driver has queued —
    /// which caps the worst case at one un-cancellable chunk rather than a
    /// whole message.
    static let cmdAbortSending = "RX;"

    static func cmdSetFrequency(hz: Int) -> String {
        String(format: "FA%011d;", max(0, hz))
    }

    /// The CAT manual gives `KS` no field width, only "the specified number of
    /// words per minute". Its own opening section names the spec it subsets —
    /// the Kenwood TS-480, whose PC control reference prints `KS` as three
    /// digits (`KSP1P1P1;`) — so three digits it is, zero-padded.
    static func cmdSetKeyerSpeed(wpm: Int) -> String {
        String(format: "KS%03d;", min(50, max(8, wpm)))
    }

    /// MD command for an app mode; "SSB" resolves to the conventional sideband
    /// for the frequency (USB at/above 10 MHz, LSB below). Returns nil for
    /// anything a QMX cannot do — notably FM, which has no MD digit at all —
    /// and never returns MD8, which would key the radio into SWR Tune.
    static func cmdSetMode(rawMode: String, frequencyHz: Int) -> String? {
        let digit: Character? = switch rawMode.uppercased() {
        case "CW": "3"
        case "USB": "2"
        case "LSB": "1"
        case "SSB": frequencyHz >= 10_000_000 ? "2" : "1"
        case "RTTY", "DIGI": "6"
        case "AM": "5"
        default: nil
        }
        return digit.map { "MD\($0);" }
    }

    /// Split text into `KY` commands of at most `keyerChunkLimit` characters.
    ///
    /// The cut falls *after* a space, not on it, so the chunks concatenate back
    /// to the original text exactly. That is the whole point: with TS-480 KY
    /// compatibility off — the QMX default, "KY TS480: NO" — each `KY` appends
    /// raw characters to one circular buffer rather than queueing a message, so
    /// a dropped delimiter sends `KE5CWKE5CW` rather than two calls.
    static func cmdKeyerText(_ text: String) -> [String] {
        var chunks: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            if remaining.count <= keyerChunkLimit {
                chunks.append(String(remaining))
                break
            }
            let window = remaining.prefix(keyerChunkLimit)
            if let space = window.lastIndex(of: " ") {
                let cut = window.index(after: space)
                chunks.append(String(remaining[..<cut]))
                remaining = remaining[cut...]
            } else {
                chunks.append(String(window))
                remaining = remaining.dropFirst(keyerChunkLimit)
            }
        }
        return chunks.map { "KY \($0);" }
    }

    func setFrequency(hz: Int) {
        // FA is VFO A. IF reports whichever VFO is in use, so a radio left on
        // VFO B reads back the frequency it is really on rather than this one.
        currentTransport()?.write(Self.cmdSetFrequency(hz: hz))
    }

    func setMode(rawMode: String) {
        let freq = lock.withLock { lastState?.frequencyHz ?? 14_000_000 }
        guard let cmd = Self.cmdSetMode(rawMode: rawMode, frequencyHz: freq) else { return }
        currentTransport()?.write(cmd)
    }

    func setKeyerSpeed(wpm: Int) {
        currentTransport()?.write(Self.cmdSetKeyerSpeed(wpm: wpm))
    }

    /// First chunk goes now; the rest wait for the radio to say it has room.
    func sendInternalKeyerText(_ text: String) {
        guard let transport = currentTransport() else { return }
        let chunks = Self.cmdKeyerText(text)
        guard let first = chunks.first else { return }
        lock.withLock { pendingKeyerChunks = Array(chunks.dropFirst()) }
        transport.write(first)
    }

    func stopInternalKeyer() {
        lock.withLock { pendingKeyerChunks.removeAll() }
        currentTransport()?.write(Self.cmdAbortSending)
    }

    // MARK: Response parsing (pure — unit tested)

    /// State of the `KY` send buffer, as the `KY;` query reports it.
    enum KeyerBufferStatus: Character, Sendable {
        /// Sending, buffer no more than 75% full — room for another chunk.
        case sending = "0"
        /// Sending, buffer more than 75% full — hold.
        case sendingNearlyFull = "1"
        /// Nothing being sent; the buffer is empty.
        case idle = "2"
    }

    /// `IF[f]*****+yyyyrx*00tmvspbd ;` — the TS-480 layout, field by field from
    /// the CAT manual's own list: 11-digit frequency [2..12], five spaces
    /// [13..17], RIT offset [18..22], RIT [23], XIT [24], memory bank [25],
    /// memory channel [26..27], **TX flag [28]**, **mode [29]**, receive VFO
    /// [30], scan [31], split [32], tone [33], tone number [34], a trailing
    /// space [35], terminator [36].
    ///
    /// Only the first 30 characters are required: a radio that truncates a line
    /// after the mode digit still yields everything the app logs, and one that
    /// truncates before it yields nothing rather than a guess.
    static func parseIF(_ response: String) -> RadioState? {
        let chars = Array(response)
        guard chars.count >= 30, chars[0] == "I", chars[1] == "F" else { return nil }
        guard let freq = Int(String(chars[2..<13])) else { return nil }
        // A mode of 8 is SWR Tune. It classifies as digital if allowed through,
        // which would put "SWR" in the mode column of whatever QSO was being
        // typed while the operator tuned up.
        guard let mode = QMXMode(rawValue: chars[29]), let rawMode = mode.rawMode else { return nil }
        return RadioState(
            frequencyHz: freq,
            rawMode: rawMode,
            isTransmitting: chars[28] == "1"
        )
    }

    /// `FAnnnnnnnnnnn;` → Hz.
    static func parseFA(_ response: String) -> Int? {
        guard response.hasPrefix("FA"), response.count >= 13 else { return nil }
        return Int(String(Array(response)[2..<13]))
    }

    /// `MDn;` → mode.
    static func parseMD(_ response: String) -> QMXMode? {
        guard response.hasPrefix("MD"), response.count >= 3 else { return nil }
        return QMXMode(rawValue: Array(response)[2])
    }

    /// `KSnnn;` → WPM. Read as one to three digits rather than a fixed field:
    /// the CAT manual documents the value and not its width, so a firmware that
    /// answers `KS28;` has not broken its own spec.
    static func parseKS(_ response: String) -> Int? {
        guard response.hasPrefix("KS") else { return nil }
        let digits = response.dropFirst(2).prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        return Int(digits)
    }

    /// `KYn;` → send-buffer state.
    static func parseKY(_ response: String) -> KeyerBufferStatus? {
        guard response.hasPrefix("KY"), response.count >= 3 else { return nil }
        return KeyerBufferStatus(rawValue: Array(response)[2])
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
            return
        }
        if let status = Self.parseKY(response) {
            releaseNextKeyerChunk(status: status)
        }
    }

    /// Hand the radio the next chunk, but only on its own word that there is
    /// room. `KY1;` (over 75% full) means wait for the next poll.
    private func releaseNextKeyerChunk(status: KeyerBufferStatus) {
        guard status != .sendingNearlyFull else { return }
        let next: String? = lock.withLock {
            pendingKeyerChunks.isEmpty ? nil : pendingKeyerChunks.removeFirst()
        }
        guard let next else { return }
        currentTransport()?.write(next)
    }
}

/// QMX mode digits (MD command). Raw values are the CAT protocol digits — note
/// there is no 4: a QMX has no FM.
enum QMXMode: Character, Sendable {
    case lsb = "1"
    case usb = "2"
    case cw = "3"
    case am = "5"
    case fsk = "6"
    case cwReverse = "7"
    /// Not an operating mode: MD8 "activates SWR Tune mode", i.e. transmits.
    case swrTune = "8"
    case fskReverse = "9"

    /// ADIF-style mode string for logging, or nil where the digit names
    /// something that is not a mode a QSO can be made on.
    var rawMode: String? {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .cw, .cwReverse: "CW"
        case .am: "AM"
        case .fsk, .fskReverse: "RTTY"
        case .swrTune: nil
        }
    }

    var modeClass: ModeClass? {
        rawMode.map { ModeClass.classify(rawMode: $0) }
    }
}
