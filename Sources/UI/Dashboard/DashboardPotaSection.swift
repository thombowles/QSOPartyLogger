import SwiftUI

/// The POTA history list — separate from the contests table, because an
/// outing is not a contest entry: the year's outings one row per log, with
/// parks, QSOs, activation validity against POTA's ten, P2P, states, DX and
/// time. Return or double-click opens the .qplog; the per-park submission
/// files are made from the open log (⌥⌘E), where the parks are.
struct DashboardPotaSection: View {
    @Bindable var model: DashboardModel

    @State private var sortOrder = [KeyPathComparator(\PotaRow.date)]
    @State private var selection: PotaRow.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("POTA in \(String(model.selectedYear))", systemImage: "tree")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Return opens an outing's log — export its POTA files there (⌥⌘E)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                Text("No POTA outings in \(String(model.selectedYear)).")
                    .foregroundStyle(.secondary)
            } else {
                table
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Rows

    /// Flat, sortable projection of an outing for the Table.
    struct PotaRow: Identifiable, Sendable {
        let outing: PotaSeason.Outing
        let fileAvailable: Bool

        var id: String { outing.id }
        var date: Date { outing.date }
        var parks: String { outing.parks.joined(separator: " ") }
        /// The contest a park was worked during — nil for a POTA log.
        var contest: String? { outing.isContest ? outing.record.partyID.uppercased() : nil }
        var qsos: Int { outing.qsos }
        var p2p: Int { outing.p2pContacts }
        var states: Int { outing.states }
        var dx: Int { outing.dxEntities }
        var minutes: Int { outing.minutes }
        /// Sorting the Activation column ranks by park-days made valid.
        var validParkDays: Int { outing.validParkDays }

        var activation: String {
            DashboardPotaSection.activationLabel(
                valid: outing.validParkDays,
                total: outing.parkDays.count,
                unique: outing.parkDays.count == 1 ? outing.parkDays.first?.unique : nil
            )
        }

        /// The tooltip: every park-day spelled out.
        var activationDetail: String {
            guard !outing.parkDays.isEmpty else {
                return "No park of your own on this outing — hunting"
            }
            return outing.parkDays.map { day in
                let status = day.valid
                    ? "✓ activated"
                    : "\(day.unique)/\(PotaStats.validationTarget) unique"
                return "\(day.park) · \(day.day.formatted(DashboardPotaSection.utcDay)) — \(status)"
            }.joined(separator: "\n")
        }
    }

    /// Park-days are UTC facts, like every contest time in the app.
    nonisolated static let utcDay = Date.FormatStyle(
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "UTC")!
    ).month(.abbreviated).day()

    private var rows: [PotaRow] {
        model.potaSeason.outings.map {
            PotaRow(outing: $0, fileAvailable: model.logFileExists($0.record))
        }
    }

    private var sortedRows: [PotaRow] {
        rows.sorted(using: sortOrder)
    }

    private var selectedRow: PotaRow? {
        rows.first { $0.id == selection }
    }

    // MARK: Table

    private var table: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { row in
                Text(row.date, format: .dateTime.month(.abbreviated).day())
            }
            .width(70)

            TableColumn("Park(s)", value: \.parks) { row in
                HStack(spacing: 6) {
                    Text(row.parks.isEmpty ? "hunting" : row.parks)
                        .monospaced()
                        .foregroundStyle(row.parks.isEmpty ? .secondary : .primary)
                    if let contest = row.contest {
                        Text(contest)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .help("Worked from the park during \(contest) — the contest is in the contests table as well; only the contacts made from the park count here")
                    }
                    if row.fileAvailable {
                        Image(systemName: "doc")
                            .foregroundStyle(.tertiary)
                            .help("Log file is in the logs folder — press Return to open")
                    }
                }
            }

            TableColumn("QSOs", value: \.qsos) { row in
                Text("\(row.qsos)").monospacedDigit()
            }
            .width(60)

            TableColumn("Activation", value: \.validParkDays) { row in
                Text(row.activation)
                    .monospacedDigit()
                    .help(row.activationDetail)
            }
            .width(110)

            TableColumn("P2P", value: \.p2p) { row in
                Text("\(row.p2p)").monospacedDigit()
            }
            .width(50)

            TableColumn("States", value: \.states) { row in
                Text("\(row.states)").monospacedDigit()
            }
            .width(55)

            TableColumn("DX", value: \.dx) { row in
                Text("\(row.dx)").monospacedDigit()
            }
            .width(45)

            TableColumn("Time", value: \.minutes) { row in
                Text(DashboardFormat.minutes(row.minutes)).monospacedDigit()
            }
            .width(70)
        }
        .frame(height: max(140, CGFloat(rows.count) * 28 + 32))
        .onKeyPress(.return) {
            guard let row = selectedRow, row.fileAvailable else { return .ignored }
            model.openLog(row.outing.record)
            return .handled
        }
        .contextMenu(forSelectionType: PotaRow.ID.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }),
               row.fileAvailable {
                Button("Open Log") { model.openLog(row.outing.record) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }),
               row.fileAvailable {
                model.openLog(row.outing.record)
            }
        }
    }

    /// The Activation cell: hunting, one park-day against POTA's ten, or
    /// how many of a rove's park-days made it.
    nonisolated static func activationLabel(valid: Int, total: Int, unique: Int?) -> String {
        guard total > 0 else { return "hunting" }
        if total == 1, let unique {
            return valid == 1
                ? "✓ \(unique) unique"
                : "\(unique)/\(PotaStats.validationTarget) unique"
        }
        return (valid == total ? "✓ " : "") + "\(valid)/\(total) valid"
    }
}
