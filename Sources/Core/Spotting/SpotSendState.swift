import Foundation

/// Where one spot stands with one network. Shared by the cluster, the hub
/// and POTA so the receipt reads the same way whatever the transport.
enum SpotSendState: Equatable, Sendable {
    case idle
    case sending
    /// The network took the message. *Sent*, not *accepted*: the hub's page
    /// re-renders rather than reporting a status, and a node acknowledges
    /// nothing, so this is provisional until the network shows the spot back.
    case sent(Date)
    /// Seen back from the network — the board's own list, the node's echo.
    /// The only real confirmation.
    case confirmed
    case failed(String)

    var isSettled: Bool { self != .sending }

    var failure: String? {
        if case .failed(let why) = self { return why }
        return nil
    }
}
