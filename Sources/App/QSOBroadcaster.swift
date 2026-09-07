import Foundation
import Observation

/// Sends the log's changes to RUMlogNG — or any N1MM-compatible listener —
/// as N1MM contact packets over UDP (`N1MMContactBroadcast`), and keeps the
/// status line honest about what left this Mac. One per log window, like
/// the spot clients.
///
/// One paced queue carries everything: a live contact, a bulk edit's
/// hundreds of pairs, and a whole-log resend all leave one datagram at a
/// time with `pacing` between, so a burst cannot overrun the receiver's
/// socket buffer while a live contact still leaves within milliseconds.
/// The socket is `UDPSending` behind an injectable factory, so tests record
/// datagrams and nothing here touches the network.
@MainActor
@Observable
final class QSOBroadcaster {

    struct Config: Equatable, Sendable {
        var enabled: Bool
        var host: String
        var port: Int

        init(enabled: Bool = false, host: String = AppSettings.defaultQSOBroadcastHost,
             port: Int = AppSettings.defaultQSOBroadcastPort) {
            self.enabled = enabled
            self.host = host
            self.port = port
        }

        var destination: String { "\(host):\(port)" }
    }

    /// What the pane shows. UDP has no acknowledgement: `sent` is what left
    /// this Mac, never what RUMlogNG saved.
    enum Status: Equatable, Sendable {
        case off
        case ready(destination: String)
        case sent(count: Int, lastCall: String, at: Date, destination: String)
        case sending(done: Int, total: Int)
        case failed(String)

        var text: String {
            switch self {
            case .off:
                "Off — nothing is sent."
            case .ready(let destination):
                "Ready — \(destination). Nothing sent yet this session."
            case .sent(let count, let call, let at, let destination):
                "Sent \(call) at \(Self.clock.string(from: at))z to \(destination) · \(count) this session"
            case .sending(let done, let total):
                "Sending \(done.formatted()) of \(total.formatted())…"
            case .failed(let why):
                why
            }
        }

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        private static let clock: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            f.timeZone = TimeZone(identifier: "UTC")
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
    }

    private(set) var config = Config()
    /// Datagrams sent since the window opened.
    private(set) var sentCount = 0
    private(set) var lastSentCall: String?
    private(set) var lastSentAt: Date?
    private(set) var lastFailure: String?
    private(set) var wholeLogDone = 0
    private(set) var wholeLogTotal: Int?

    var isSendingWholeLog: Bool { wholeLogTotal != nil }

    var status: Status {
        guard config.enabled else { return .off }
        if let total = wholeLogTotal { return .sending(done: wholeLogDone, total: total) }
        if let failure = lastFailure { return .failed(failure) }
        if let call = lastSentCall, let at = lastSentAt {
            return .sent(count: sentCount, lastCall: call, at: at, destination: config.destination)
        }
        return .ready(destination: config.destination)
    }

    /// The socket, opened on first use. A test hands in a recorder.
    @ObservationIgnored var makeSender: (String, UInt16) throws -> any UDPSending = { try UDPSender(host: $0, port: $1) }
    /// `StationName` — this Mac's name.
    @ObservationIgnored var stationName: String = Host.current().localizedName ?? "Mac"
    /// Between datagrams. 2,000 rows in ten seconds; zero in tests.
    @ObservationIgnored var pacing: Duration = .milliseconds(5)
    @ObservationIgnored var now: () -> Date = Date.init

    @ObservationIgnored private var sender: (any UDPSending)?
    @ObservationIgnored private var queue: [Queued] = []
    @ObservationIgnored private var drain: Task<Void, Never>?

    private struct Queued {
        let packet: N1MMContactBroadcast.Packet
        let wholeLog: Bool
    }

    private var station: N1MMContactBroadcast.Station { .init(stationName: stationName) }

    // MARK: Configuration

    /// The window pushes the preference on appear and on every change.
    /// Off closes the socket and drops the queue; a new host or port closes
    /// it, and the next packet reopens.
    func configure(_ new: Config) {
        guard new != config else { return }
        let destinationChanged = new.host != config.host || new.port != config.port
        config = new
        if !new.enabled || destinationChanged { closeSender() }
        if !new.enabled {
            queue.removeAll()
            drain?.cancel()
            drain = nil
            finishWholeLog()
        }
        lastFailure = nil
    }

    /// The window is closing.
    func shutdown() {
        queue.removeAll()
        drain?.cancel()
        drain = nil
        finishWholeLog()
        closeSender()
    }

    // MARK: Sending

    /// A document change. Nothing happens while off — the scoring closure,
    /// which reads the engine's fold, is never called.
    func handle(_ change: QSOChange, log: ContestLog, contest: ContestDefinition?,
                scoring: (QSO) -> N1MMContactBroadcast.RowScoring) {
        guard config.enabled else { return }
        guard let contest else {
            lastFailure = "No contest rules installed for \(log.partyID) — nothing sent."
            return
        }
        enqueue(N1MMContactBroadcast.packets(for: change, log: log, contest: contest, station: station, scoring: scoring),
                wholeLog: false)
    }

    /// Every row again, oldest first — the catch-up. A second call while one
    /// is running stops it (the button's *Stop*); live changes queued behind
    /// it still go.
    func sendWholeLog(log: ContestLog, contest: ContestDefinition?,
                      scoring: (QSO) -> N1MMContactBroadcast.RowScoring) {
        guard config.enabled else { return }
        if isSendingWholeLog {
            stopWholeLog()
            return
        }
        guard let contest else {
            lastFailure = "No contest rules installed for \(log.partyID) — nothing sent."
            return
        }
        let packets = N1MMContactBroadcast.wholeLog(log: log, contest: contest, station: station, scoring: scoring)
        guard !packets.isEmpty else { return }
        wholeLogTotal = packets.count
        wholeLogDone = 0
        lastFailure = nil
        enqueue(packets, wholeLog: true)
    }

    func stopWholeLog() {
        queue.removeAll { $0.wholeLog }
        finishWholeLog()
    }

    /// Waits for the queue to empty — for tests.
    func flush() async {
        while let task = drain { await task.value }
    }

    // MARK: The queue

    private func enqueue(_ packets: [N1MMContactBroadcast.Packet], wholeLog: Bool) {
        guard !packets.isEmpty else { return }
        queue.append(contentsOf: packets.map { Queued(packet: $0, wholeLog: wholeLog) })
        guard drain == nil else { return }
        drain = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while config.enabled, !queue.isEmpty, !Task.isCancelled {
            let next = queue.removeFirst()
            guard let sender = openSenderIfNeeded() else {
                // A destination that cannot be opened drops what was queued:
                // retrying every packet against a bad host is noise, and the
                // next change tries again once the field has been fixed.
                queue.removeAll()
                finishWholeLog()
                break
            }
            let failuresBefore = sender.sendFailures.count
            sender.send(next.packet.data)
            let failures = sender.sendFailures
            if failures.count > failuresBefore {
                let reason = failures.lastErrno.map { String(cString: strerror($0)) } ?? "unknown error"
                lastFailure = "Send failed: \(reason)"
            } else {
                lastFailure = nil
                sentCount += 1
                lastSentCall = next.packet.call
                lastSentAt = now()
            }
            if next.wholeLog {
                wholeLogDone += 1
                if let total = wholeLogTotal, wholeLogDone >= total { finishWholeLog() }
            }
            if pacing > .zero {
                try? await Task.sleep(for: pacing)
            } else {
                await Task.yield()
            }
        }
        // A cancelled drain leaves `drain` to whoever cancelled it: `configure`
        // has already cleared it, and may have started a successor.
        if !Task.isCancelled { drain = nil }
    }

    private func openSenderIfNeeded() -> (any UDPSending)? {
        if let sender { return sender }
        guard let port = UInt16(exactly: config.port), port > 0 else {
            lastFailure = "Port \(config.port) is not between 1 and 65535."
            return nil
        }
        do {
            let opened = try makeSender(config.host, port)
            sender = opened
            return opened
        } catch {
            lastFailure = error.localizedDescription
            return nil
        }
    }

    private func closeSender() {
        sender?.close()
        sender = nil
    }

    private func finishWholeLog() {
        wholeLogTotal = nil
        wholeLogDone = 0
    }
}

extension AppSettings {
    /// The three preferences as the broadcaster takes them, in one place so
    /// the pane and the window cannot drift over which key drives what.
    var qsoBroadcast: QSOBroadcaster.Config {
        QSOBroadcaster.Config(enabled: qsoBroadcastEnabled, host: qsoBroadcastHost, port: qsoBroadcastPort)
    }
}
