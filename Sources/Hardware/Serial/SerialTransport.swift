import Foundation

/// Control lines usable for CW/PTT keying.
enum SerialLine: String, Codable, CaseIterable, Sendable {
    case dtr = "DTR"
    case rts = "RTS"
}

/// Minimal serial abstraction so radio drivers and the keyer are testable
/// without hardware.
protocol SerialTransport: AnyObject {
    var isOpen: Bool { get }
    /// Called on an arbitrary background queue as bytes arrive.
    var onReceive: (@Sendable (Data) -> Void)? { get set }

    func open(baudRate: Int) throws
    func close()
    func write(_ data: Data)
    /// Assert (true) or deassert (false) a control line.
    func set(line: SerialLine, active: Bool)
}

extension SerialTransport {
    func write(_ string: String) {
        write(Data(string.utf8))
    }
}

enum SerialError: Error, LocalizedError {
    case openFailed(path: String, errno: Int32)
    case notOpen

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let code):
            "Could not open \(path): \(String(cString: strerror(code)))"
        case .notOpen:
            "Serial port is not open."
        }
    }
}
