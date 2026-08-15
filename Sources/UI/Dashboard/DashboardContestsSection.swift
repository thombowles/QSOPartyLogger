import Charts
import SwiftUI
import UniformTypeIdentifiers

/// The year's contests: sortable score table (Return or double-click opens
/// the .qplog, ⌘E exports it as ADIF, ⇧⌘E as Cabrillo), a QSOs-per-contest
/// chart, and — with a row selected — that party's all-years trend with the
/// personal best called out.
struct DashboardContestsSection: View {
    @Bindable var model: DashboardModel

    @State private var sortOrder = [KeyPathComparator(\ContestRow.date)]
    @State private var selection: ContestRow.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Contests in \(String(model.selectedYear))", systemImage: "list.number")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    if let row = selectedRow {
                        model.exportADIF(row.record)
                    }
                } label: {
                    Label("Export ADIF…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!(selectedRow?.exportable ?? false))
                .help(exportBlockedReason ?? "Export the selected contest's log as ADIF (⌘E)")
                .shortcutHint("⌘E")

                Button {
                    if let row = selectedRow {
                        model.exportCabrillo(row.record)
                    }
                } label: {
                    Label("Export Cabrillo…", systemImage: "doc.plaintext")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!(selectedRow?.exportable ?? false))
                .help(exportBlockedReason ?? "Export the selected contest's log as Cabrillo (⇧⌘E)")
                .shortcutHint("⇧⌘E")
            }

            if rows.isEmpty {
                Text("Nothing logged in \(String(model.selectedYear)).")
                    .foregroundStyle(.secondary)
            } else {
                table
                charts
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        // The content type follows the staged export — UTType.adi for ADIF
        // so the save panel keeps the .adi name (see LogDocument.swift).
        .fileExporter(
            isPresented: exportPresented,
            document: model.stagedExport.map { TextExportDocument(text: $0.text) },
            contentType: model.stagedExportType,
            defaultFilename: model.stagedExport?.fileName
        ) { _ in
            model.stagedExport = nil
        }
    }

    /// Presented exactly while an export is staged; dismissing the panel
    /// (save or cancel) clears it.
    private var exportPresented: Binding<Bool> {
        Binding(
            get: { model.stagedExport != nil },
            set: { if !$0 { model.stagedExport = nil } }
        )
    }

    /// Why the selection can't export — nil when it can. Shared by both
    /// formats: each needs the saved file and the installed rules alike.
    private var exportBlockedReason: String? {
        guard let row = selectedRow else {
            return "Select a contest, then export its log (⌘E ADIF, ⇧⌘E Cabrillo)"
        }
        if !row.fileAvailable {
            return "Can't export — the log file is no longer in the logs folder"
        }
        if !row.partyInstalled {
            return "Can't export — \(row.partyName) rules are not installed"
        }
        return nil
    }

    // MARK: Rows

    /// Flat, sortable projection of a record for the Table.
    struct ContestRow: Identifiable, Sendable {
        let record: ContestRecord
        let partyName: String
        let fileAvailable: Bool
        let partyInstalled: Bool

        /// ADIF export needs both the saved .qplog (to read) and the party's
        /// installed rules (to render county names and the contest id).
        var exportable: Bool { fileAvailable && partyInstalled }

        var id: String { record.id }
        var date: Date { record.earliestQSO ?? .distantPast }
        var location: String { record.myLocation.displayText }
        var qsos: Int { record.snapshot.validQSOs }
        var dupes: Int { record.snapshot.dupeCount }
        var mults: Int { record.snapshot.figures?.multiplierCount ?? 0 }
        var bonus: Int { record.snapshot.figures?.bonusPoints ?? 0 }
        var score: Int { record.snapshot.figures?.total ?? 0 }
        var scored: Bool { record.snapshot.figures != nil }
        var minutes: Int { record.snapshot.operatingMinutes }
    }

    private var rows: [ContestRow] {
        model.stats.rows.map {
            ContestRow(
                record: $0,
                partyName: model.partyName(for: $0.partyID),
                fileAvailable: model.logFileExists($0),
                partyInstalled: model.partyInstalled($0.partyID)
            )
        }
    }

    private var sortedRows: [ContestRow] {
        rows.sorted(using: sortOrder)
    }

    private var selectedRow: ContestRow? {
        rows.first { $0.id == selection }
    }

    // MARK: Table

    private var table: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { row in
                Text(row.date, format: .dateTime.month(.abbreviated).day())
            }
            .width(70)

            TableColumn("Party", value: \.partyName) { row in
                HStack(spacing: 6) {
                    Text(row.partyName)
                    if row.fileAvailable {
                        Image(systemName: "doc")
                            .foregroundStyle(.tertiary)
                            .help("Log file is in the logs folder — press Return to open")
                    }
                }
            }

            TableColumn("From", value: \.location) { row in
                Text(row.location).monospaced()
            }
            .width(90)

            TableColumn("QSOs", value: \.qsos) { row in
                Text("\(row.qsos)")
                    .monospacedDigit()
                    .help(row.dupes > 0 ? "+\(row.dupes) dupes kept in the log" : "no dupes")
            }
            .width(60)

            TableColumn("Mults", value: \.mults) { row in
                Text(row.scored ? "\(row.mults)" : "—").monospacedDigit()
            }
            .width(60)

            TableColumn("Bonus", value: \.bonus) { row in
                Text(row.scored ? DashboardFormat.points(row.bonus) : "—").monospacedDigit()
            }
            .width(70)

            TableColumn("Time", value: \.minutes) { row in
                Text(DashboardFormat.minutes(row.minutes)).monospacedDigit()
            }
            .width(70)

            TableColumn("Score", value: \.score) { row in
                Text(row.scored ? DashboardFormat.points(row.score) : "rules not installed")
                    .monospacedDigit()
                    .fontWeight(row.scored ? .semibold : .regular)
                    .foregroundStyle(row.scored ? .primary : .secondary)
            }
            .width(100)
        }
        .frame(height: max(140, CGFloat(rows.count) * 28 + 32))
        .onKeyPress(.return) {
            guard let row = selectedRow, row.fileAvailable else { return .ignored }
            model.openLog(row.record)
            return .handled
        }
        .contextMenu(forSelectionType: ContestRow.ID.self) { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                if row.fileAvailable {
                    Button("Open Log") { model.openLog(row.record) }
                }
                Button("Export ADIF…") { model.exportADIF(row.record) }
                    .disabled(!row.exportable)
                Button("Export Cabrillo…") { model.exportCabrillo(row.record) }
                    .disabled(!row.exportable)
            }
        } primaryAction: { ids in
            if let id = ids.first, let row = rows.first(where: { $0.id == id }),
               row.fileAvailable {
                model.openLog(row.record)
            }
        }
    }

    // MARK: Charts

    private var charts: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Valid QSOs by contest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Chart(rows) { row in
                    BarMark(
                        x: .value("QSOs", row.qsos),
                        y: .value("Party", row.partyName)
                    )
                    .foregroundStyle(row.id == selection ? .orange : .blue)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(row.qsos)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: max(120, CGFloat(rows.count) * 26))
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                if let selected = selectedRow {
                    Text("\(selected.partyName) — score by year")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    trendChart(for: selected)
                } else {
                    Text("Score by contest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Chart(rows.filter(\.scored)) { row in
                        BarMark(
                            x: .value("Score", row.score),
                            y: .value("Party", row.partyName)
                        )
                        .foregroundStyle(.teal)
                    }
                    .chartXAxis(.hidden)
                    .frame(height: max(120, CGFloat(rows.count) * 26))
                    Text("Select a contest to see its year-over-year trend.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func trendChart(for row: ContestRow) -> some View {
        let trend = SeasonStats.partyTrend(records: model.archive.records, partyID: row.record.partyID)
            .map { (year: $0.year, score: $0.snapshot.figures?.total ?? 0, qsos: $0.snapshot.validQSOs) }
        let best = trend.max { $0.score < $1.score }

        return VStack(alignment: .leading, spacing: 4) {
            Chart(trend, id: \.year) { point in
                LineMark(
                    x: .value("Year", String(point.year)),
                    y: .value("Score", point.score)
                )
                PointMark(
                    x: .value("Year", String(point.year)),
                    y: .value("Score", point.score)
                )
                .annotation(position: .top) {
                    if point.year == best?.year, trend.count > 1 {
                        Text("best")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(height: max(120, CGFloat(rows.count) * 26))

            if trend.count == 1 {
                Text("First year in this one — the trend starts next season.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
