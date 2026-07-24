import Foundation

/// POSIX/termios serial port (pattern proven in K3MacroKeyer). 8N1, raw mode.
///
/// Keying safety: control lines are explicitly deasserted right after open —
/// if DTR/RTS are wired as CW key/PTT (K3 CONFIG:PTT-KEY), asserting them at
/// open would key the transmitter.
final class SerialPort: SerialTransport, @unchecked Sendable {
    let path: String
    private var fd: Int32 = -1
    private var readSource: (any DispatchSourceRead)?
    private let queue = DispatchQueue(label: "org.b5n.QSOPartyLogger.serial", qos: .userInitiated)

    var onReceive: (@Sendable (Data) -> Void)?

    var isOpen: Bool {
        queue.sync { fd != -1 }
    }

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    func open(baudRate: Int) throws {
        try queue.sync {
            guard fd == -1 else { return }
            let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard descriptor != -1 else {
                throw SerialError.openFailed(path: path, errno: errno)
            }

            var options = termios()
            tcgetattr(descriptor, &options)
            cfsetispeed(&options, speed_t(baudRate))
            cfsetospeed(&options, speed_t(baudRate))
            // 8N1, receiver on, no modem control.
            options.c_cflag &= ~UInt(PARENB)
            options.c_cflag &= ~UInt(CSTOPB)
            options.c_cflag &= ~UInt(CSIZE)
            options.c_cflag |= UInt(CS8)
            options.c_cflag |= UInt(CREAD)
            options.c_cflag |= UInt(CLOCAL)
            // Raw input/output.
            options.c_iflag &= ~UInt(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON)
            options.c_lflag &= ~UInt(ICANON | ECHO | ECHOE | ISIG)
            options.c_oflag &= ~UInt(OPOST)
            // Non-blocking reads; the dispatch source tells us when data exists.
            options.c_cc.16 = 0  // VMIN
            options.c_cc.17 = 0  // VTIME
            tcsetattr(descriptor, TCSANOW, &options)

            // Deassert both control lines (see keying-safety note above).
            var lines: Int32 = TIOCM_DTR | TIOCM_RTS
            _ = ioctl(descriptor, TIOCMBIC, &lines)

            fd = descriptor

            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in
                self?.drainInput()
            }
            source.resume()
            readSource = source
        }
    }

    func close() {
        queue.sync {
            readSource?.cancel()
            readSource = nil
            if fd != -1 {
                Darwin.close(fd)
                fd = -1
            }
        }
    }

    func write(_ data: Data) {
        queue.async { [self] in
            guard fd != -1 else { return }
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if n > 0 {
                        offset += n
                    } else if errno == EAGAIN {
                        usleep(1000)
                    } else {
                        break
                    }
                }
            }
        }
    }

    /// Synchronous so the CW keyer's edge timing isn't queued behind writes.
    func set(line: SerialLine, active: Bool) {
        var bits: Int32 = line == .dtr ? TIOCM_DTR : TIOCM_RTS
        let descriptor = queue.sync { fd }
        guard descriptor != -1 else { return }
        _ = ioctl(descriptor, active ? TIOCMBIS : TIOCMBIC, &bits)
    }

    private func drainInput() {
        guard fd != -1 else { return }
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                onReceive?(Data(buffer[0..<n]))
            } else {
                break
            }
        }
    }
}
