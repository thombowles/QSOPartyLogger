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
    /// DTR/RTS line keying is possible (serial radios only).
    let supportsDirectKeying: Bool
    /// How the keyer picker names *this* radio's own keyer. The shared
    /// `KeyerBackend` setting is radio-neutral (Article 11), so the model's
    /// command name lives here rather than in the enum or the UI: keep the
    /// neutral "Radio keyer" prefix and add the command in parentheses.
    let keyerLabel: String
    let makeDriver: @Sendable () -> any RadioDriver
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
            keyerLabel: "Radio keyer (KY)",
            makeDriver: { ElecraftK3Driver() }
        ),
        RadioDescriptor(
            id: "flex-6000",
            displayName: "FlexRadio 6000/8000 (TCP)",
            connection: .network(defaultPort: FlexRadioDriver.defaultPort),
            defaultBaud: 0,
            baudRates: [],
            supportsDirectKeying: false,
            keyerLabel: "Radio keyer (CWX)",
            makeDriver: { FlexRadioDriver() }
        ),
    ]

    static func descriptor(id: String) -> RadioDescriptor? {
        all.first { $0.id == id }
    }
}
