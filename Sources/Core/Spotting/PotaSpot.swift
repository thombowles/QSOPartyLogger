import Foundation

/// A spot for pota.app, built the way the site's own "Add Spot" form builds
/// one. The contract is the form's code (`SpotForm` in pota.app's bundle,
/// fetched 2026-08-15 — `docs/research/pota/SOURCES.md`): a JSON POST of
/// `activator, spotter, frequency, reference, mode, source, comments` to
/// `https://api.pota.app/spot`, no authentication, the response being the
/// board's current spot list. Every rule below is quoted from that form.
///
/// Pure: it builds and checks the payload and posts nothing.
enum PotaSpot {

    struct Fields: Equatable, Sendable {
        var activator: String
        var spotter: String
        var frequencyKHz: Double
        var reference: String
        var mode: String
        var comments: String
    }

    enum Problem: Equatable, LocalizedError {
        case missingActivator
        case missingSpotter
        case badCallsign(String)
        case missingReference
        case badReference(String)
        case frequencyNotKHz

        var errorDescription: String? {
            switch self {
            case .missingActivator: "Enter the call you're spotting."
            case .missingSpotter: "Enter your own call — pota.app records who spotted."
            case .badCallsign(let call): "\(call) isn't a callsign pota.app accepts."
            case .missingReference: "Enter the park reference."
            case .badReference(let reference):
                "\(reference) isn't a reference pota.app accepts — they look like US-0817."
            case .frequencyNotKHz: "pota.app takes the frequency in kilohertz, above 1000."
            }
        }
    }

    /// What the board records as the origin — other loggers post under their
    /// own names (`Ham2K Portable Logger`, `HAMRS Pro/2.52.0` on the live
    /// board), and so does this one.
    static let source = "QSOPartyLogger"
    static let postURL = URL(string: "https://api.pota.app/spot")!
    /// The board, for confirming a send the response did not confirm.
    static let boardURL = URL(string: "https://api.pota.app/spot/activator")!

    /// The form's `validCallsignRegex`, verbatim.
    private static let callsignPattern = try! NSRegularExpression(
        pattern: #"^(?:[A-Z\d]{1,4}/)?[A-Z\d]{1,3}\d[A-Z\d]*(?:/[A-Z\d]{1,4})?$"#,
        options: [.caseInsensitive]
    )
    /// The form's `validReferenceRegex`, verbatim.
    private static let referencePattern = try! NSRegularExpression(
        pattern: #"^[A-Z0-9]{1,2}-[0-9]{4,5}$"#
    )

    static func isValidCallsign(_ call: String) -> Bool {
        matches(callsignPattern, call)
    }

    /// The reference as the form accepts it: through the ADIF grammar first
    /// (`PotaRef.normalize` — trim, uppercase, shape), with any `@subdivision`
    /// dropped because the spot page's regex has no room for one, then the
    /// page's own rule — or its literal `K-TEST`. `nil` when nothing usable.
    static func reference(from raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if token == "K-TEST" { return token }
        guard let normalized = PotaRef.normalize(token),
              let park = normalized.split(separator: "@").first.map(String.init),
              matches(referencePattern, park)
        else { return nil }
        return park
    }

    static func validate(_ fields: Fields) -> Problem? {
        let activator = fields.activator.trimmingCharacters(in: .whitespaces)
        let spotter = fields.spotter.trimmingCharacters(in: .whitespaces)
        guard !activator.isEmpty else { return .missingActivator }
        guard !spotter.isEmpty else { return .missingSpotter }
        guard isValidCallsign(activator) else { return .badCallsign(activator.uppercased()) }
        guard isValidCallsign(spotter) else { return .badCallsign(spotter.uppercased()) }
        let rawReference = fields.reference.trimmingCharacters(in: .whitespaces)
        guard !rawReference.isEmpty else { return .missingReference }
        guard reference(from: rawReference) != nil else {
            return .badReference(rawReference.uppercased())
        }
        // "Frequency in kHz (> 1000)" — the form's third frequency rule.
        guard fields.frequencyKHz > 1000 else { return .frequencyNotKHz }
        return nil
    }

    // MARK: Wire

    private struct Body: Encodable {
        let activator, spotter, frequency, reference, mode, source, comments: String
    }

    /// The JSON the form posts, keys sorted so the bytes are stable.
    static func jsonBody(_ fields: Fields) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Body(
            activator: fields.activator.trimmingCharacters(in: .whitespaces).uppercased(),
            spotter: fields.spotter.trimmingCharacters(in: .whitespaces).uppercased(),
            frequency: SpotFrequency.text(kHz: fields.frequencyKHz),
            reference: reference(from: fields.reference)
                ?? fields.reference.trimmingCharacters(in: .whitespaces).uppercased(),
            mode: fields.mode.trimmingCharacters(in: .whitespaces).uppercased(),
            source: source,
            comments: fields.comments.trimmingCharacters(in: .whitespaces)
        ))
    }

    // MARK: The board

    /// One row of the board, read leniently — only what confirmation needs.
    struct BoardSpot: Decodable, Equatable, Sendable {
        var activator: String
        var reference: String
        var spotter: String?
        var frequency: String?
        var mode: String?
        var spotTime: String?
        var source: String?
    }

    /// The board as the API returns it (and as the POST answers). `nil` when
    /// the body is not that list — an error text, an HTML page.
    static func board(from data: Data) -> [BoardSpot]? {
        try? JSONDecoder().decode([BoardSpot].self, from: data)
    }

    /// Whether the board shows this spot: same activator, same reference.
    static func contains(_ fields: Fields, in board: [BoardSpot]) -> Bool {
        let activator = fields.activator.trimmingCharacters(in: .whitespaces).uppercased()
        guard let reference = reference(from: fields.reference) else { return false }
        return board.contains {
            $0.activator.uppercased() == activator && $0.reference.uppercased() == reference
        }
    }

    /// The failure the operator reads: the server's own first line when it
    /// sent a readable one (the form shows `e.response.data` as-is), else
    /// the status. HTML is not readable.
    static func failureText(status: Int, body: Data) -> String {
        let text = String(decoding: body, as: UTF8.self)
        let line = text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if line.isEmpty || line.hasPrefix("<") || line.count > 120 {
            return "pota.app refused the spot (HTTP \(status))."
        }
        return "pota.app refused the spot: \(line)"
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
