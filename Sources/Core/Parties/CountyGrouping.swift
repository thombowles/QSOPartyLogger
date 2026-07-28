import Foundation

/// A party's counties arranged for display: by member contest, then by state.
///
/// One flat list of 422 codes is unreadable and, worse, unactionable — it can't
/// tell you that the three you are missing are the whole of Delaware. Grouping
/// is derived from `combines` and from each county's own `state`, so it is one
/// rule for every party rather than a special case for the combined entry.
enum CountyGrouping {

    struct StateGroup: Identifiable, Equatable, Sendable {
        let state: String
        let counties: [County]
        var id: String { state }
    }

    struct PartyGroup: Identifiable, Equatable, Sendable {
        let partyID: String
        /// `nil` for an ordinary party: there is only one contest here, and
        /// naming it above its own county list is noise.
        let partyName: String?
        let states: [StateGroup]

        var id: String { partyID }
        var counties: [County] { states.flatMap(\.counties) }
        /// A single-state group needs no state heading — the group's own
        /// heading already said it (Indiana, Delaware, and every ordinary party).
        var isSingleState: Bool { states.count == 1 }
    }

    /// Groups for `party`. `members` supplies the definitions of whatever it
    /// `combines`; pass an empty array for an ordinary party, or when the
    /// members can't be resolved — the counties then group by state alone,
    /// which every multi-state party's own data already supports.
    static func groups(
        for party: PartyDefinition,
        members: [PartyDefinition] = []
    ) -> [PartyGroup] {
        let byID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resolved = party.combines.compactMap { byID[$0] }

        guard !resolved.isEmpty else {
            return [PartyGroup(
                partyID: party.id,
                partyName: nil,
                states: byState(party.counties, fallback: party.homeState)
            )]
        }
        return resolved.map { member in
            PartyGroup(
                partyID: member.id,
                partyName: member.name,
                states: byState(member.counties, fallback: member.homeState)
            )
        }
    }

    /// Counties keep their definition order inside a state — the generators
    /// emit them in the sponsor's own order — while the states themselves sort,
    /// so the eye can find one.
    private static func byState(_ counties: [County], fallback: String) -> [StateGroup] {
        var order: [String] = []
        var grouped: [String: [County]] = [:]
        for county in counties {
            let state = county.state ?? fallback
            if grouped[state] == nil { order.append(state) }
            grouped[state, default: []].append(county)
        }
        return order.sorted().map { StateGroup(state: $0, counties: grouped[$0] ?? []) }
    }
}
