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

    /// An identical spot repeated inside this window is a stuck key, not news.
    static let duplicateWindow: TimeInterval = 5 * 60

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
        if let county = fields.county?.trimmingCharacters(in: .whitespaces), !county.isEmpty {
            guard party.counties.contains(where: { $0.abbr == county.uppercased() }) else {
                return .unknownCounty(county.uppercased())
            }
        }
        return nil
    }

    /// Whether this spot repeats one just sent. Frequency and county changes
    /// are never duplicates — those are precisely the moments a re-spot
    /// matters, and a rover changing county is the thing most often forgotten.
    static func isDuplicate(
        _ fields: Fields, of previous: Fields, lastSentAt: Date, now: Date
    ) -> Bool {
        guard now.timeIntervalSince(lastSentAt) < duplicateWindow else { return false }
        return fields == previous
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
    /// to reduce the ambiguity its own parser exists to resolve.
    /// Not `%g`: its six significant digits turn 14045.25 into 14045.2, which
    /// would broadcast a frequency 50 Hz off to everyone reading the board.
    static func formattedFrequency(_ kHz: Double) -> String {
        if kHz == kHz.rounded() { return String(Int(kHz)) }
        var text = String(format: "%.2f", kHz)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Our official abbreviation translated to the token the hub's own form
    /// accepts — Illinois' `PULA` has to go out as its `PULS`.
    private static func hubCountyToken(_ county: String?, party: PartyDefinition) -> String {
        guard let county = county?.trimmingCharacters(in: .whitespaces).uppercased(),
              !county.isEmpty else { return "" }
        return party.hubSpots?.reverseCountyAliases[county] ?? county
    }
}
