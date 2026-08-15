import Foundation

/// What one Post became: a state per network, and how it reads. Pure — the
/// dispatcher writes it, the capsule in the station strip shows it. It
/// closes a standing gap: the hub's "confirmed on the board" was tracked and
/// never shown.
struct SpotReceipt: Equatable, Sendable {
    var station: String
    var frequencyKHz: Double
    var states: [SpotNetwork: SpotSendState]
    /// When the latest state landed. Visibility runs from here.
    var changedAt: Date
    var dismissedAt: Date?

    enum Tint: Equatable, Sendable {
        /// Something still in flight, or sent and not yet shown back.
        case pending
        /// Every network showed the spot back.
        case good
        /// A network failed.
        case bad
    }

    /// Long enough to read; the consoles keep the record.
    static let quietWindow: TimeInterval = 12
    /// Long enough to read and act on.
    static let failureWindow: TimeInterval = 60

    init(
        station: String, frequencyKHz: Double, states: [SpotNetwork: SpotSendState],
        changedAt: Date, dismissedAt: Date? = nil
    ) {
        self.station = station
        self.frequencyKHz = frequencyKHz
        self.states = states
        self.changedAt = changedAt
        self.dismissedAt = dismissedAt
    }

    /// The networks this send went to, in list order.
    var networks: [SpotNetwork] { SpotNetwork.allCases.filter { states[$0] != nil } }

    var failedNetworks: [SpotNetwork] { networks.filter { states[$0]?.failure != nil } }

    var isSettled: Bool { !states.values.contains(.sending) }

    var tint: Tint {
        if !failedNetworks.isEmpty { return .bad }
        if !states.isEmpty, states.values.allSatisfy({ $0 == .confirmed }) { return .good }
        return .pending
    }

    var title: String { "\(station) \(SpotFrequency.text(kHz: frequencyKHz))" }

    func line(for network: SpotNetwork) -> String {
        let name = network.shortName
        switch states[network] ?? .idle {
        case .idle:
            return "\(name) — waiting"
        case .sending:
            return "\(name) — sending…"
        case .sent:
            switch network {
            case .cluster: return "\(name) — sent to the node"
            case .hub: return "\(name) — sent, watching the board"
            case .pota: return "\(name) — sent, watching pota.app"
            }
        case .confirmed:
            switch network {
            case .cluster: return "\(name) — echoed by the node"
            case .hub: return "\(name) — on the board"
            case .pota: return "\(name) — on pota.app"
            }
        case .failed(let why):
            return "\(name) — \(why)"
        }
    }

    var summary: String { networks.map(line(for:)).joined(separator: " · ") }

    /// Shown from the last change for a quiet window, or a longer one when
    /// something failed; hidden by a dismissal until the next change — so a
    /// verdict that lands late, the hub's poll saying the spot never
    /// appeared, still surfaces.
    func isVisible(now: Date) -> Bool {
        if let dismissedAt, changedAt <= dismissedAt { return false }
        let window = failedNetworks.isEmpty ? Self.quietWindow : Self.failureWindow
        return now.timeIntervalSince(changedAt) < window
    }

    /// Only networks this send went to take updates, and an unchanged state
    /// does not re-arm the window.
    mutating func set(_ state: SpotSendState, for network: SpotNetwork, at now: Date) {
        guard let current = states[network], current != state else { return }
        states[network] = state
        changedAt = now
    }

    mutating func dismiss(at now: Date) {
        dismissedAt = now
    }
}
