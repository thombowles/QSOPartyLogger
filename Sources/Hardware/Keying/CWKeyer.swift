import Foundation

/// Direct CW keying by toggling serial control lines (DTR/RTS) with software
/// timing — the N1MM-style keying the K3 supports via CONFIG:PTT-KEY.
///
/// Timing runs on a dedicated `.userInteractive` thread against absolute
/// deadlines (coarse sleep + fine spin), giving sub-millisecond edge accuracy
/// at contest speeds.
final class CWKeyer: CWSender, @unchecked Sendable {

    private let lock = NSLock()
    private let wake = NSCondition()
    private var queue: [String] = []
    private var aborted = false
    private var running = true
    private var thread: Thread?

    private weak var transport: (any SerialTransport)?
    private var config: KeyerLineConfig

    private var _wpm: Int
    var wpm: Int {
        get { lock.withLock { _wpm } }
        set { lock.withLock { _wpm = min(50, max(8, newValue)) } }
    }

    /// Called with each chunk as it starts sending (for UI display).
    var onSending: (@Sendable (String) -> Void)?

    init(transport: any SerialTransport, config: KeyerLineConfig, wpm: Int = 20) {
        self.transport = transport
        self.config = config
        self._wpm = min(50, max(8, wpm))
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "org.b5n.QSOPartyLogger.cwkeyer"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
    }

    deinit {
        shutdown()
    }

    func updateConfig(_ config: KeyerLineConfig) {
        lock.withLock { self.config = config }
        keyUp()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wake.lock()
        queue.append(trimmed)
        wake.signal()
        wake.unlock()
    }

    /// Immediate stop: clears the queue and forces key/PTT up.
    func abort() {
        wake.lock()
        queue.removeAll()
        aborted = true
        wake.signal()
        wake.unlock()
        keyUp()
    }

    func shutdown() {
        wake.lock()
        running = false
        queue.removeAll()
        aborted = true
        wake.signal()
        wake.unlock()
        keyUp()
    }

    var isIdle: Bool {
        wake.lock()
        defer { wake.unlock() }
        return queue.isEmpty
    }

    // MARK: Thread body

    private func runLoop() {
        while true {
            wake.lock()
            while queue.isEmpty && running {
                wake.wait()
            }
            guard running else {
                wake.unlock()
                return
            }
            aborted = false
            let text = queue.removeFirst()
            wake.unlock()

            transmit(text)
        }
    }

    private func transmit(_ text: String) {
        let (currentConfig, speed) = lock.withLock { (config, _wpm) }
        let events = KeyerTiming.schedule(text: text, wpm: speed)
        guard !events.isEmpty else { return }

        onSending?(text)

        if currentConfig.pttEnabled, let ptt = currentConfig.pttLine {
            transport?.set(line: ptt, active: true)
            preciseSleep(ms: Double(currentConfig.pttLeadMs))
        }

        var deadline = DispatchTime.now().uptimeNanoseconds
        for event in events {
            if isAborted() { break }
            transport?.set(line: currentConfig.keyLine, active: event.keyDown)
            deadline += UInt64(event.durationMs * 1_000_000)
            sleepUntil(uptimeNanos: deadline)
        }
        transport?.set(line: currentConfig.keyLine, active: false)

        if currentConfig.pttEnabled, let ptt = currentConfig.pttLine {
            if !isAborted() {
                preciseSleep(ms: Double(currentConfig.pttTailMs))
            }
            transport?.set(line: ptt, active: false)
        }
    }

    private func isAborted() -> Bool {
        wake.lock()
        defer { wake.unlock() }
        return aborted
    }

    private func keyUp() {
        let currentConfig = lock.withLock { config }
        transport?.set(line: currentConfig.keyLine, active: false)
        if let ptt = currentConfig.pttLine {
            transport?.set(line: ptt, active: false)
        }
    }

    // MARK: Precision timing

    private func sleepUntil(uptimeNanos: UInt64) {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= uptimeNanos { return }
            let remaining = uptimeNanos - now
            if remaining > 1_500_000 {
                // Coarse sleep to within ~1 ms of the deadline.
                usleep(UInt32((remaining - 1_000_000) / 1_000))
            } else if remaining > 50_000 {
                usleep(20)
            }
            // Final <50 µs: spin on the clock.
        }
    }

    private func preciseSleep(ms: Double) {
        sleepUntil(uptimeNanos: DispatchTime.now().uptimeNanoseconds + UInt64(ms * 1_000_000))
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
