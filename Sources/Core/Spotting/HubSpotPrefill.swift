import Foundation

/// Filling the spot sheet from whatever the operator right-clicked — a band
/// map spot, a log row, or the call in the entry field.
///
/// Pure, and it posts nothing: the sheet still confirms every send, because
/// the hub's form has no authentication and reaches a public board at once.
///
/// The judgement here is the county. `theirLoc` is a county for an in-state
/// station and a state or `DX` for everyone else; the entry field holds
/// whatever has been copied so far, report and all. Only a county of this
/// party may go out as a county token, so anything else is dropped rather than
/// broadcast to everyone reading the board.
enum HubSpotPrefill {

    static func fields(
        station: String,
        frequencyKHz: Double?,
        location: String?,
        poster: String,
        party: PartyDefinition
    ) -> HubSelfSpot.Fields {
        HubSelfSpot.Fields(
            station: station.trimmingCharacters(in: .whitespaces).uppercased(),
            // No frequency means the sheet opens with the field empty and the
            // send held by its own validation. A guessed frequency on a public
            // board is worse than a blank one.
            frequencyKHz: frequencyKHz ?? 0,
            county: counties(in: location, party: party),
            comment: "",
            poster: poster.trimmingCharacters(in: .whitespaces).uppercased()
        )
    }

    /// Every county of this party named anywhere in `text`, in the order
    /// written, slash-joined. Scanned by token so a half-copied exchange —
    /// `599 MDSN` — offers its county, and a county line offers both: a spot
    /// naming only the first tells a chaser hunting the second to skip a
    /// station that would have given them the multiplier.
    ///
    /// Only real counties survive, which is the whole point of scanning found
    /// text rather than trusting it — an out-of-state `TX`, a `DX`, a signal
    /// report or a garbled token must never reach a public board as a county.
    /// Our own abbreviations, not the hub's: `HubSelfSpot` translates at the
    /// wire, which is the only place that knows the board's own spelling.
    static func counties(in text: String?, party: PartyDefinition) -> String? {
        guard let text else { return nil }
        let abbrs = Set(party.counties.map(\.abbr))
        let found = HubSelfSpot.counties(in: text).filter { abbrs.contains($0) }
        return found.isEmpty ? nil : found.joined(separator: "/")
    }

    /// The county to offer for your *own* spot — your counties, joined, and
    /// nothing at all when you are out of state.
    ///
    /// The out-of-state case is the one that matters: an entrant's "location"
    /// is a state, which is a multiplier and not a county token. Offering it
    /// would fill the sheet with the single value its own validation refuses,
    /// and block the send that was just asked for.
    ///
    /// Also what the rover tracker compares. A line moving `MDSN/LIME` to
    /// `MDSN/LAWR` changes in the second position only, so comparing the first
    /// county alone would never notice the change worth re-spotting for.
    static func ownCounty(_ location: MyLocation) -> String? {
        guard location.isInState else { return nil }
        let counties = location.sentExchanges.filter { !$0.isEmpty }
        return counties.isEmpty ? nil : counties.joined(separator: "/")
    }
}
