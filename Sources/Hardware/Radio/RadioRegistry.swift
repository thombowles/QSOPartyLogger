import Foundation

/// Radio support catalog. Adding a radio = write a `RadioDriver` and append a
/// descriptor here.
struct RadioDescriptor: Identifiable, Sendable {
    /// How the app reaches the radio's CAT interface.
    enum Connection: Equatable, Sendable {
        case serial
        case network(defaultPort: UInt16)
    }

    let id: String
    let displayName: String
    let connection: Connection
    let defaultBaud: Int
    let baudRates: [Int]
    /// DTR/RTS line keying is possible (serial radios only) — and where it is,
    /// it is the *only* CW path (Article 11). A descriptor with this false
    /// must make a driver conforming to `InternalKeyerDriver`, or the radio
    /// has no way to send at all; `RadioRegistryTests` checks both halves.
    let supportsDirectKeying: Bool
    let makeDriver: @Sendable () -> any RadioDriver
}

extension RadioDescriptor {
    /// The port this radio's CAT interface listens on, or `nil` when it is
    /// reached over a serial port. The UI asks the descriptor for the number
    /// rather than printing a model's port itself (Article 10).
    var defaultNetworkPort: UInt16? {
        if case .network(let port) = connection { port } else { nil }
    }
}

enum RadioRegistry {
    static let all: [RadioDescriptor] = [
        RadioDescriptor(
            id: "elecraft-k3",
            displayName: "Elecraft K3 / K3S / KX3 / KX2",
            connection: .serial,
            defaultBaud: 38400,
            baudRates: ElecraftK3Driver.baudRates,
            supportsDirectKeying: true,
            makeDriver: { ElecraftK3Driver() }
        ),
        RadioDescriptor(
            id: "qrplabs-qmx",
            displayName: "QRP Labs QMX+ / QMX",
            connection: .serial,
            defaultBaud: 9600,
            baudRates: QRPLabsQMXDriver.baudRates,
            supportsDirectKeying: true,
            makeDriver: { QRPLabsQMXDriver() }
        ),
        RadioDescriptor(
            id: "flex-6000",
            displayName: "FlexRadio 6000/8000 (TCP)",
            connection: .network(defaultPort: FlexRadioDriver.defaultPort),
            defaultBaud: 0,
            baudRates: [],
            supportsDirectKeying: false,
            makeDriver: { FlexRadioDriver() }
        ),
    ]

    /// The radio a fresh install starts on. It lives here rather than in
    /// `AppSettings` so that no radio `id` appears in the app layer
    /// (Article 10); `RadioRegistryTests` checks it still resolves.
    static let defaultRadioID = "elecraft-k3"

    /// Starting value for the shared serial baud preference — the default
    /// radio's own default rate. Non-optional, unlike the TCP port: `connect`
    /// opens the port at exactly this rate with no range check, so there is no
    /// later opportunity to substitute the radio's own.
    static var defaultBaud: Int {
        descriptor(id: defaultRadioID)?.defaultBaud ?? 9600
    }

    /// Starting value for the shared network-CAT port preference, and the
    /// number the port field's help text quotes — the first network radio's
    /// own port. `nil` in a serial-only catalog, which costs nothing:
    /// `RadioController.connect` substitutes the connected radio's port
    /// whenever the stored value is out of range, so no caller needs a
    /// model-specific fallback of its own.
    static var defaultNetworkPort: UInt16? {
        all.compactMap(\.defaultNetworkPort).first
    }

    static func descriptor(id: String) -> RadioDescriptor? {
        all.first { $0.id == id }
    }
}
