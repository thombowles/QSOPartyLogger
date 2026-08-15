import Foundation

/// What the spot sheet edits: one station, one frequency, and the pieces
/// each network wants — the party's county for the hub (and the cluster's
/// remarks), the park and mode for POTA — plus which networks are ticked.
///
/// Each network's own composer turns it into that network's payload, and
/// each network's own validator judges it, so a problem is shown under the
/// row it belongs to and never blocks another network. Nothing is skipped
/// silently: Post waits until every ticked network is satisfied.
struct SpotDraft: Equatable, Sendable {
    var station: String
    var frequencyKHz: Double
    /// The party's own county abbreviation(s), slash-joined for a line.
    var county: String?
    var comment: String
    var poster: String
    /// One POTA reference — the board takes one per spot.
    var park: String
    /// The ADIF mode POTA is told (`SSB`, `CW`, …).
    var mode: String
    var networks: Set<SpotNetwork>

    static let empty = SpotDraft(
        station: "", frequencyKHz: 0, county: nil, comment: "",
        poster: "", park: "", mode: "", networks: []
    )

    // MARK: Per-network payloads

    var hubFields: HubSelfSpot.Fields {
        HubSelfSpot.Fields(
            station: station, frequencyKHz: frequencyKHz, county: county,
            comment: comment, poster: poster
        )
    }

    func clusterFields(party: PartyDefinition) -> ClusterSpot.Fields {
        ClusterSpot.Fields(
            call: station,
            frequencyKHz: frequencyKHz,
            remarks: ClusterSpot.remarks(contest: party.cabrilloContest, county: county, comment: comment)
        )
    }

    var potaFields: PotaSpot.Fields {
        PotaSpot.Fields(
            activator: station, spotter: poster, frequencyKHz: frequencyKHz,
            reference: park, mode: mode, comments: comment
        )
    }

    // MARK: Judgement

    /// This network's objection to the draft, in its own words — independent
    /// of whether the network is ticked, so the sheet can show it either way.
    func problem(for network: SpotNetwork, party: PartyDefinition) -> String? {
        switch network {
        case .cluster: ClusterSpot.validate(clusterFields(party: party))?.errorDescription
        case .hub: HubSelfSpot.validate(hubFields, party: party)?.errorDescription
        case .pota: PotaSpot.validate(potaFields)?.errorDescription
        }
    }

    /// What stands between the draft and Post: the ticked networks'
    /// objections, each keyed to its network.
    func problems(party: PartyDefinition) -> [SpotNetwork: String] {
        var problems: [SpotNetwork: String] = [:]
        for network in networks {
            if let problem = problem(for: network, party: party) {
                problems[network] = problem
            }
        }
        return problems
    }

    /// Post is enabled only when something is ticked and nothing ticked has
    /// a problem — the operator fixes it or unticks it.
    func canPost(party: PartyDefinition) -> Bool {
        !networks.isEmpty && problems(party: party).isEmpty
    }

    /// Exactly what the network will carry, before it goes.
    func preview(for network: SpotNetwork, party: PartyDefinition) -> String {
        switch network {
        case .cluster:
            return ClusterSpot.command(clusterFields(party: party))
        case .hub:
            return [
                station.trimmingCharacters(in: .whitespaces).uppercased(),
                SpotFrequency.text(kHz: frequencyKHz),
                county ?? "",
                comment,
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        case .pota:
            return [
                PotaSpot.reference(from: park) ?? park.trimmingCharacters(in: .whitespaces).uppercased(),
                mode.trimmingCharacters(in: .whitespaces).uppercased(),
                comment,
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        }
    }

    /// The draft as it goes to the dispatcher: a network that stopped being
    /// on offer while the sheet was open (the node dropped) is not sent to.
    func sending(available: Set<SpotNetwork>) -> SpotDraft {
        var copy = self
        copy.networks = networks.intersection(available)
        return copy
    }
}
