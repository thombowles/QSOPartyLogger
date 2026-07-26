import SwiftUI

/// The QSO log. County-line rows carry a ⧉ marker with the group's row count;
/// dupes and new mults are flagged from the live score.
struct LogTable: View {
    let qsos: [QSO]
    let score: ScoreEngine.ScoreBreakdown
    let party: PartyDefinition?
    let onDeleteRow: (QSO) -> Void
    let onDeleteGroup: (QSO) -> Void
    let onEdit: (QSO) -> Void
    /// Whether this party is on the QSO Party Hub and there is a callsign to
    /// post under. False leaves the menu item out rather than offering
    /// something that cannot work.
    let canSpotToHub: Bool
    /// Right-click → post this station to the hub. Opens the confirmation
    /// sheet; nothing is posted from the menu itself.
    let onSpotToHub: (QSO) -> Void

    @State private var selection: QSO.ID?

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

            TableColumn("Sent") { q in
                Text("\(q.rstSent) \(q.myLoc)").monospaced()
            }
            .width(min: 76, ideal: 90)

            TableColumn("Rcvd") { q in
                Text("\(q.rstRcvd) \(q.theirLoc)").monospaced()
            }
            .width(min: 76, ideal: 90)

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
                }
            }
            .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: QSO.ID.self) { ids in
            if let id = ids.first, let qso = qsos.first(where: { $0.id == id }) {
                Button("Edit…") { onEdit(qso) }
                if canSpotToHub {
                    Button("Spot \(qso.call) to QSO Party Hub…") { onSpotToHub(qso) }
                }
                Divider()
                Button("Delete Row", role: .destructive) { onDeleteRow(qso) }
                if (groupSizes[qso.groupID] ?? 1) > 1 {
                    Button("Delete Contact Group (×\(groupSizes[qso.groupID]!))", role: .destructive) {
                        onDeleteGroup(qso)
                    }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let qso = qsos.first(where: { $0.id == id }) {
                onEdit(qso)
            }
        }
    }

    private func pointsText(_ q: QSO) -> String {
        guard let party else { return "-" }
        if score.dupeRowIDs.contains(q.id)
            || score.invalidRowIDs.contains(q.id)
            || score.outOfScopeRowIDs.contains(q.id) { return "0" }
        // Parties that pay by who was worked (MEQP) need the row's location,
        // not just its mode — otherwise a 2-point Maine QSO displays as 1.
        let table = party.pointsTable(
            forTheirLoc: q.theirLoc,
            countyAbbrs: Set(party.counties.map(\.abbr))
        )
        return String(table.points(for: q.modeClass))
    }
}
