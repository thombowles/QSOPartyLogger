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
            county: county(in: location, party: party),
            comment: "",
            poster: poster.trimmingCharacters(in: .whitespaces).uppercased()
        )
    }

    /// The first county of this party named anywhere in `text`. Scanned by
    /// token so a half-copied exchange — `599 MDSN` — offers its county, and a
    /// county line offers the first of the pair for the picker to change.
    /// Our own abbreviation, not the hub's: `HubSelfSpot` translates at the
    /// wire, which is the only place that knows the board's own spelling.
    static func county(in text: String?, party: PartyDefinition) -> String? {
        guard let text else { return nil }
        let abbrs = Set(party.counties.map(\.abbr))
        return text.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .first { abbrs.contains($0) }
    }
}
