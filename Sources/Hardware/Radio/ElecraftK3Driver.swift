import Foundation

/// Elecraft K3/K3S/KX3/KX2 CAT driver. ASCII commands terminated with ';' at
/// 38400-8N1 (default). Response formats verified against the Elecraft
/// Programmer's Reference revisions F2 and G5 (identical for these commands).
final class ElecraftK3Driver: RadioDriver, @unchecked Sendable {

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
    private var lastState: RadioState?
    private var lastWPM: Int?

    // MARK: Lifecycle

    func start(transport: any SerialTransport) {
        lock.lock()
        self.transport = transport
        lock.unlock()

        transport.onReceive = { [weak self] data in
            self?.ingest(data)
        }
        // AI0 = deterministic polling; K31 = K3 extended response mode.
        transport.write(Self.cmdAutoInfoOff + Self.cmdExtendedMode)

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
        lock.unlock()
    }

    private func poll() {
        // IF = freq/mode/TX; KS = keyer speed (bidirectional speed sync).
        currentTransport()?.write(Self.cmdPollIF + Self.cmdPollKS)
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

    static func cmdSetFrequency(hz: Int) -> String {
        String(format: "FA%011d;", max(0, hz))
    }

    static func cmdSetKeyerSpeed(wpm: Int) -> String {
        String(format: "KS%03d;", min(50, max(8, wpm)))
    }

    /// KY accepts ≤24 chars per command; chunk at word boundaries when possible.
    static func cmdKeyerText(_ text: String) -> [String] {
        var chunks: [String] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            if remaining.count <= 24 {
                chunks.append(String(remaining))
                break
            }
            let window = remaining.prefix(24)
            if let cut = window.lastIndex(of: " "), cut > window.startIndex {
                chunks.append(String(remaining[..<cut]))
                remaining = remaining[remaining.index(after: cut)...]
            } else {
                chunks.append(String(window))
                remaining = remaining.dropFirst(24)
            }
        }
        return chunks.map { "KY \($0);" }
    }

    /// Immediately terminate internal-keyer transmission (KY with '@').
    static let cmdKeyerStop = "KY @;"

    func setFrequency(hz: Int) {
        currentTransport()?.write(Self.cmdSetFrequency(hz: hz))
    }

    func setKeyerSpeed(wpm: Int) {
        currentTransport()?.write(Self.cmdSetKeyerSpeed(wpm: wpm))
    }

    func sendInternalKeyerText(_ text: String) {
        guard let transport = currentTransport() else { return }
        for cmd in Self.cmdKeyerText(text) {
            transport.write(cmd)
        }
    }

    func stopInternalKeyer() {
        currentTransport()?.write(Self.cmdKeyerStop)
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
            mode: mode,
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
        }
    }
}
