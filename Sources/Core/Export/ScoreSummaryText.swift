import Foundation

/// The score sidebar as fixed-width text, for pasting into a summary email or a
/// 3830 post.
///
/// Shaped after N1MM's Score window, whose right-click menu offers "Copy all —
/// Copy all info to the Windows Clipboard" (N1MM Logger+ manual, *The Score
/// Window*, fetched 2026-08-05). The manual does not transcribe that window's
/// own screenshot and no byte-exact sample of what it copies was reachable, so
/// **the column layout here is a reconstruction of the window's shape, not of
/// N1MM's bytes**. Nothing depends on it: this is a convenience format, not a
/// scoring rule, and matching a real sample later is a change to this one file.
///
/// Every figure comes from the same `ScoreBreakdown` the sidebar draws, under
/// the same labels, so the paste and the screen can never disagree.
enum ScoreSummaryText {

    static func make(
        log: ContestLog,
        party: PartyDefinition?,
        score: ScoreEngine.ScoreBreakdown,
        members: [PartyDefinition] = []
    ) -> String {
        var blocks: [String] = [heading(log: log, party: party)]
        if let party {
            blocks.append(bandTable(log: log, party: party).joined(separator: "\n"))
            let combined = partyTable(log: log, party: party, members: members)
            if !combined.isEmpty {
                blocks.append(combined.joined(separator: "\n"))
            }
        }
        blocks.append(scoreTable(party: party, score: score).joined(separator: "\n"))
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: Blocks

    private static func heading(log: ContestLog, party: PartyDefinition?) -> String {
        let parts = [log.station.callsign, party?.name].compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "QSO Party Logger" : parts.joined(separator: " — ")
    }

    /// Bands down, mode classes across, exactly as the sidebar's matrix — and
    /// from the same `bandModeCounts`, which has already dropped dupes,
    /// wrong-mode and out-of-scope rows.
    ///
    /// A single-mode party gets no mode columns: for NAQP CW the CW column and
    /// the QSOs column would carry identical figures under two headings.
    private static func bandTable(log: ContestLog, party: PartyDefinition) -> [String] {
        let counts = ScoreEngine.bandModeCounts(log: log, party: party)
        let modes = party.allowedModeClasses
        let bands = Band.allCases.filter { counts[$0] != nil }
        let showModes = modes.count > 1

        func total(_ band: Band) -> Int {
            counts[band]?.values.reduce(0, +) ?? 0
        }

        var rows: [[String]] = [
            ["Band"] + (showModes ? modes.map(\.shortLabel) : []) + ["QSOs"]
        ]
        for band in bands {
            rows.append(
                [band.rawValue]
                    + (showModes ? modes.map { "\(counts[band]?[$0] ?? 0)" } : [])
                    + ["\(total(band))"]
            )
        }
        rows.append(
            ["Total"]
                + (showModes
                   ? modes.map { mode in "\(bands.reduce(0) { $0 + (counts[$1]?[mode] ?? 0) })" }
                   : [])
                + ["\(bands.reduce(0) { $0 + total($1) })"]
        )
        return columns(rows)
    }

    /// A combined entry's per-sponsor counts. Empty — and so omitted — for
    /// every ordinary party. The Challenge's two-QSO bar is marked, because a
    /// sponsor that will not count is the thing worth seeing in a paste.
    private static func partyTable(
        log: ContestLog, party: PartyDefinition, members: [PartyDefinition]
    ) -> [String] {
        let lines = CombinedLogSplit.split(log: log, combined: party, members: members)
        guard !lines.isEmpty else { return [] }
        var rows: [[String]] = [["Party", "QSOs", ""]]
        for line in lines {
            rows.append([
                line.party.name,
                "\(line.validQSOs)",
                line.qualifiesForChallenge ? "" : "under 2",
            ])
        }
        // The name column reads as a list, not a right-aligned ledger.
        return columns(rows, leftAlignFirst: true)
    }

    /// The score components, in the sidebar's own order and under its own
    /// labels, with the total last — a summary reads to its conclusion.
    private static func scoreTable(
        party: PartyDefinition?, score: ScoreEngine.ScoreBreakdown
    ) -> [String] {
        var pairs: [(String, String)] = [
            ("QSO points", grouped(score.qsoPoints)),
            ("Multipliers", grouped(score.multiplierCount)),
            ("Bonus", "+\(grouped(score.bonusPoints))"),
        ]
        // A member party's summary email asks for the three-way split by name
        // ("Skeeter QSOs — 23 / Non-Skeeter QRP — 5 / Non-Skeeter QRO — 12").
        if let member = party?.memberExchange {
            pairs.append((member.memberPlural, grouped(score.memberQSOs)))
            pairs.append(("QRP / QRO", "\(grouped(score.qrpQSOs)) / \(grouped(score.otherQSOs))"))
        }
        if !score.categoryFactor.isOne {
            pairs.append(("Category ×", score.categoryFactor.displayString))
        }
        if score.dupeCount > 0 {
            pairs.append(("Dupes", grouped(score.dupeCount)))
        }
        pairs.append(("Score", grouped(score.total)))
        return columns(pairs.map { [$0.0, $0.1] }, leftAlignFirst: true)
    }

    // MARK: Fixed-width plumbing

    /// Right-aligns every column to its widest cell, two spaces between — the
    /// first column optionally left-aligned where it holds names rather than
    /// figures.
    private static func columns(
        _ rows: [[String]], leftAlignFirst: Bool = false
    ) -> [String] {
        let width = (0..<(rows.map(\.count).max() ?? 0)).map { column in
            rows.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            let cells = width.indices.map { column -> String in
                let cell = row.indices.contains(column) ? row[column] : ""
                return column == 0 && leftAlignFirst
                    ? pad(cell, to: width[column], left: false)
                    : pad(cell, to: width[column], left: true)
            }
            // A left-aligned last column would otherwise ship trailing spaces
            // into somebody's email.
            return cells.joined(separator: "  ")
                .replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        }
    }

    private static func pad(_ value: String, to width: Int, left: Bool) -> String {
        let fill = String(repeating: " ", count: max(0, width - value.count))
        return left ? fill + value : value + fill
    }

    /// Deterministic grouping. `Int.formatted()` follows the run's locale, so a
    /// golden test would pass in Kansas and fail in Köln.
    private static func grouped(_ value: Int) -> String {
        Self.formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}
