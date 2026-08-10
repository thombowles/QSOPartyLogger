import Foundation

/// FlexRadio Signature (6000/8000 series) driver over the SmartSDR TCP API
/// (default port 4992). Unlike the K3's poll loop, Flex status is push-based:
/// subscribe once at start, then parse `S<handle>|…` status lines as they
/// arrive. CW is keyed through CWX, the radio's built-in macro keyer.
///
/// Wire format (SmartSDR TCP/IP API):
///   → `C<seq>|<command>`            command
///   ← `R<seq>|<code>|<message>`     response (0 = OK)
///   ← `S<handle>|<status text>`     subscribed status update
///   ← `V…` / `H…` / `M…`            version / handle / message on connect
final class FlexRadioDriver: InternalKeyerDriver, @unchecked Sendable {

    static let defaultPort: UInt16 = 4992

    private let lock = NSLock()
    private var transport: (any SerialTransport)?
    private var rxBuffer = ""
    private var seq = 0
    private var slices: [Int: SliceState] = [:]
    private var transmitting = false
    private var lastPublished: RadioState?
    private var lastWPM: Int?
    private var pingTimer: (any DispatchSourceTimer)?
    private let timerQueue = DispatchQueue(label: "org.b5n.QSOPartyLogger.flexping")

    var onStateChange: (@Sendable (RadioState) -> Void)?
    var onKeyerSpeedChange: (@Sendable (Int) -> Void)?

    private struct SliceState {
        var frequencyHz: Int?
        var rawMode: String?
        var active: Bool?
    }

    /// Parsed fields of one slice status delta (nil = key absent, keep old).
    struct SliceUpdate: Equatable {
        var index: Int
        var frequencyHz: Int?
        var rawMode: String?
        var active: Bool?
    }

    // MARK: Lifecycle

    func start(transport: any SerialTransport) {
        lock.withLock { self.transport = transport }
        transport.onReceive = { [weak self] data in
            self?.ingest(data)
        }
        // No `client program` handshake: the radio rejects unregistered
        // program names ("unknown client program"), and nothing needs it.
        sendCommand("sub slice all")
        sendCommand("sub tx all")
        sendCommand("sub cwx all")

        // Heartbeat: keeps NAT/idle timeouts away on quiet receivers.
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.sendCommand("ping")
        }
        timer.resume()
        lock.withLock { pingTimer = timer }
    }

    func stop() {
        lock.lock()
        pingTimer?.cancel()
        pingTimer = nil
        transport = nil
        rxBuffer = ""
        slices = [:]
        transmitting = false
        lastPublished = nil
        lastWPM = nil
        lock.unlock()
    }

    private func sendCommand(_ body: String) {
        let n: Int = lock.withLock {
            seq += 1
            return seq
        }
        currentTransport()?.write("C\(n)|\(body)\n")
    }

    private func currentTransport() -> (any SerialTransport)? {
        lock.withLock { transport }
    }

    // MARK: RadioDriver commands

    func setFrequency(hz: Int) {
        let idx = activeSliceIndexOrDefault()
        sendCommand(Self.cmdTune(sliceIndex: idx, hz: hz))
        // SmartSDR broadcasts status for changes made elsewhere (VFO knob,
        // other clients) but does NOT echo back to the commanding client —
        // like FlexLib, we apply our own commands to our model directly.
        applyLocal(index: idx) { $0.frequencyHz = hz }
    }

    func setMode(rawMode: String) {
        let freq: Int = lock.withLock { lastPublished?.frequencyHz ?? 14_000_000 }
        guard let flexMode = Self.flexMode(forAppMode: rawMode, frequencyHz: freq) else { return }
        let idx = activeSliceIndexOrDefault()
        sendCommand(Self.cmdSetMode(sliceIndex: idx, flexMode: flexMode))
        applyLocal(index: idx) { $0.rawMode = Self.appRawMode(flexMode: flexMode) }
    }

    /// Apply a self-commanded change to the local slice model and publish —
    /// a later radio echo (if any) dedupes against `lastPublished`.
    private func applyLocal(index: Int, _ mutate: (inout SliceState) -> Void) {
        lock.lock()
        var slice = slices[index] ?? SliceState()
        mutate(&slice)
        slices[index] = slice
        let state = publishableStateLocked()
        lock.unlock()
        if let state { onStateChange?(state) }
    }

    func setKeyerSpeed(wpm: Int) {
        sendCommand(Self.cmdKeyerSpeed(wpm: wpm))
    }

    func sendInternalKeyerText(_ text: String) {
        sendCommand(Self.cmdSendCW(text))
    }

    func stopInternalKeyer() {
        sendCommand("cwx clear")
    }

    private func activeSliceIndexOrDefault() -> Int {
        lock.withLock { slices.first(where: { $0.value.active == true })?.key ?? 0 }
    }

    // MARK: Command builders (pure — unit tested)

    static func cmdTune(sliceIndex: Int, hz: Int) -> String {
        String(format: "slice tune %d %.6f", sliceIndex, Double(hz) / 1_000_000)
    }

    static func cmdSetMode(sliceIndex: Int, flexMode: String) -> String {
        "slice set \(sliceIndex) mode=\(flexMode)"
    }

    /// `cw wpm`, **not** `cwx wpm`. Every other verb the CWX page documents is
    /// `cwx <verb>`; WPM alone is not, and it is printed the same way on the
    /// `cw` page — see `docs/research/flex_smartsdr_tcpip_api_cw.txt`. The
    /// radio answers an unknown command with an error rather than a complaint
    /// the app would notice, so the `cwx wpm` this used to send simply meant
    /// speed never changed at all.
    static func cmdKeyerSpeed(wpm: Int) -> String {
        "cw wpm \(min(50, max(8, wpm)))"
    }

    /// CWX rejects embedded quotes — strip rather than escape.
    static func cmdSendCW(_ text: String) -> String {
        "cwx send \"\(text.replacingOccurrences(of: "\"", with: ""))\""
    }

    // MARK: Mode mapping

    /// Flex mode → ADIF-style app mode.
    static func appRawMode(flexMode: String) -> String {
        switch flexMode.uppercased() {
        case "DIGU", "DIGL": "RTTY"
        default: flexMode.uppercased()
        }
    }

    /// App mode → Flex mode; "SSB" resolves to the conventional sideband for
    /// the frequency (USB at/above 10 MHz, LSB below).
    static func flexMode(forAppMode mode: String, frequencyHz: Int) -> String? {
        switch mode.uppercased() {
        case "CW": "CW"
        case "USB": "USB"
        case "LSB": "LSB"
        case "SSB": frequencyHz >= 10_000_000 ? "USB" : "LSB"
        case "RTTY", "DIGI": "DIGU"
        case "AM": "AM"
        case "FM": "FM"
        default: nil
        }
    }

    // MARK: Status parsing (pure — unit tested)

    /// `slice <n> key=value …` → delta of the fields the app cares about.
    static func parseSlice(_ status: String) -> SliceUpdate? {
        let tokens = status.split(separator: " ")
        guard tokens.count >= 2, tokens[0] == "slice", let index = Int(tokens[1]) else { return nil }
        var update = SliceUpdate(index: index)
        for token in tokens.dropFirst(2) {
            let kv = token.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "RF_frequency":
                if let mhz = Double(kv[1]) {
                    update.frequencyHz = Int((mhz * 1_000_000).rounded())
                }
            case "mode":
                update.rawMode = appRawMode(flexMode: String(kv[1]))
            case "active":
                update.active = kv[1] == "1"
            default:
                break
            }
        }
        return update
    }

    /// `interlock … state=<STATE> …` → is the radio transmitting?
    static func parseInterlockTransmitting(_ status: String) -> Bool? {
        guard status == "interlock" || status.hasPrefix("interlock ") else { return nil }
        guard let stateToken = status.split(separator: " ").first(where: { $0.hasPrefix("state=") }) else {
            return nil
        }
        return stateToken.dropFirst("state=".count) == "TRANSMITTING"
    }

    /// `cwx … wpm=<n> …` → keyer speed (radio-side changes sync the app).
    static func parseCWXSpeed(_ status: String) -> Int? {
        guard status == "cwx" || status.hasPrefix("cwx ") else { return nil }
        guard let wpmToken = status.split(separator: " ").first(where: { $0.hasPrefix("wpm=") }) else {
            return nil
        }
        return Int(wpmToken.dropFirst("wpm=".count))
    }

    // MARK: RX plumbing

    private func ingest(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return }
        lock.lock()
        rxBuffer += text
        var lines: [String] = []
        while let nl = rxBuffer.firstIndex(of: "\n") {
            lines.append(String(rxBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines))
            rxBuffer = String(rxBuffer[rxBuffer.index(after: nl)...])
        }
        if rxBuffer.count > 8192 { rxBuffer = "" }
        lock.unlock()

        for line in lines where !line.isEmpty {
            handle(line: line)
        }
    }

    private func handle(line: String) {
        // Only S (status) lines matter; V/H/M/R lines are handshake + acks.
        guard line.hasPrefix("S"), let bar = line.firstIndex(of: "|") else { return }
        let status = String(line[line.index(after: bar)...])

        if let update = Self.parseSlice(status) {
            apply(update: update)
        } else if let tx = Self.parseInterlockTransmitting(status) {
            lock.lock()
            transmitting = tx
            let state = publishableStateLocked()
            lock.unlock()
            if let state { onStateChange?(state) }
        } else if let wpm = Self.parseCWXSpeed(status) {
            lock.lock()
            let changed = wpm != lastWPM
            lastWPM = wpm
            lock.unlock()
            if changed { onKeyerSpeedChange?(wpm) }
        }
    }

    private func apply(update: SliceUpdate) {
        lock.lock()
        var slice = slices[update.index] ?? SliceState()
        if let f = update.frequencyHz { slice.frequencyHz = f }
        if let m = update.rawMode { slice.rawMode = m }
        if let a = update.active { slice.active = a }
        slices[update.index] = slice
        let state = publishableStateLocked()
        lock.unlock()
        if let state { onStateChange?(state) }
    }

    /// Build the app-facing state from the active slice; nil when nothing
    /// changed or no slice is active yet. Caller must hold the lock.
    private func publishableStateLocked() -> RadioState? {
        guard let active = slices.values.first(where: { $0.active == true }),
              let freq = active.frequencyHz else { return nil }
        let state = RadioState(
            frequencyHz: freq,
            rawMode: active.rawMode ?? "USB",
            isTransmitting: transmitting
        )
        guard state != lastPublished else { return nil }
        lastPublished = state
        return state
    }
}
