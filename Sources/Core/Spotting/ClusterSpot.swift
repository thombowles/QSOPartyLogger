import Foundation

/// A spot for a DX cluster node — the `DX` command as both node families
/// take it. DXSpider User Manual v1.51: `dx (frequency) (callsign)
/// (remarks)`, "frequency is in kilohertz"; AR-Cluster: `DX frequency
/// callsign misc-info`, "misc-info should be kept brief". Frequency first is
/// the order both accept. Sources: `docs/research/dxcluster-dx-command.md`.
///
/// Pure. It builds and checks the command and sends nothing; `SpotClient`
/// writes it down the open session, and the node's echo — "The callout will
/// also be sent to you as proof of receipt" — is the confirmation.
enum ClusterSpot {

    struct Fields: Equatable, Sendable {
        var call: String
        var frequencyKHz: Double
        var remarks: String
    }

    enum Problem: Equatable, LocalizedError {
        case missingCall
        case missingFrequency

        var errorDescription: String? {
            switch self {
            case .missingCall: "Enter the call you're spotting."
            case .missingFrequency: "Enter the frequency — the node needs one in kilohertz."
            }
        }
    }

    static func validate(_ fields: Fields) -> Problem? {
        guard !fields.call.trimmingCharacters(in: .whitespaces).isEmpty else { return .missingCall }
        guard fields.frequencyKHz > 0 else { return .missingFrequency }
        return nil
    }

    /// `DX <kHz> <CALL> <remarks>` — one line, exactly what goes down the wire
    /// (the transport adds the CRLF).
    static func command(_ fields: Fields) -> String {
        var parts = [
            "DX",
            SpotFrequency.text(kHz: fields.frequencyKHz),
            fields.call.trimmingCharacters(in: .whitespaces).uppercased(),
        ]
        let remarks = sanitize(fields.remarks)
        if !remarks.isEmpty { parts.append(remarks) }
        return parts.joined(separator: " ")
    }

    /// The remarks for a spot from this log: the party's Cabrillo contest
    /// name first — the sponsor's own identifier, and the one party-neutral
    /// tag there is, so a reader outside the party knows what the spot is —
    /// then the county, because a cluster has no county field of its own,
    /// then whatever the operator typed. Each part optional.
    static func remarks(contest: String?, county: String?, comment: String) -> String {
        sanitize([contest, county, comment].compactMap { $0 }.joined(separator: " "))
    }

    /// One line, single-spaced, printable. A CR or LF would end the command
    /// early and send the rest as a second one; control characters have no
    /// place on the air. Tabs and runs of spaces collapse to one.
    static func sanitize(_ text: String) -> String {
        text.split(whereSeparator: { character in
            character.isWhitespace || character.isNewline
                || (character.asciiValue.map { $0 < 32 || $0 == 127 } ?? false)
        })
        .joined(separator: " ")
    }

    /// Whether an incoming spot is the node handing this one back — ours by
    /// spotter and call, at the frequency we gave within half a kilohertz
    /// (nodes print to 100 Hz).
    static func isEcho(_ spot: Spot, of fields: Fields, poster: String) -> Bool {
        spot.spotter.uppercased() == poster.trimmingCharacters(in: .whitespaces).uppercased()
            && spot.call.uppercased() == fields.call.trimmingCharacters(in: .whitespaces).uppercased()
            && abs(spot.freqKHz - fields.frequencyKHz) < 0.5
    }
}
