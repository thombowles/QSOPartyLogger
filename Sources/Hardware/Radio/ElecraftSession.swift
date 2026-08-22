import Foundation

/// The transport half of an Elecraft link: holds the port, polls it, and cuts
/// the incoming byte stream into complete `;`-terminated responses.
///
/// Split out of the driver because both Elecraft drivers need exactly this and
/// neither needs to think about it. It carries **no radio state** — no model, no
/// mode, no voice bookkeeping — which is what makes it testable on its own and
/// what keeps the two drivers' state machines the only place their behaviour can
/// differ.
///
/// `@unchecked Sendable` behind a lock, like every driver here: the poll timer
/// fires on its own queue and the transport calls back on another.
final class ElecraftSession: @unchecked Sendable {

    /// How often the radio is asked for its state. Fast enough for the band
    /// map's VFO marker; slow enough that the reference's warning about
    /// "continuous, fast polling" does not apply.
    static let pollInterval: TimeInterval = 0.5
    /// Delay before the first poll, so the setup commands land first.
    static let firstPollDelay: TimeInterval = 0.2
    /// A stream with no terminator in this many characters is garbage, and is
    /// dropped rather than grown without bound.
    static let maxBufferedCharacters = 4096

    private let lock = NSLock()
    private let pollQueue: DispatchQueue
    private var transport: (any SerialTransport)?
    private var pollTimer: (any DispatchSourceTimer)?
    private var rxBuffer = ""
    private var onResponse: (@Sendable (String) -> Void)?

    init(queueLabel: String) {
        pollQueue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }

    /// Attach to an open transport, write `setup` once, and begin polling.
    ///
    /// `setup` goes out **before** the timer starts, so the radio has been told
    /// how to answer before it is first asked. `onResponse` is called on the
    /// transport's own callback thread, once per complete response.
    func start(
        transport: any SerialTransport,
        setup: String,
        pollCommands: String,
        onResponse: @escaping @Sendable (String) -> Void
    ) {
        lock.lock()
        self.transport = transport
        self.onResponse = onResponse
        lock.unlock()

        transport.onReceive = { [weak self] data in
            self?.ingest(data)
        }
        transport.write(setup)

        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + Self.firstPollDelay, repeating: Self.pollInterval)
        timer.setEventHandler { [weak self] in
            self?.write(pollCommands)
        }
        timer.resume()
        lock.lock()
        pollTimer = timer
        lock.unlock()
    }

    /// Idempotent (Article 13): stopping a session that never started, or
    /// stopping twice, does nothing.
    func stop() {
        lock.lock()
        pollTimer?.cancel()
        pollTimer = nil
        transport = nil
        onResponse = nil
        rxBuffer = ""
        lock.unlock()
    }

    func write(_ text: String) {
        currentTransport()?.write(text)
    }

    private func currentTransport() -> (any SerialTransport)? {
        lock.withLock { transport }
    }

    /// Accumulate bytes and emit whole responses.
    ///
    /// ISO Latin-1, not UTF-8: an `IC` response is made of bytes with the high
    /// bit always set, and decoding those as UTF-8 would mangle them. Latin-1
    /// maps every byte to exactly one scalar in 0x00...0xFF, which is what
    /// `ElecraftProtocol.parseIC` reads.
    private func ingest(_ data: Data) {
        guard let text = String(data: data, encoding: .isoLatin1) else { return }
        lock.lock()
        rxBuffer += text
        var responses: [String] = []
        while let separator = rxBuffer.firstIndex(of: ";") {
            responses.append(String(rxBuffer[..<separator]) + ";")
            rxBuffer = String(rxBuffer[rxBuffer.index(after: separator)...])
        }
        // Guard against garbage floods with no terminator.
        if rxBuffer.count > Self.maxBufferedCharacters { rxBuffer = "" }
        let deliver = onResponse
        lock.unlock()

        for response in responses {
            deliver?(response)
        }
    }
}
