import Foundation

/// Composing a self-spot for qsopartyhub.com.
///
/// Pure: it builds and checks the payload, and posts nothing. The form it
/// targets has no CSRF token, no authentication and no session, so anything
/// posted reaches a public board immediately and a repeated submit posts
/// twice. Everything here exists because of that.
///
/// The contract is derived from the page's own markup — see
/// `docs/research/qsopartyhub.md` §5. No test post was made to the live board,
/// so the first real send is verified against the following poll.
enum HubSelfSpot {

    struct Fields: Equatable, Sendable {
        var station: String
        var frequencyKHz: Double
        var county: String?
        var comment: String
        var poster: String
    }

    enum Problem: Equatable, LocalizedError {
        case missingStation
        case missingPoster
        case tooLong(field: String, limit: Int)
        case frequencyNotOnAPartyBand
        case unknownCounty(String)

        var errorDescription: String? {
            switch self {
            case .missingStation: "Enter the call you're spotting."
            case .missingPoster: "Enter your own call — the hub records who posted."
            case .tooLong(let field, let limit):
                "\(field.capitalized) is longer than the \(limit) characters the hub accepts."
            case .frequencyNotOnAPartyBand:
                "That frequency isn't on one of this party's bands."
            case .unknownCounty(let county):
                "\(county) isn't a county in this party."
            }
        }
    }

    /// The form's own maxlength attributes.
    private static let limits = [
        "station": 15, "frequency": 10, "comment": 50, "poster": 15,
    ]

    /// An identical spot repeated inside this window is a stuck key, not news
    /// — the guard every network shares.
    static let duplicateWindow: TimeInterval = SpotRepeat.window

    // MARK: Validation

    static func validate(_ fields: Fields, party: PartyDefinition) -> Problem? {
        let station = fields.station.trimmingCharacters(in: .whitespaces)
        let poster = fields.poster.trimmingCharacters(in: .whitespaces)
        guard !station.isEmpty else { return .missingStation }
        guard !poster.isEmpty else { return .missingPoster }

        if station.count > limits["station"]! {
            return .tooLong(field: "station", limit: limits["station"]!)
        }
        if poster.count > limits["poster"]! {
            return .tooLong(field: "poster", limit: limits["poster"]!)
        }
        if fields.comment.count > limits["comment"]! {
            return .tooLong(field: "comment", limit: limits["comment"]!)
        }
        if formattedFrequency(fields.frequencyKHz).count > limits["frequency"]! {
            return .tooLong(field: "frequency", limit: limits["frequency"]!)
        }

        guard let band = Band.from(freqKHz: Int(fields.frequencyKHz.rounded())),
              party.validBands.contains(band) else {
            return .frequencyNotOnAPartyBand
        }
        // Every county of a line, not just the first: one bad half must not
        // ride out on the back of a good one. The offender is named rather
        // than leaving the operator to work out which half is wrong.
        for county in counties(in: fields.county ?? "") {
            guard party.counties.contains(where: { $0.abbr == county }) else {
                return .unknownCounty(county)
            }
        }
        return nil
    }

    /// The counties in a typed county field, in the order written, uppercased,
    /// deduped. Separated however the operator happens to write a line —
    /// `MDSN/LIME`, `MDSN, LIME`, `MDSN LIME` all read the same.
    ///
    /// Every token comes back, county or not. Judging them is `validate`'s
    /// job, and it needs the bad ones in order to name them.
    static func counties(in text: String) -> [String] {
        var seen = Set<String>()
        return text.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { seen.insert($0).inserted }
    }

    /// Whether this spot repeats one just sent. Frequency and county changes
    /// are never duplicates — those are precisely the moments a re-spot
    /// matters, and a rover changing county is the thing most often forgotten.
    static func isDuplicate(
        _ fields: Fields, of previous: Fields, lastSentAt: Date, now: Date
    ) -> Bool {
        SpotRepeat.isRepeat(fields, of: previous, lastSentAt: lastSentAt, now: now)
    }

    // MARK: Wire format

    static func multipartBody(
        fields: Fields, party: PartyDefinition, boundary: String
    ) -> Data {
        let values = [
            ("station", fields.station.trimmingCharacters(in: .whitespaces).uppercased()),
            ("frequency", formattedFrequency(fields.frequencyKHz)),
            ("county", hubCountyToken(fields.county, party: party)),
            ("comment", fields.comment.trimmingCharacters(in: .whitespaces)),
            ("poster", fields.poster.trimmingCharacters(in: .whitespaces).uppercased()),
        ]
        var body = ""
        for (name, value) in values {
            body += "--\(boundary)\r\n"
            body += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            body += "\(value)\r\n"
        }
        body += "--\(boundary)--\r\n"
        return Data(body.utf8)
    }

    /// Kilohertz, the way the form's own `14150` placeholder asks for it, with
    /// no trailing zeros. Posting clean kHz is the one thing this app can do
    /// to reduce the ambiguity its own parser exists to resolve. The one
    /// formatter every network shares — see `SpotFrequency` for why not `%g`.
    static func formattedFrequency(_ kHz: Double) -> String {
        SpotFrequency.text(kHz: kHz)
    }

    /// Our official abbreviations translated to the tokens the hub's own form
    /// accepts — Illinois' `PULA` has to go out as its `PULS`. Per token, so
    /// the alias still holds inside a pair and its partner is left alone.
    ///
    /// A county line goes out whole, slash-joined. This is off the documented
    /// contract: `docs/research/qsopartyhub.md` §5 records the county input as
    /// a `<select>` of single tokens, and §6 lists a county-line spot as
    /// unverified. Taken anyway, because a spot naming only the first county
    /// tells a chaser hunting the second to skip a station that would have
    /// given them the multiplier — correct information off-contract beats
    /// misleading information on it. The first real county-line send is
    /// verified against the following poll, not assumed from an HTTP 200.
    private static func hubCountyToken(_ county: String?, party: PartyDefinition) -> String {
        let aliases = party.hubSpots?.reverseCountyAliases
        return counties(in: county ?? "")
            .map { aliases?[$0] ?? $0 }
            .joined(separator: "/")
    }
}
