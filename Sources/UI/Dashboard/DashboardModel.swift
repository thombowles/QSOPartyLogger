import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// State for the Contest Dashboard window: reads the logs folder as the
/// history (the `.qplog` files *are* the history — see `LogFolder`), selects
/// a year, and derives stats/standing/upcoming from Core.
@Observable @MainActor
final class DashboardModel {
    var archive: ContestArchive = .empty
    var selectedYear = Date().utcYear
    var loadError: String?
    var isLoading = false
    var lastRefreshed: Date?
    /// Two files for one contest — the later-modified is shown, the rest named.
    var duplicates: [LogFolder.Duplicate] = []
    /// Logs that didn't decode, by name — skipped, never touched.
    var unreadable: [String] = []
    /// Logs iCloud has not downloaded to this Mac yet.
    var downloading = 0

    private(set) var parties: [PartyDefinition] = []
    let challengeCalendar = ChallengeCalendar.loadBundled()
    /// The downloaded park list — the cache Contest Setup's POTA section
    /// fills — for each park's name and state in the POTA list. Nil until
    /// it has been downloaded; the list then shows references alone.
    private(set) var parks: PotaParkDirectory?

    /// Where the logs are — the iCloud logs folder setting in the app, read
    /// at every use so a folder chosen mid-session is followed at once; a
    /// temp folder in tests, so nothing here can reach the real one.
    private let logsFolder: @Sendable () -> URL?
    /// Where the park list comes from — the on-disk cache in the app; a
    /// directory handed in by tests.
    private let parkDirectory: @Sendable () -> PotaParkDirectory?

    init(
        logsFolder: @escaping @Sendable () -> URL? = { CloudMirror.activeFolder() },
        parkDirectory: @escaping @Sendable () -> PotaParkDirectory? = {
            PotaParkStore(folder: PotaParkStore.defaultFolder).loadCached()?.directory
        }
    ) {
        self.logsFolder = logsFolder
        self.parkDirectory = parkDirectory
    }

    /// "Cedar Hill State Park · TX" for a reference the park list knows;
    /// nil for one it does not, or before the list is downloaded.
    func parkLabel(_ reference: String) -> String? {
        parks?.park(reference: reference)?.nameAndState
    }

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

    /// Party IDs whose contest is an always-on program (POTA): their
    /// records feed the POTA widgets and stay out of every contest one.
    private(set) var programPartyIDs: Set<String> = []

    /// The archive minus program records — what the season cards, contests
    /// table and charts read.
    var contestRecords: [ContestRecord] {
        archive.records.filter { !programPartyIDs.contains($0.partyID) }
    }

    /// What the POTA cards and history list read: the program records, and
    /// every contest worked from a park — KSQP from a state park — which is
    /// an outing as well as an entry, its park contacts counted
    /// (`PotaSeason`). Such a record is in `contestRecords` too.
    var potaRecords: [ContestRecord] {
        archive.records.filter { programPartyIDs.contains($0.partyID) || $0.activatesAPark }
    }

    var stats: SeasonStats {
        SeasonStats.compute(records: contestRecords, year: selectedYear)
    }

    var potaSeason: PotaSeason {
        PotaSeason.compute(records: potaRecords, year: selectedYear)
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

    /// The logs folder in use, or nil when none is chosen.
    var logsFolderURL: URL? {
        logsFolder()
    }

    var historyFolderPath: String? {
        logsFolderURL?.path(percentEncoded: false)
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

    /// Read every log in the logs folder. Off the main actor — the folder
    /// holds every QSO of every contest — and a missing folder is simply
    /// empty: the empty state offers the chooser.
    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            lastRefreshed = Date()
        }
        parties = PartyCatalog.allParties()

        guard let folder = logsFolder() else {
            archive = .empty
            programPartyIDs = []
            duplicates = []
            unreadable = []
            downloading = 0
            loadError = nil
            return
        }
        let parkDirectory = parkDirectory
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<LogFolder.History, Error> in
            Result { try LogFolder(url: folder).history() }
        }.value
        // ~13k parks, parsed off the main actor like the history; read on
        // every refresh so a list downloaded mid-session shows on the next.
        parks = await Task.detached(priority: .utility) { parkDirectory() }.value

        switch outcome {
        case .success(let history):
            archive = history.archive
            programPartyIDs = Set(history.archive.records.map(\.partyID)
                .filter { ContestCatalog.contest(id: $0)?.family == .program })
            duplicates = history.duplicates
            unreadable = history.unreadable
            downloading = history.downloading
            loadError = nil
            if !archive.records.isEmpty, !archive.years.contains(selectedYear) {
                selectedYear = archive.years.first ?? selectedYear
            }
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    // MARK: Actions

    /// The export staged for the contests section's save panel — cleared
    /// when the panel closes — and the content type that rides along with
    /// it, because the panel's allowed extensions follow the type: ADIF
    /// needs UTType.adi to keep a ".adi" name, while Cabrillo's ".log" is
    /// a name plain text already claims.
    var stagedExport: ArchivedLogExport.Export?
    var stagedExportType: UTType = .plainText

    /// Whether the record's party rules are installed right now — the same
    /// catalog snapshot the row's name and score affordances read.
    func partyInstalled(_ partyID: String) -> Bool {
        partyNames[partyID] != nil
    }

    func exportADIF(_ record: ContestRecord) {
        do {
            stagedExportType = .adi
            stagedExport = try ArchivedLogExport.adif(
                record: record, folder: logsFolder()
            )
        } catch {
            NSLog("Dashboard: ADIF export failed: \(error)")
        }
    }

    func exportCabrillo(_ record: ContestRecord) {
        do {
            stagedExportType = .plainText
            stagedExport = try ArchivedLogExport.cabrillo(
                record: record, folder: logsFolder()
            )
        } catch {
            NSLog("Dashboard: Cabrillo export failed: \(error)")
        }
    }

    func openLog(_ record: ContestRecord) {
        guard let name = record.sourceFileName,
              let folder = logsFolder() else { return }
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
              let folder = logsFolder() else { return false }
        return FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(name).path(percentEncoded: false)
        )
    }

    /// Open the logs folder — the history — in Finder, the way the toolbar's
    /// iCloud folder button does.
    func revealLogsFolder() {
        guard let folder = logsFolder() else { return }
        NSWorkspace.shared.open(folder)
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
