import Foundation

/// Sends prepared packets one every `interval` on a dedicated thread with
/// absolute deadlines — the keyer's `sleepUntil` discipline — so a long clip
/// does not drift against the radio's clock. `stop()` ends it between
/// packets; `onFinished` is called only when every packet went out, so the
/// caller can unkey knowing the audio is really over.
final class FlexDAXStreamer: @unchecked Sendable {
    private let sender: any UDPSending
    private let interval: TimeInterval
    private let lock = NSLock()
    private var stopped = false
    private var thread: Thread?

    init(sender: any UDPSending, intervalSeconds: TimeInterval) {
        self.sender = sender
        self.interval = intervalSeconds
    }

    /// Single-use: a `stop()` that lands before `stream` ends it before the
    /// first packet, so a play the driver has already abandoned never goes out.
    func stream(_ packets: [Data],
                onFirstPacket: @escaping @Sendable () -> Void,
                onFinished: @escaping @Sendable () -> Void) {
        let t = Thread { [self] in
            var deadline = DispatchTime.now().uptimeNanoseconds
            let step = UInt64(interval * 1_000_000_000)
            for (i, packet) in packets.enumerated() {
                if isStopped { return }
                sender.send(packet)
                if i == 0 { onFirstPacket() }
                deadline += step
                sleepUntil(uptimeNanos: deadline)
            }
            if !isStopped { onFinished() }
        }
        t.name = "org.b5n.QSOPartyLogger.dax"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        lock.withLock { stopped = true }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    /// Coarse sleep to within a millisecond, then a short spin — the same
    /// discipline as `CWKeyer`, at a far coarser 5.3 ms grid.
    private func sleepUntil(uptimeNanos: UInt64) {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= uptimeNanos { return }
            let remaining = uptimeNanos - now
            if remaining > 1_500_000 {
                usleep(UInt32((remaining - 1_000_000) / 1_000))
            } else if remaining > 50_000 {
                usleep(20)
            }
        }
    }
}
