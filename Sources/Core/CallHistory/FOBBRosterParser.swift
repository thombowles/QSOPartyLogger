import Foundation

/// Reads the ARS self-serve Bumblebee roster — the sponsor's own report
/// page at a stable URL (`Process_Get_All_By_Number.php`), one plain HTML
/// table `BB | Callsign | Name | SPC | Expected Location` — and converts it
/// to the N1MM call-history text shape so the store, token gate, parser and
/// prefill pipeline downstream run untouched.
///
/// Pure and offline, like `SkeeterRosterParser`, and with the same drift
/// stance: these are positional reads of somebody else's markup, so an
/// unrecognized page is an explicit `nil` — never a silent empty that reads
/// as "no roster this event". Page shape observed 2026-08-10; captured
/// fixture in `Tests/Fixtures/CallHistory`, provenance in
/// `docs/research/fobb_rules.md` §13.
///
/// Each Bumblebee is emitted under both `CALL` and `CALL/BB`: bees sign /BB
/// on the air ("Bumblebees will add /BB to their calls") and
/// `CallHistoryFile.entry(for:)` matches the typed call exactly, so the
/// double row is what makes prefill fire however the operator types it.
///
/// Roster data is a **hint, never a rule** (constitution Article 1): every
/// value it carries is re-validated by the party's own parsers before being
/// offered, and nothing from it reaches `ScoreEngine` — Bumblebee credit
/// comes from the received exchange, not from roster membership.
enum FOBBRosterParser {

    /// The first four column headings, as the report prints them.
    private static let expectedHeader = ["BB", "CALLSIGN", "NAME", "SPC"]

    /// The roster table converted to N1MM call-history text: the S/P/C rides
    /// the State column and the BB number rides Exch1 (the Skeeter
    /// converter's arrangement), so `CallHistoryFile.Entry.locations` carries
    /// both and the two prefill channels split them — the number fails the
    /// location parse, the S/P/C fails the member digits test.
    ///
    /// `nil` when no row carries the header observed 2026-08-10, or when no
    /// numbered row follows it.
    static func n1mmText(fromHTML html: String, token: String) -> String? {
        let rows = tableRows(html)
        // The header is found rather than assumed to be row one, so a page
        // that gains a navigation table above the roster still reads; a page
        // with no such header at all is the drift case, and fails.
        guard let headerIndex = rows.firstIndex(where: isHeader) else { return nil }

        var lines = [
            "# \(token)",
            "# Converted from the ARS self-serve Bumblebee roster by QSOPartyLogger.",
            "# This is helping file, LOG what you copy.",
            "!!Order!!,Call,Name,State,Exch1",
        ]
        var records = 0
        for row in rows[rows.index(after: headerIndex)...] where row.count >= 4 {
            let number = row[0].trimmingCharacters(in: .whitespaces)
            let call = clean(row[1])
            guard !number.isEmpty, number.allSatisfy(\.isWholeNumber),
                  !call.isEmpty else { continue }
            let name = clean(row[2])
            let spc = clean(row[3])
            lines.append("\(call),\(name),\(spc),\(number)")
            lines.append("\(call)/BB,\(name),\(spc),\(number)")
            records += 1
        }
        guard records > 0 else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func isHeader(_ row: [String]) -> Bool {
        guard row.count >= 4 else { return false }
        return row.prefix(4).map { $0.uppercased() } == expectedHeader
    }

    /// `<tr>` rows as arrays of tag-stripped, entity-unescaped cell texts.
    /// Regex-free scanning in the `SkeeterRosterParser` idiom. `<th>` is
    /// normalized to `<td>` first so a mixed row keeps document order — this
    /// report writes even its headings as `<td>`, but a redesign need not.
    private static func tableRows(_ html: String) -> [[String]] {
        let normalized = html
            .replacingOccurrences(of: "<th", with: "<td", options: .caseInsensitive)
            .replacingOccurrences(of: "</th", with: "</td", options: .caseInsensitive)
        var rows: [[String]] = []
        for rowChunk in normalized.components(separatedBy: "<tr").dropFirst() {
            let row = rowChunk.components(separatedBy: "</tr").first ?? rowChunk
            var cells: [String] = []
            for cellChunk in row.components(separatedBy: "<td").dropFirst() {
                // Everything up to this cell's own closing tag, so nested
                // markup (the report wraps its headings in <font>) keeps all
                // of its text rather than stopping at the first "</".
                let body = cellChunk.components(separatedBy: "</td").first ?? cellChunk
                cells.append(unescaped(stripTags(body)))
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    private static func stripTags(_ text: String) -> String {
        var out = ""
        var inTag = false
        for c in text {
            if c == "<" { inTag = true } else if c == ">" { inTag = false } else if !inTag {
                out.append(c)
            }
        }
        return out
    }

    /// The handful of entities a hand-maintained roster actually produces.
    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed, uppercased, and stripped of the emitted format's own
    /// delimiters — the table is hand-maintained, and the Skeeter lesson is
    /// that a stray "," in a cell shifts every column after it.
    private static func clean(_ field: String) -> String {
        field.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .filter { $0 != "," && $0 != ";" }
    }
}
