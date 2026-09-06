import SwiftUI

/// The Contest Dashboard window (⌘⇧D): season summary, per-contest scores,
/// State QSO Party Challenge standing, trends, and the upcoming calendar —
/// all read straight from the `.qplog` files in the synced logs folder,
/// which are the history.
struct DashboardView: View {
    @State private var model = DashboardModel()
    /// Hidden widgets, stored as the pure type's raw string — one pref for
    /// every dashboard window, so the layout composed once holds.
    @AppStorage("dashboardHiddenWidgets") private var hiddenWidgetsRaw = ""

    private var visibility: DashboardWidgetVisibility {
        DashboardWidgetVisibility(rawValue: hiddenWidgetsRaw)
    }

    private func showsBinding(_ widget: DashboardWidget) -> Binding<Bool> {
        Binding(
            get: { visibility.shows(widget) },
            set: { _ in
                var toggled = visibility
                toggled.toggle(widget)
                hiddenWidgetsRaw = toggled.rawValue
            }
        )
    }

    var body: some View {
        Group {
            if model.archive.records.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        // A window of its own, never a tab among the logs (`LogWindowTabs`).
        .background(WindowAccessor { $0.tabbingMode = .disallowed })
        .navigationTitle("Contest Dashboard")
        .navigationSubtitle(model.historyFolderPath ?? "no logs folder chosen")
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
                if visibility.shows(.seasonCards) { summaryCards }
                if visibility.shows(.potaCards) { potaCards }
                if visibility.shows(.challenge), let standing = model.standing {
                    DashboardChallengeSection(
                        standing: standing,
                        includesSplitEntry: model.standingIncludesSplitEntry
                    )
                }
                if visibility.shows(.contests) { DashboardContestsSection(model: model) }
                if visibility.shows(.pota) { DashboardPotaSection(model: model) }
                if visibility.shows(.upcoming) { DashboardUpcomingSection(model: model) }
                if visibility.allHidden {
                    Label(
                        "Every widget is hidden — the toolbar Widgets menu (or ⌘1–⌘6) brings them back.",
                        systemImage: "rectangle.grid.1x2"
                    )
                    .foregroundStyle(.secondary)
                }
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

            Menu {
                ForEach(DashboardWidget.allCases) { widget in
                    Toggle(widget.title, isOn: showsBinding(widget))
                        .keyboardShortcut(KeyEquivalent(widget.shortcutKey), modifiers: .command)
                }
            } label: {
                Label("Widgets", systemImage: "rectangle.grid.1x2")
            }
            .help("Show or hide dashboard widgets — compose the dashboard you want (⌘1–⌘6)")
            .shortcutHint("⌘1–6")

            Button {
                model.revealLogsFolder()
            } label: {
                Label("Reveal Logs Folder", systemImage: "folder")
            }
            .disabled(model.logsFolderURL == nil)
            .help("Open the logs folder in Finder — its .qplog files are this history; delete a log to drop it")

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
            .help("Re-read the logs folder (⌘R)")
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

    /// POTA's own headline numbers — the season cards above count contests
    /// only, an outing is not a contest entry.
    private var potaCards: some View {
        let pota = model.potaSeason
        return HStack(spacing: 12) {
            StatCard(
                title: "Activations",
                value: "\(pota.activations)",
                detail: activationsDetail(pota),
                systemImage: "tree"
            )
            StatCard(
                title: "Parks",
                value: "\(pota.parksActivated)",
                detail: "activated in \(String(model.selectedYear))",
                systemImage: "mappin.and.ellipse"
            )
            StatCard(
                title: "POTA QSOs",
                value: DashboardFormat.points(pota.qsos),
                detail: modeSplit(pota.qsosByMode),
                systemImage: "dot.radiowaves.left.and.right"
            )
            StatCard(
                title: "Park-to-Park",
                value: "\(pota.p2pContacts)",
                detail: pota.parksHunted == 0
                    ? "no parks hunted yet"
                    : "\(pota.parksHunted) distinct park\(pota.parksHunted == 1 ? "" : "s") hunted",
                systemImage: "arrow.left.arrow.right"
            )
            StatCard(
                title: "States · DX",
                value: "\(pota.states) · \(pota.dxEntities)",
                detail: "states · DX entities worked",
                systemImage: "globe.americas"
            )
        }
    }

    private func activationsDetail(_ pota: PotaSeason) -> String {
        guard pota.activations > 0 else { return "none yet" }
        let short = pota.activations - pota.validActivations
        return short == 0
            ? "all valid (≥ \(PotaStats.validationTarget) QSOs)"
            : "\(pota.validActivations) valid · \(short) short of \(PotaStats.validationTarget)"
    }

    private var modeSplitText: String {
        modeSplit(model.stats.qsosByMode)
    }

    private func modeSplit(_ byMode: [String: Int]) -> String {
        let split = ModeClass.allCases
            .compactMap { mode -> String? in
                guard let count = byMode[mode.rawValue], count > 0 else { return nil }
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

    /// The facts that make an incomplete or untidy folder look like what it
    /// is: logs still downloading from iCloud, two files for one contest,
    /// and files that couldn't be read (skipped, never touched).
    private var footer: some View {
        HStack(spacing: 14) {
            if model.downloading > 0 {
                Label(
                    "\(model.downloading) log\(model.downloading == 1 ? "" : "s") still downloading from iCloud — refresh in a moment",
                    systemImage: "icloud.and.arrow.down"
                )
            }
            ForEach(model.duplicates, id: \.shown) { duplicate in
                Label(
                    "Two files for one contest — showing \(duplicate.shown); also \(duplicate.others.joined(separator: ", "))",
                    systemImage: "doc.on.doc"
                )
                .help("The later-modified file is shown. Delete or move the other if it is a stale copy.")
            }
            if !model.unreadable.isEmpty {
                Label(
                    "Couldn't read: \(model.unreadable.joined(separator: ", ")) (left untouched)",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                .help("These files in the logs folder don't decode as logs. They were skipped and never overwritten.")
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
                        ? "Pick your iCloud Drive logs folder. The .qplog files saved there are your contest history, on every Mac."
                        : "The .qplog files in your logs folder are your history — log a contest, or drop the logs you already have into the folder."
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
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            if model.downloading > 0 {
                Label(
                    "\(model.downloading) log\(model.downloading == 1 ? "" : "s") still downloading from iCloud — refresh in a moment",
                    systemImage: "icloud.and.arrow.down"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !model.unreadable.isEmpty {
                Label(
                    "Couldn't read: \(model.unreadable.joined(separator: ", ")) (left untouched)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
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
