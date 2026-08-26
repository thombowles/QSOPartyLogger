import SwiftUI

/// The QSO log. County-line rows carry a ⧉ marker with the group's row count;
/// dupes and new mults are flagged from the live score.
struct LogTable: View {
    let qsos: [QSO]
    let score: ScoreEngine.ScoreBreakdown
    let party: PartyDefinition?
    let onDeleteRows: (Set<QSO.ID>) -> Void
    let onDeleteGroup: (QSO) -> Void
    let onEdit: (QSO) -> Void
    /// The POTA row's State and Notes columns (operator report 1,
    /// 2026-08-25) — shown for the POTA contest, where the entry row has
    /// the fields; every party's table keeps its exact columns.
    var showsPotaColumns: Bool = false
    /// Two or more rows selected → the bulk editor, with the selection in
    /// chronological order so its seed value is the earliest contact's.
    let onBulkEdit: ([QSO]) -> Void
    /// Whether a spot has anywhere to go — a callsign to post under and a
    /// network on offer. False leaves the menu item out rather than offering
    /// something that cannot work.
    let canSpot: Bool
    /// Right-click → spot this station, to whichever networks apply. Opens the
    /// confirmation sheet; nothing is posted from the menu itself.
    let onSpotStation: (QSO) -> Void

    /// A set, not one id: shift-click for a range, ⌘-click for scattered rows,
    /// ⌘A for the lot — the selection model N1MM's Log window documents, and
    /// `Table` gives every one of those keyboard paths for free.
    @State private var selection = Set<QSO.ID>()

    private var rows: [QSO] {
        qsos.sortedChronologically().reversed()
    }

    private var groupSizes: [UUID: Int] {
        Dictionary(grouping: qsos, by: \.groupID).mapValues(\.count)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("UTC") { q in
                Text(Self.timeFormatter.string(from: q.timestampUTC))
                    .monospacedDigit()
            }
            .width(48)

            TableColumn("Call") { q in
                Text(q.call).font(.system(.body, design: .monospaced).weight(.medium))
            }
            .width(min: 90, ideal: 110)

            TableColumn("kHz") { q in
                Text(q.freqKHz.map(String.init) ?? q.band.rawValue)
                    .monospacedDigit()
                    .foregroundStyle(q.freqKHz == nil ? .secondary : .primary)
            }
            .width(60)

            TableColumn("Mode") { q in
                Text(q.rawMode)
            }
            .width(48)

            // Whatever this party's exchange actually carries — a name, a QSO
            // number, a report, or the location alone. See `ExchangeSummary`.
            TableColumn("Sent") { q in
                Text(ExchangeSummary.sent(q, party: party)).monospaced()
            }
            .width(min: 76, ideal: 100)

            TableColumn("Rcvd") { q in
                Text(ExchangeSummary.received(q, party: party)).monospaced()
            }
            .width(min: 76, ideal: 100)

            if showsPotaColumns {
                TableColumn("St") { q in
                    Text(q.theirState ?? "").monospaced()
                }
                .width(34)

                TableColumn("Notes") { q in
                    Text(q.notes ?? "")
                        .lineLimit(1)
                        .help(q.notes ?? "")
                }
                .width(min: 80, ideal: 150)
            }

            TableColumn("Pts") { q in
                Text(pointsText(q)).monospacedDigit()
            }
            .width(34)

            TableColumn("Flags") { q in
                HStack(spacing: 4) {
                    if (groupSizes[q.groupID] ?? 1) > 1 {
                        Label("×\(groupSizes[q.groupID]!)", systemImage: "square.on.square")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if score.dupeRowIDs.contains(q.id) {
                        Text("DUPE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    if score.invalidRowIDs.contains(q.id) {
                        Text("INVALID MODE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    if score.outOfScopeRowIDs.contains(q.id) {
                        Text("NO CREDIT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    if score.newMultRowIDs.contains(q.id) {
                        Text("MULT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    // Park-to-park rows, findable at a glance after the
                    // contest without spending a column on a field most
                    // logs never carry.
                    if let parks = q.theirPotaRefs {
                        Label("P2P \(parks.joined(separator: ","))", systemImage: "tree")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                            .help("Park-to-park — their POTA reference(s)")
                    }
                }
            }
            .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: QSO.ID.self) { ids in
            let selected = selectedRows(ids)
            if selected.count > 1 {
                Button("Edit \(selected.count) Contacts…") { onBulkEdit(selected) }
                Divider()
                Button("Delete \(selected.count) Rows", role: .destructive) {
                    onDeleteRows(ids)
                }
            } else if let qso = selected.first {
                Button("Edit…") { onEdit(qso) }
                // One station per post, so this stays single-row however many
                // are selected.
                if canSpot {
                    Button("Spot \(qso.call)…") { onSpotStation(qso) }
                }
                Divider()
                Button("Delete Row", role: .destructive) { onDeleteRows([qso.id]) }
                if (groupSizes[qso.groupID] ?? 1) > 1 {
                    Button("Delete Contact Group (×\(groupSizes[qso.groupID]!))", role: .destructive) {
                        onDeleteGroup(qso)
                    }
                }
            }
        } primaryAction: { ids in
            let selected = selectedRows(ids)
            if selected.count > 1 {
                onBulkEdit(selected)
            } else if let qso = selected.first {
                onEdit(qso)
            }
        }
    }

    /// The selected rows, oldest first. Chronological rather than the table's
    /// newest-first display order, so "the first contact in the selection" —
    /// which is what the bulk sheet seeds from — means the one the operator
    /// worked first.
    private func selectedRows(_ ids: Set<QSO.ID>) -> [QSO] {
        qsos.sortedChronologically().filter { ids.contains($0.id) }
    }

    private func pointsText(_ q: QSO) -> String {
        Self.pointsText(for: q, score: score, party: party)
    }

    /// What the `Pts` column prints for a row: what the engine paid it, and
    /// nothing this view works out for itself. Recomputing here from the
    /// party's mode/location table read every Skeeter Hunt row as 1 while the
    /// score card said 70 (2026-08-16) — that table cannot see the received
    /// Skeeter number or power. A row the engine paid nothing for (a dupe, an
    /// invalid mode, out of scope) is absent from the breakdown and reads 0.
    nonisolated static func pointsText(
        for q: QSO, score: ScoreEngine.ScoreBreakdown, party: PartyDefinition?
    ) -> String {
        guard party != nil else { return "-" }
        return String(score.pointsByRowID[q.id] ?? 0)
    }
}
