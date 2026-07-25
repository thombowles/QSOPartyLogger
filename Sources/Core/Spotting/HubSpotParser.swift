import Foundation

/// Reads the spot table served by qsopartyhub.com.
///
/// Pure and offline: it takes the page text and the active party, and returns
/// spots. Nothing here touches the network, so every case is testable against
/// the captured pages in `Tests/Fixtures/HubSpots`.
///
/// The page is not well-formed — the `agekey` legend table above the spots is
/// never closed — so rows are lifted directly rather than handed to a strict
/// parser. Because the columns are read by position, the header is a hard
/// gate: if the hub inserts a column, parsing stops rather than sliding the
/// county into the comment and presenting wrong multiplier data.
enum HubSpotParser {

    struct Result: Equatable {
        var spots: [Spot] = []
        /// Rows that could not be read, kept for the operator's node console.
        /// A silently shrinking spot list is indistinguishable from a quiet
        /// band; a visible reject is diagnosable.
        var rejected: [String] = []
        /// The table's columns are not the ones this parser understands.
        var headerMismatch = false
    }

    static let expectedHeader = ["TIME (UTC)", "SPOT", "FREQ", "QTH", "COMMENT", "POSTER"]

    /// Two spots this far apart in frequency are on the same one.
    private static let sameFrequencyToleranceKHz = 0.25
    /// A correction follows its typo closely; hours apart is two operators.
    private static let correctionWindow: TimeInterval = 20 * 60

    static func parse(html: String, party: PartyDefinition) -> Result {
        guard let table = spotsTable(in: html) else { return Result() }

        let header = cells(in: table, tag: "th")
        guard !header.isEmpty else { return Result() }
        guard header == expectedHeader else {
            return Result(headerMismatch: true)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let countyAbbrs = Set(party.counties.map(\.abbr))
        let aliases = party.hubSpots?.countyAliases ?? [:]
        let bands = Set(party.validBands)

        var result = Result()
        for row in rows(in: table) {
            let fields = cells(in: row, tag: "td")
            guard fields.count == expectedHeader.count else {
                result.rejected.append(text(of: row))
                continue
            }
            guard let spot = spot(
                fields: fields, formatter: formatter, bands: bands,
                countyAbbrs: countyAbbrs, aliases: aliases
            ) else {
                result.rejected.append(text(of: row))
                continue
            }
            result.spots.append(spot)
        }
        result.spots = markingSupersededCalls(result.spots)
        return result
    }

    // MARK: Row → Spot

    private static func spot(
        fields: [String],
        formatter: DateFormatter,
        bands: Set<Band>,
        countyAbbrs: Set<String>,
        aliases: [String: String]
    ) -> Spot? {
        guard let timestamp = formatter.date(from: fields[0]) else { return nil }

        let call = fields[1].uppercased()
        guard call.count >= 3, call.contains(where: \.isNumber) else { return nil }

        // The hub invites "General" announcements with a frequency of "00";
        // they are messages, not somewhere to tune.
        guard let frequency = HubFrequency.normalize(fields[2]),
              let band = Band.from(freqKHz: Int(frequency.kHz.rounded())),
              bands.contains(band) else { return nil }

        let comment = fields[4]
        let county = self.county(
            qth: fields[3], comment: comment,
            countyAbbrs: countyAbbrs, aliases: aliases
        )

        return Spot(
            call: call,
            freqKHz: frequency.kHz,
            spotter: fields[5].uppercased(),
            comment: comment,
            receivedAt: timestamp,
            county: county,
            source: .hub,
            frequencyConfidence: frequency.confidence
        )
    }

    /// The county the spot is really reporting.
    ///
    /// The QTH column is authoritative when it holds a county this party has.
    /// When it is blank, the comment is searched — operators do put the county
    /// there instead, and it is the multiplier the party is scored on. A token
    /// that is not one of this party's counties is dropped rather than carried
    /// as a multiplier that cannot exist.
    private static func county(
        qth: String,
        comment: String,
        countyAbbrs: Set<String>,
        aliases: [String: String]
    ) -> String? {
        if let resolved = resolve(qth, countyAbbrs: countyAbbrs, aliases: aliases) {
            return resolved
        }
        for token in comment.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if let resolved = resolve(String(token), countyAbbrs: countyAbbrs, aliases: aliases) {
                return resolved
            }
        }
        return nil
    }

    private static func resolve(
        _ token: String,
        countyAbbrs: Set<String>,
        aliases: [String: String]
    ) -> String? {
        let upper = token.trimmingCharacters(in: .whitespaces).uppercased()
        guard !upper.isEmpty else { return nil }
        if let aliased = aliases[upper], countyAbbrs.contains(aliased) { return aliased }
        return countyAbbrs.contains(upper) ? upper : nil
    }

    // MARK: Corrections

    /// The board keeps a busted call alongside the correction that follows it
    /// — live ALQP carried `KC4TE` and then `KC4TEO` four minutes later on one
    /// frequency, commented `RIGHT CALL`. Shown naively that is a phantom
    /// station sitting beside the real one.
    ///
    /// Marked, never dropped: the rule rests on few observed instances, so the
    /// operator has to be able to see it and disagree.
    private static func markingSupersededCalls(_ spots: [Spot]) -> [Spot] {
        var spots = spots
        for i in spots.indices {
            for j in spots.indices where i != j {
                let candidate = spots[i]      // possibly the typo
                let successor = spots[j]      // possibly the correction
                guard successor.receivedAt > candidate.receivedAt,
                      successor.receivedAt.timeIntervalSince(candidate.receivedAt)
                          <= correctionWindow,
                      abs(successor.freqKHz - candidate.freqKHz)
                          <= sameFrequencyToleranceKHz,
                      isOneEditApart(candidate.call, successor.call) else { continue }
                spots[i].isSuperseded = true
                break
            }
        }
        return spots
    }

    /// One insertion, deletion or substitution apart — the shape of a typo.
    static func isOneEditApart(_ a: String, _ b: String) -> Bool {
        if a == b { return false }
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 1 { return false }

        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        var i = 0, j = 0, edits = 0
        while i < short.count, j < long.count {
            if short[i] == long[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if short.count == long.count { i += 1 }
            j += 1
        }
        return true
    }

    // MARK: HTML

    /// The spots table only. The legend table above it is never closed, so the
    /// first `</table>` after the marker is this table's own.
    private static func spotsTable(in html: String) -> Substring? {
        guard let start = html.range(of: "<table id=spots>") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: "</table>") else { return nil }
        return rest[..<end.lowerBound]
    }

    private static func rows(in table: Substring) -> [Substring] {
        var out: [Substring] = []
        var remainder = table[...]
        while let open = remainder.range(of: "<tr", options: .caseInsensitive) {
            let afterOpen = remainder[open.lowerBound...]
            guard let close = afterOpen.range(of: "</tr>", options: .caseInsensitive) else { break }
            let row = afterOpen[..<close.lowerBound]
            // The header row carries no data cells.
            if row.range(of: "<td", options: .caseInsensitive) != nil {
                out.append(row)
            }
            remainder = afterOpen[close.upperBound...]
        }
        return out
    }

    private static func cells(in fragment: Substring, tag: String) -> [String] {
        var out: [String] = []
        var remainder = fragment
        while let open = remainder.range(of: "<\(tag)", options: .caseInsensitive) {
            let afterTag = remainder[open.upperBound...]
            guard let contentStart = afterTag.firstIndex(of: ">") else { break }
            let body = afterTag[afterTag.index(after: contentStart)...]
            guard let close = body.range(of: "</\(tag)>", options: .caseInsensitive) else { break }
            out.append(text(of: body[..<close.lowerBound]))
            remainder = body[close.upperBound...]
        }
        return out
    }

    /// Tag-stripped, entity-decoded, whitespace-collapsed cell text.
    private static func text(of fragment: Substring) -> String {
        var s = String(fragment)
        while let tag = s.range(of: "<[^>]*>", options: .regularExpression) {
            s.replaceSubrange(tag, with: "")
        }
        for (entity, character) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ] {
            s = s.replacingOccurrences(of: entity, with: character)
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
