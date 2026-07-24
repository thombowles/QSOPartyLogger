import Foundation

/// Radio support catalog. Adding a radio = write a `RadioDriver` and append a
/// descriptor here.
struct RadioDescriptor: Identifiable, Sendable {
    let id: String
    let displayName: String
    let defaultBaud: Int
    let baudRates: [Int]
    let makeDriver: @Sendable () -> any RadioDriver
}

enum RadioRegistry {
    static let all: [RadioDescriptor] = [
        RadioDescriptor(
            id: "elecraft-k3",
            displayName: "Elecraft K3 / K3S / KX3 / KX2",
            defaultBaud: 38400,
            baudRates: ElecraftK3Driver.baudRates,
            makeDriver: { ElecraftK3Driver() }
        )
    ]

    static func descriptor(id: String) -> RadioDescriptor? {
        all.first { $0.id == id }
    }
}
