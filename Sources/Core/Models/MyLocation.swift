import Foundation

/// Where this station is operating from for the active party.
enum MyLocation: Codable, Equatable, Hashable, Sendable {
    /// Inside the party's state. Multiple counties = operating on a county line (max 4).
    case inState(counties: [String])
    /// Outside the state: a US state, Canadian province, or "DX".
    case outOfState(location: String)

    /// The exchange values sent, one per logged row (county-line ops send each county).
    var sentExchanges: [String] {
        switch self {
        case .inState(let counties): counties
        case .outOfState(let location): [location]
        }
    }

    var isInState: Bool {
        if case .inState = self { return true }
        return false
    }

    var displayText: String {
        sentExchanges.joined(separator: "/")
    }
}
