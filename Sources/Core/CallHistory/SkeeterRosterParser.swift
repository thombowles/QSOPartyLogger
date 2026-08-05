import Foundation

/// Reads the two artifacts the Skeeter Hunt roster download needs: W2LJ's
/// Skeeter Hunt page (which links each season's roster spreadsheet — the
/// document id changes yearly, the page URL does not) and the roster sheet's
/// CSV export, which is converted to the N1MM call-history text shape so the
/// store, parser and prefill pipeline downstream run untouched.
///
/// Pure and offline, like `CallHistoryPageParser`, and with the same drift
/// stance: these are positional reads of somebody else's markup, so an
/// unrecognized page is an explicit `nil` — never a silent empty that reads
/// as "no roster this year". Page shape observed 2026-08-04; captured
/// fixtures in `Tests/Fixtures/CallHistory`, provenance in
/// `docs/research/skeeter_rules.md` §13.
///
/// Roster data is a **hint, never a rule** (constitution Article 1): every
/// value it carries is re-validated by the party's own parsers before being
/// offered, and nothing from it reaches `ScoreEngine` — a contact's points
/// come from the received exchange, not from roster membership.
enum SkeeterRosterParser {

    /// The roster sheet's CSV-export URL, found by taking the spreadsheet
    /// link whose surrounding text names the roster — the page also links a
    /// dozen years of *scoreboard* spreadsheets, so the anchor phrase is what
    /// tells them apart ("The entire 2026 Skeeter Hunt roster can be seen
    /// <link>"). `nil` for a page with no such link: the site changed, and
    /// the caller must say so rather than shrug.
    static func rosterSheetURL(inPageHTML html: String) -> String? {
        let marker = "docs.google.com/spreadsheets/d/"
        var searchFrom = html.startIndex
        while let at = html.range(of: marker, range: searchFrom..<html.endIndex) {
            searchFrom = at.upperBound
            let id = html[at.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            guard !id.isEmpty else { continue }
            // The context that names this link, tags stripped so markup
            // between the phrase and the href cannot hide it.
            let contextStart = html.index(
                at.lowerBound, offsetBy: -600, limitedBy: html.startIndex
            ) ?? html.startIndex
            let context = html[contextStart..<at.lowerBound]
                .replacingOccurrences(
                    of: "<[^>]+>", with: " ", options: .regularExpression)
                .lowercased()
            if context.contains("roster") {
                return "https://docs.google.com/spreadsheets/d/\(id)/export?format=csv"
            }
        }
        return nil
    }

    /// The roster CSV, converted to N1MM call-history text: the S/P/C rides
    /// the State column and the Skeeter number rides Exch1, so
    /// `CallHistoryFile.Entry.locations` carries both and the two prefill
    /// channels split them — the number fails the location parse, the state
    /// token fails the member digits test. The `token` comment is what
    /// `CallHistorySource.isDeclared` later verifies.
    ///
    /// `nil` when the header row is not the sheet observed 2026-08-04
    /// (`Skeeter #, Call, Name, S/P/C, …`) or no numbered row survives —
    /// shape drift fails loudly rather than installing an empty roster.
    static func n1mmText(fromCSV csv: String, token: String) -> String? {
        let rows = parseCSV(csv)
        guard let header = rows.first else { return nil }
        let names = header.map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard let numberCol = names.firstIndex(of: "skeeter #"),
              let callCol = names.firstIndex(of: "call"),
              let spcCol = names.firstIndex(of: "s/p/c")
        else { return nil }
        let nameCol = names.firstIndex(of: "name")

        var lines = [
            "# \(token)",
            "# Converted from the sponsor's roster spreadsheet by QSOPartyLogger.",
            "# This is helping file, LOG what you copy.",
            "!!Order!!,Call,Name,State,Exch1",
        ]
        var records = 0
        for row in rows.dropFirst() {
            guard row.count > max(numberCol, callCol, spcCol) else { continue }
            let number = row[numberCol].trimmingCharacters(in: .whitespaces)
            let call = clean(row[callCol])
            // The live sheet's tail is blank scoreboard rows; a roster row is
            // one with a number and a call.
            guard !number.isEmpty, number.allSatisfy(\.isWholeNumber),
                  !call.isEmpty else { continue }
            let spc = clean(row[spcCol])
            let name = nameCol.map { i in
                row.count > i ? clean(row[i]) : ""
            } ?? ""
            lines.append("\(call),\(name),\(spc),\(number)")
            records += 1
        }
        guard records > 0 else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Trimmed, uppercased, and stripped of the emitted format's own
    /// delimiters — the sheet is hand-maintained and a stray "," in a cell
    /// (",SC" has appeared) would shift every column after it.
    private static func clean(_ field: String) -> String {
        field.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .filter { $0 != "," && $0 != ";" }
    }

    /// Minimal RFC-4180 field splitting: quoted fields may hold commas and
    /// doubled quotes, records end at unquoted newlines. The scoreboard
    /// columns riding beside the roster use quoted cells ("5th Place - High
    /// Score IA, High Score SSB"), so a naive comma split misreads real rows.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(row)
            }
            row = []
        }

        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": endField()
                // A CRLF pair is ONE Swift Character (grapheme cluster), so
                // it must be matched as itself — a separate "\r" case never
                // sees it, and Google's export uses CRLF endings.
                case "\n", "\r\n": endRow()
                case "\r": break
                default: field.append(c)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
