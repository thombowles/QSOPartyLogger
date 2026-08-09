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
    /// True while a message is actually on the air, as distinct from waiting
    /// in `queue`. Guarded by `wake`, like the queue itself.
    private var transmitting = false
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

    /// Called once the queue has drained — the message is off the air. Lets
    /// the UI clear "sending" on real completion rather than on an estimate
    /// that a mid-message speed change would invalidate.
    var onFinished: (@Sendable () -> Void)?

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

    /// Nothing on the air and nothing waiting to go. Note this covers the
    /// message *being sent*, not just the queue behind it — a caller asking
    /// "are we done?" means the key, not the backlog.
    var isIdle: Bool {
        wake.lock()
        defer { wake.unlock() }
        return queue.isEmpty && !transmitting
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
            transmitting = true
            let text = queue.removeFirst()
            wake.unlock()

            transmit(text)

            wake.lock()
            transmitting = false
            // A message split into chunks finishes once, not once per chunk.
            let drained = queue.isEmpty
            wake.unlock()

            if drained {
                onFinished?()
            }
        }
    }

    private func transmit(_ text: String) {
        let currentConfig = lock.withLock { config }
        let events = KeyerTiming.schedule(text: text)
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
            play(event, until: &deadline)
        }
        transport?.set(line: currentConfig.keyLine, active: false)

        if currentConfig.pttEnabled, let ptt = currentConfig.pttLine {
            if !isAborted() {
                preciseSleep(ms: Double(currentConfig.pttTailMs))
            }
            transport?.set(line: ptt, active: false)
        }
    }

    /// Hold one element, reading the speed as late as possible so `⌘=` lands
    /// part-way through a message rather than at the end of it.
    ///
    /// A key-down element is held at the speed it began at: re-reading inside
    /// a dit or dah would put half of one speed and half of another on the
    /// air, and a malformed element is worse than a few milliseconds of lag.
    /// Key-up gaps have no such shape to spoil, so they re-read every dit —
    /// which is what keeps the worst case down to one dah rather than the
    /// seven dits of a word gap.
    ///
    /// `deadline` accumulates absolutely across the whole message, so slicing
    /// a gap into dits introduces no drift.
    private func play(_ event: KeyerTiming.KeyEvent, until deadline: inout UInt64) {
        let slice = event.keyDown ? event.dits : 1
        var remaining = event.dits
        while remaining > 1e-9 {
            if isAborted() { return }
            let step = min(remaining, slice)
            deadline += UInt64(step * KeyerTiming.ditMs(wpm: wpm) * 1_000_000)
            sleepUntil(uptimeNanos: deadline)
            remaining -= step
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
