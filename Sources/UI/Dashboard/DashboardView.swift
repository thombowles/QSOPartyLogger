import SwiftUI

/// The Contest Dashboard window (⌘⇧D): season summary, per-contest scores,
/// State QSO Party Challenge standing, trends, and the upcoming calendar —
/// all read from the one-file history archive in the synced logs folder.
struct DashboardView: View {
    @State private var model = DashboardModel()

    var body: some View {
        Group {
            if model.archive.records.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .navigationTitle("Contest Dashboard")
        .navigationSubtitle(model.historyFolderPath ?? "local history — no iCloud folder chosen")
        .toolbar { toolbarContent }
        .task { await model.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { _ in
            // Another Mac may have synced while this window was in back.
            Task { await model.refresh() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCards
                if let standing = model.standing {
                    DashboardChallengeSection(
                        standing: standing,
                        includesSplitEntry: model.standingIncludesSplitEntry
                    )
                }
                DashboardContestsSection(model: model)
                DashboardUpcomingSection(model: model)
                footer
            }
            .padding(20)
        }
    }

    // MARK: Toolbar (keyboard-first: ⌘[ ⌘] year, ⌘R refresh)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.stepYear(-1)
            } label: {
                Label("Previous Year", systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Previous year (⌘[)")
            .disabled(model.years.sorted().first == model.selectedYear)
            .shortcutHint("⌘[")

            Picker("Year", selection: $model.selectedYear) {
                ForEach(model.years, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .help("Season to summarize")

            Button {
                model.stepYear(1)
            } label: {
                Label("Next Year", systemImage: "chevron.right")
            }
            .keyboardShortcut("]", modifiers: .command)
            .help("Next year (⌘])")
            .disabled(model.years.sorted().last == model.selectedYear)
            .shortcutHint("⌘]")

            Spacer()

            Button {
                Task { await model.importFromLogsFolder() }
            } label: {
                Label("Import Logs", systemImage: "square.and.arrow.down.on.square")
            }
            .help("Scan the logs folder for .qplog files and add them to the history")

            Button {
                model.revealHistoryFile()
            } label: {
                Label("Reveal History File", systemImage: "doc.badge.gearshape")
            }
            .help("Show 'Contest History.qphistory' in Finder")

            Button {
                Task { await model.refresh() }
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Re-read the history file (⌘R)")
            .shortcutHint("⌘R")
        }
    }

    // MARK: Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Contests",
                value: "\(model.stats.contests)",
                detail: "entered in \(String(model.selectedYear))",
                systemImage: "trophy"
            )
            StatCard(
                title: "Valid QSOs",
                value: DashboardFormat.points(model.stats.validQSOs),
                detail: modeSplitText,
                systemImage: "dot.radiowaves.left.and.right"
            )
            StatCard(
                title: "Combined Score",
                value: DashboardFormat.points(model.stats.combinedScore),
                detail: scoredDetailText,
                systemImage: "sum"
            )
            StatCard(
                title: "On-Air Time",
                value: DashboardFormat.minutes(model.stats.operatingMinutes),
                detail: "breaks ≥ 30 min excluded",
                systemImage: "clock"
            )
            StatCard(
                title: "Counties",
                value: DashboardFormat.points(model.stats.countiesWorked),
                detail: "worked across all parties",
                systemImage: "map"
            )
        }
    }

    private var modeSplitText: String {
        let split = ModeClass.allCases
            .compactMap { mode -> String? in
                guard let count = model.stats.qsosByMode[mode.rawValue], count > 0 else { return nil }
                return "\(count) \(mode.displayName)"
            }
            .joined(separator: " · ")
        return split.isEmpty ? "none yet" : split
    }

    private var scoredDetailText: String {
        let unscored = model.stats.contests - model.stats.scoredContests
        return unscored == 0
            ? "claimed totals, all contests"
            : "\(unscored) contest\(unscored == 1 ? "" : "s") without installed rules not included"
    }

    private var footer: some View {
        HStack {
            if let summary = model.importSummary {
                Label(summary, systemImage: "square.and.arrow.down")
            }
            Spacer()
            if let refreshed = model.lastRefreshed {
                Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Empty / degraded states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No contest history yet")
                .font(.title2.weight(.semibold))

            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 460)
            } else {
                Text(
                    model.historyFolderPath == nil
                        ? "Pick your iCloud Drive logs folder so every contest — and this dashboard — syncs across your Macs. Then import the logs you already have."
                        : "Log a contest, or import the .qplog files already in your logs folder."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            }

            HStack(spacing: 10) {
                if model.historyFolderPath == nil {
                    Button("Choose iCloud Folder…") {
                        if CloudMirror.chooseFolder() {
                            Task { await model.refresh() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Import Existing Logs…") {
                    Task { await model.importFromLogsFolder() }
                }
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            if let summary = model.importSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// One headline number with context.
struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
