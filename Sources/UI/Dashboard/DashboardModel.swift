import AppKit
import SwiftUI

/// State for the Contest Dashboard window: loads the archive (merging any
/// iCloud conflict versions and a pre-iCloud local archive first), selects a
/// year, and derives stats/standing/upcoming from Core.
@Observable @MainActor
final class DashboardModel {
    var archive: ContestArchive = .empty
    var selectedYear = Date().utcYear
    var loadError: String?
    var importSummary: String?
    var isLoading = false
    var lastRefreshed: Date?

    private(set) var parties: [PartyDefinition] = []
    let challengeCalendar = ChallengeCalendar.loadBundled()
    private var didAutoImport = false

    // MARK: Derived

    var partyNames: [String: String] {
        Dictionary(uniqueKeysWithValues: parties.map { ($0.id, $0.name) })
    }

    func partyName(for id: String) -> String {
        partyNames[id] ?? id.uppercased()
    }

    /// Years offered by the picker: everything archived plus the current one.
    var years: [Int] {
        Set(archive.years + [Date().utcYear]).sorted(by: >)
    }

    var stats: SeasonStats {
        SeasonStats.compute(records: archive.records, year: selectedYear)
    }

    /// A combined entry is not a contest the Challenge tracks — `in7qpne` is not
    /// on the approved list and never will be — so its record is split into the
    /// member contests it is actually made of first. Unsplit it would count for
    /// nothing; split, one May weekend is worth up to four multipliers, which is
    /// what the four sponsors say it is.
    var standing: ChallengeStanding? {
        challengeCalendar.map {
            ChallengeStanding.compute(
                records: CombinedLogSplit.expand(records: archive.records, parties: parties),
                calendar: $0,
                year: selectedYear,
                partyNames: partyNames
            )
        }
    }

    /// True when a combined log for the selected year was split for the standing
    /// above, so the Challenge section can say where four contests came from
    /// when the operator only opened one.
    var standingIncludesSplitEntry: Bool {
        let combined = Set(parties.filter { !$0.combines.isEmpty }.map(\.id))
        return archive.records.contains {
            $0.year == selectedYear && combined.contains($0.partyID)
        }
    }

    var upcoming: [UpcomingContest] {
        UpcomingContests.upcoming(
            now: Date(),
            parties: parties,
            calendar: challengeCalendar,
            records: archive.records
        )
    }

    var historyFolderPath: String? {
        CloudMirror.isConfigured ? CloudMirror.folderDisplayPath : nil
    }

    var historyFileURL: URL {
        ArchiveStore(folder: ContestHistorian.resolveFolder()).fileURL
    }

    func stepYear(_ delta: Int) {
        let all = years.sorted()
        guard let index = all.firstIndex(of: selectedYear) else {
            selectedYear = all.last ?? Date().utcYear
            return
        }
        let next = index + delta
        if all.indices.contains(next) {
            selectedYear = all[next]
        }
    }

    // MARK: Loading

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            lastRefreshed = Date()
        }
        parties = PartyCatalog.allParties()

        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ContestArchive, Error> in
            // Fold a pre-iCloud local archive in once a folder is chosen…
            let folder = ContestHistorian.resolveFolder()
            _ = try? ContestHistorian.migrate(
                localFolder: ContestHistorian.applicationSupportFolder, into: folder
            )
            // …and any iCloud conflict versions (merge is commutative).
            _ = await ContestHistorian.shared.resolveCloudConflicts()
            do {
                return .success(try ArchiveStore(folder: folder).load())
            } catch {
                return .failure(error)
            }
        }.value

        switch outcome {
        case .success(let loaded):
            archive = loaded
            loadError = nil
            if !archive.records.isEmpty, !archive.years.contains(selectedYear) {
                selectedYear = archive.years.first ?? selectedYear
            }
        case .failure(let error):
            loadError = error.localizedDescription
        }

        // Born populated: with a synced folder configured and no archive yet,
        // pull in whatever .qplog files are already there — once.
        if archive.records.isEmpty, loadError == nil, !didAutoImport,
           CloudMirror.isConfigured,
           !FileManager.default.fileExists(atPath: historyFileURL.path(percentEncoded: false)) {
            didAutoImport = true
            await importFromLogsFolder()
        }
    }

    func importFromLogsFolder() async {
        guard let folder = CloudMirror.activeFolder() else {
            importSummary = "Choose your iCloud logs folder first."
            return
        }
        isLoading = true
        let result = await ContestHistorian.shared.importLogs(from: folder)
        isLoading = false
        var summary = "Imported \(result.imported) log\(result.imported == 1 ? "" : "s")."
        if !result.failed.isEmpty {
            summary += " Couldn't read: \(result.failed.joined(separator: ", "))."
        }
        importSummary = summary
        await refresh()
    }

    // MARK: Actions

    /// The export staged for the contests section's ADIF save panel;
    /// cleared when the panel closes.
    var adifExport: AdifExporter.ArchivedExport?

    /// Whether the record's party rules are installed right now — the same
    /// catalog snapshot the row's name and score affordances read.
    func partyInstalled(_ partyID: String) -> Bool {
        partyNames[partyID] != nil
    }

    func exportADIF(_ record: ContestRecord) {
        do {
            adifExport = try AdifExporter.exportArchived(
                record: record, folder: CloudMirror.activeFolder()
            )
        } catch {
            NSLog("Dashboard: ADIF export failed: \(error)")
        }
    }

    func openLog(_ record: ContestRecord) {
        guard let name = record.sourceFileName,
              let folder = CloudMirror.activeFolder() else { return }
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        NSDocumentController.shared.openDocument(
            withContentsOf: url, display: true
        ) { _, _, error in
            if let error {
                NSLog("Dashboard: open log failed: \(error.localizedDescription)")
            }
        }
    }

    func logFileExists(_ record: ContestRecord) -> Bool {
        guard let name = record.sourceFileName,
              let folder = CloudMirror.activeFolder() else { return false }
        return FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(name).path(percentEncoded: false)
        )
    }

    func revealHistoryFile() {
        NSWorkspace.shared.activateFileViewerSelecting([historyFileURL])
    }
}

/// Shared dashboard formatting.
enum DashboardFormat {
    static func points(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func minutes(_ total: Int) -> String {
        total < 60 ? "\(total)m" : "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }

    /// "Sat Oct 3, 16:00–22:00Z" — contest windows are UTC facts.
    static func window(_ window: PartyDefinition.ScheduleWindow) -> String {
        let day = DateFormatter()
        day.dateFormat = "EEE MMM d"
        day.timeZone = TimeZone(identifier: "UTC")
        day.locale = Locale(identifier: "en_US_POSIX")
        let time = DateFormatter()
        time.dateFormat = "HHmm"
        time.timeZone = TimeZone(identifier: "UTC")
        time.locale = Locale(identifier: "en_US_POSIX")
        return "\(day.string(from: window.start)) \(time.string(from: window.start))–\(time.string(from: window.end))Z"
    }

    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}
