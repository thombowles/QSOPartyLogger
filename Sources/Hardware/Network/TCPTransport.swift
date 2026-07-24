import Foundation
import Network

/// `SerialTransport` over TCP — used for FlexRadio CAT and the DX cluster.
/// Control lines don't exist over TCP, so `set(line:)` is a no-op; the baud
/// rate passed to `open` is ignored. Writes issued before the connection is
/// ready are queued and flushed on connect, so callers can fire-and-forget
/// their setup commands exactly like they do on a serial port.
final class TCPTransport: SerialTransport, @unchecked Sendable {

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "org.b5n.QSOPartyLogger.tcp", qos: .userInitiated)
    private let lock = NSLock()
    private var connection: NWConnection?
    private var ready = false
    private var pending: [Data] = []

    var onReceive: (@Sendable (Data) -> Void)?
    /// Connection failed or was closed by the remote end (TCP-specific — the
    /// SerialTransport protocol has no equivalent signal).
    var onDisconnect: (@Sendable (String) -> Void)?
    /// Connection is stalled waiting for a viable path (Local Network
    /// permission, DNS, cable). Transient — the connection keeps retrying.
    var onWaiting: (@Sendable (String) -> Void)?

    var isOpen: Bool {
        lock.withLock { connection != nil }
    }

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 4992)!
    }

    func open(baudRate: Int) throws {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        lock.withLock {
            connection = conn
            ready = false
        }
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let queued: [Data] = self.lock.withLock {
                    self.ready = true
                    let p = self.pending
                    self.pending = []
                    return p
                }
                for data in queued {
                    conn.send(content: data, completion: .contentProcessed { _ in })
                }
                self.receiveLoop(conn)
            case .failed(let error):
                self.onDisconnect?(error.localizedDescription)
                self.close()
            case .waiting(let error):
                // NOT fatal: .waiting covers "no viable path *yet*" — most
                // importantly the unanswered macOS Local Network permission
                // prompt, plus DNS hiccups and unplugged interfaces.
                // NWConnection retries by itself when the path changes (e.g.
                // the user clicks Allow), so keep the connection alive and
                // just report why it's stalled.
                self.onWaiting?(error.localizedDescription)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func close() {
        let conn: NWConnection? = lock.withLock {
            let c = connection
            connection = nil
            ready = false
            pending = []
            return c
        }
        conn?.stateUpdateHandler = nil
        conn?.cancel()
    }

    func write(_ data: Data) {
        let conn: NWConnection? = lock.withLock {
            guard ready else {
                pending.append(data)
                return nil
            }
            return connection
        }
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }

    /// No control lines over TCP.
    func set(line: SerialLine, active: Bool) {}

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.onReceive?(data)
            }
            if isComplete || error != nil {
                if self.isOpen {
                    self.onDisconnect?(error?.localizedDescription ?? "Connection closed by remote host")
                    self.close()
                }
                return
            }
            self.receiveLoop(conn)
        }
    }
}
