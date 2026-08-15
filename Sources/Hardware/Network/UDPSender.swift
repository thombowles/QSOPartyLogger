import Foundation

/// A transport that reached the radio over IP, so a driver can open a second,
/// datagram channel to the same host. `TCPTransport` conforms; a mock in
/// tests can too.
protocol NetworkTransport: SerialTransport {
    var hostName: String { get }
}

/// What the Flex driver needs from a UDP socket, behind a protocol so tests
/// record packets instead of sending them.
protocol UDPSending: AnyObject {
    var localPort: UInt16 { get }
    func send(_ data: Data)
    func close()
}

/// A connected BSD UDP socket. Connected rather than bound to a chosen port,
/// so the kernel picks a free local port and the sandbox's network-client
/// entitlement suffices; the port is read back with `getsockname` so it can
/// be registered with the radio (`client udpport`), which then sees the
/// packets arrive from exactly that port.
final class UDPSender: UDPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32
    let localPort: UInt16

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
    }

    func send(_ data: Data) {
        let handle: Int32 = lock.withLock { fd }
        guard handle >= 0 else { return }
        data.withUnsafeBytes { buffer in
            _ = Darwin.send(handle, buffer.baseAddress, buffer.count, 0)
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
