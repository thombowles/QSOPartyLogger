import Foundation

/// The entry row's shape, computed once per contest change — which fields
/// exist, the exchange field's label, and where Space routes. For a
/// `PartyDefinition` it reproduces the row's old flag branches exactly
/// (`EntryLayoutTests` proves it per party); for a v2-only contest (POTA) it
/// derives from the exchange spec, which is what lets the row exist for a
/// contest that has no party at all. Spec 2026-08-25 §entry row, decision 12.
struct EntryLayout: Equatable {
    var showsRST: Bool
    var showsSerial: Bool
    var showsName: Bool
    var member: MemberExchange?
    var showsLocation: Bool
    var locationLabel: String
    var showsTheirPark: Bool
    /// A POTA log's park is the one field an operator fills every P2P
    /// contact, so Space reaches it there — and only there: in a party the
    /// fast path must not grow a stop (the old routing, kept).
    var theirParkInSpaceCycle: Bool
    /// The POTA row's advisory fields (operator report 1, 2026-08-25):
    /// their state — "59 Missouri" is the usual POTA exchange, so it joins
    /// the Space cycle after the park — and a free-text note, Tab-only.
    var showsTheirState: Bool
    var showsNotes: Bool

    init(party: PartyDefinition?, contest: ContestDefinition?, isActivation: Bool) {
        if let party {
            showsRST = party.exchangeIncludesRST
            showsSerial = party.exchangeIncludesSerial
            showsName = party.exchangeIncludesName
            member = party.memberExchange
            showsLocation = true
            locationLabel = Self.locationLabel(for: party)
            showsTheirPark = isActivation
            theirParkInSpaceCycle = false
            showsTheirState = false
            showsNotes = false
        } else if let contest {
            showsRST = contest.exchange.contains { $0.kind == .rst }
            showsSerial = contest.exchange.contains { $0.kind == .serial }
            showsName = contest.exchange.contains { $0.kind == .name }
            // No standalone contest carries a member element; a party's
            // comes through the branch above.
            member = nil
            showsLocation = contest.exchange.contains { $0.id == ExchangeElementID.location }
            locationLabel = "Exchange"
            showsTheirPark = contest.potaProgram || isActivation
            theirParkInSpaceCycle = contest.potaProgram
            showsTheirState = contest.potaProgram
            showsNotes = contest.potaProgram
        } else {
            // An unrecognised partyID: the row the bar has always drawn.
            showsRST = true
            showsSerial = false
            showsName = false
            member = nil
            showsLocation = true
            locationLabel = "Exchange"
            showsTheirPark = isActivation
            theirParkInSpaceCycle = false
            showsTheirState = false
            showsNotes = false
        }
    }

    /// What the exchange field asks for, in the party's own words — moved
    /// verbatim from `EntryBar.exchangeLabel`. A party with no home region
    /// has no host-state codes to hint at — every token is a peer location —
    /// and one whose multipliers are not counties must not be told they are.
    private static func locationLabel(for party: PartyDefinition) -> String {
        guard party.hasHomeRegion else { return "Location" }
        return "\(party.countyTerm.sentenceCased)/State "
            + "(\(party.homeState) ×\(party.countyAbbrLengthHint))"
    }
}

extension EntryBar.Field {
    /// Where Space moves next under `layout` — the routing that lived on the
    /// field enum as `next(includesRST:includesSerial:includesName:
    /// includesMember:)`, with one addition: a POTA layout routes into the
    /// park field where a party routes back to the call.
    ///
    /// The original rationale, kept: Call jumps straight past the pre-filled
    /// RSTs (Tab still walks them); a received QSO number is the one numeric
    /// field an operator must type every contact, so it comes first where a
    /// contest exchanges one; a received name arrives before the location on
    /// the air ("TOM TX"); the member element arrives after it ("559 NJ NR
    /// 13"), so its field trails the exchange.
    func next(layout l: EntryLayout) -> EntryBar.Field {
        // The stop after the call/report hop: the received number, the name,
        // the exchange — or, with no exchange field at all (POTA), the park.
        let afterCall: EntryBar.Field = l.showsSerial ? .serialRcvd
            : l.showsName ? .nameRcvd
            : l.showsLocation ? .exchange
            : l.theirParkInSpaceCycle ? .theirPark
            : .call
        let afterExchange: EntryBar.Field = l.theirParkInSpaceCycle ? .theirPark : .call
        switch self {
        case .call: return afterCall
        // Without an RST element the report fields are not rendered at all;
        // the old router still sent this vestigial case to the exchange, and
        // the per-party equivalence test pins that verbatim.
        case .rstSent: return l.showsRST ? .rstRcvd
            : l.showsLocation ? .exchange : afterExchange
        case .rstRcvd: return afterCall
        case .serialSent: return .serialRcvd
        case .serialRcvd: return l.showsName ? .nameRcvd
            : l.showsLocation ? .exchange : afterExchange
        case .nameRcvd: return l.showsLocation ? .exchange : afterExchange
        case .exchange: return l.member != nil ? .memberRcvd : afterExchange
        case .memberRcvd: return afterExchange
        // The park leads on to the state where the row has one ("59
        // Missouri" follows the park on the air); notes never join the
        // cycle — prose typed mid-run is the exception, and Tab reaches it.
        case .theirPark: return l.showsTheirState ? .theirState : .call
        case .theirState: return .call
        case .notes: return .call
        }
    }
}
