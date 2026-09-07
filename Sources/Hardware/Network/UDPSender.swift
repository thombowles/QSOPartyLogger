import Foundation

/// A transport that reached the radio over IP, so a driver can open a second,
/// datagram channel to the same host. `TCPTransport` conforms; a mock in
/// tests can too.
protocol NetworkTransport: SerialTransport {
    var hostName: String { get }
}

/// What the Flex driver needs from a UDP socket, behind a protocol so tests
/// record packets instead of sending them. `Sendable`: the pacing thread
/// sends and the finish callback reads the failure count.
protocol UDPSending: AnyObject, Sendable {
    var localPort: UInt16 { get }
    /// "192.168.20.5:58432" — the address the packets leave from, for the
    /// transcript: a wrong interface (a VPN, a second NIC) shows up here.
    var localDescription: String { get }
    /// How many `send` calls the kernel refused, and the last errno — the
    /// difference between "the radio ignored the packets" and "they never
    /// left the Mac".
    var sendFailures: (count: Int, lastErrno: Int32?) { get }
    func send(_ data: Data)
    func close()
}

/// A connected BSD UDP socket — the Flex DAX audio stream's, and the RUMlogNG
/// contact broadcast's. Connected rather than bound to a chosen port,
/// so the kernel picks a free local port and the sandbox's network-client
/// entitlement suffices; the port is read back with `getsockname` so it can
/// be registered with the radio (`client udpport`), which then sees the
/// packets arrive from exactly that port.
final class UDPSender: UDPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32
    let localPort: UInt16
    let localDescription: String
    private var failureCount = 0
    private var lastFailure: Int32?

    var sendFailures: (count: Int, lastErrno: Int32?) {
        lock.withLock { (failureCount, lastFailure) }
    }

    enum UDPError: Error, LocalizedError {
        case resolve(String)
        case socket(Int32)
        case connect(Int32)

        var errorDescription: String? {
            switch self {
            case .resolve(let host):
                "Could not resolve \(host) for the audio stream."
            case .socket(let e), .connect(let e):
                "Could not open the audio stream socket: \(String(cString: strerror(e)))"
            }
        }
    }

    init(host: String, port: UInt16) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
            throw UDPError.resolve(host)
        }
        defer { freeaddrinfo(info) }
        let s = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
        guard s >= 0 else { throw UDPError.socket(errno) }
        // A subnet broadcast (192.168.1.255 — the addressing N1MM documents
        // for its contact packets) is refused by the kernel unless the
        // socket says it means to; harmless for a unicast destination.
        var broadcast: Int32 = 1
        _ = setsockopt(s, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
        guard Darwin.connect(s, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0 else {
            let e = errno
            Darwin.close(s)
            throw UDPError.connect(e)
        }
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(s, $0, &length)
            }
        }
        fd = s
        localPort = UInt16(bigEndian: address.sin_port)
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var ip = address.sin_addr
        let name = inet_ntop(AF_INET, &ip, &text, socklen_t(INET_ADDRSTRLEN)).map { String(cString: $0) } ?? "?"
        localDescription = "\(name):\(localPort)"
    }

    func send(_ data: Data) {
        let handle: Int32 = lock.withLock { fd }
        guard handle >= 0 else { return }
        let sent = data.withUnsafeBytes { buffer in
            Darwin.send(handle, buffer.baseAddress, buffer.count, 0)
        }
        if sent < 0 {
            let e = errno
            lock.withLock {
                failureCount += 1
                lastFailure = e
            }
        }
    }

    func close() {
        let handle: Int32 = lock.withLock {
            defer { fd = -1 }
            return fd
        }
        if handle >= 0 { Darwin.close(handle) }
    }

    deinit { close() }
}
