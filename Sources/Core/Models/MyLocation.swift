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

    /// The single token this station reports as its own location — what the
    /// Cabrillo `LOCATION:` header and the ADIF state field are asking for.
    ///
    /// For a party with a home region that is the party's own state, however
    /// many counties are being sat on. For a party without one it is the
    /// entrant's own token, because there is no host state to name: an NAQP
    /// operator in Mexico is `XE`, not the pseudo-state that stands in for
    /// "North America" in the schema.
    func entrantToken(party: PartyDefinition) -> String {
        switch self {
        case .inState(let counties):
            party.hasHomeRegion
                ? party.homeState
                : (counties.first?.uppercased() ?? party.homeState)
        case .outOfState(let location):
            location.uppercased()
        }
    }
}
