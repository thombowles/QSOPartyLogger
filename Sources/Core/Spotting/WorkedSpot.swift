import Foundation

/// A contact from your own log, as a band map spot.
///
/// A station nobody posted left no trace on the map: you work him, and ten
/// minutes later his frequency reads as empty. N1MM's bandmap carries calls
/// the operator typed alongside network spots for exactly this reason. These
/// arrive already worked, so they draw struck-through and ⌘↑/⌘↓ steps over
/// them — the point is knowing the frequency is taken, not being sent back.
enum WorkedSpot {

    /// `nil` when the contact carries no frequency, which is every contact
    /// logged without a radio. There is nowhere to draw it and no honest way
    /// to guess where he was.
    ///
    /// Also `nil` for everything worked while running. The reason worked spots
    /// exist — *this frequency is taken by someone nobody posted* — is the one
    /// thing a run frequency never needs said: it is your own, the map already
    /// marks it, and ⌘J goes back to it. What arrives instead is the run
    /// itself, every station that answered stacked on the single frequency you
    /// are least likely to tune to. The operating mode decides, the same flag
    /// that picks the message set and reads ⇧⌘S as "spot my own run" — so a
    /// contact worked off-frequency mid-run is suppressed too, because one
    /// switch meaning one thing everywhere beats a special case here.
    static func spot(for qso: QSO, myCall: String, mode: OperatingMode) -> Spot? {
        guard mode != .run else { return nil }
        guard let freqKHz = qso.freqKHz else { return nil }
        let location = qso.theirLoc.trimmingCharacters(in: .whitespaces).uppercased()
        return Spot(
            call: qso.call.trimmingCharacters(in: .whitespaces).uppercased(),
            freqKHz: Double(freqKHz),
            spotter: myCall.trimmingCharacters(in: .whitespaces).uppercased(),
            comment: "",
            receivedAt: qso.timestampUTC,
            // What he sent, whatever it is — a county in state, a state or DX
            // outside it. `workedCallCounties` is keyed `CALL|THEIRLOC`, so
            // carrying it through is what greys the spot the moment it lands
            // instead of leaving a station you just worked looking fresh.
            // Only a real county ever reaches the hub's form; see HubSpotPrefill.
            county: location.isEmpty ? nil : location,
            source: .local
        )
    }

    /// One contact is one spot. A county-line QSO expands to a row per county
    /// but is a single station on a single frequency.
    static func spots(for rows: [QSO], myCall: String, mode: OperatingMode) -> [Spot] {
        var seen = Set<String>()
        return rows
            .compactMap { spot(for: $0, myCall: myCall, mode: mode) }
            .filter { seen.insert($0.id).inserted }
    }
}
