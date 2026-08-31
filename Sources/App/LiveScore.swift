import Foundation
import Observation

/// The one score fold per log change, shared by every reader.
///
/// Before this existed the sidebar, the log table's flags, the advisor, the
/// NEW MULT badge and the band map each folded the whole log themselves —
/// 7 ms a fold at 2,000 rows in Release, roughly four folds per keystroke
/// (`Tests/Core/ContestScalePerfTests.swift`, 2026-08-30). Now the fold runs
/// lazily, once, on the first read after a change; every other read is a
/// cache hit. A view that reads these properties observes
/// `LogDocument.generation`, so it renders when the log changes — never per
/// keystroke.
///
/// The cache stores are `@ObservationIgnored` deliberately (the
/// `BandMapModel` rule, 2026-07-25): derived data written during a body pass
/// must not invalidate the very view that is reading it.
@MainActor
@Observable
final class LiveScore {
    private let document: LogDocument

    /// Catalog lookups, injectable so a test states definitions directly
    /// instead of reaching the bundle. Cached by id below, like `EntryFlow`'s,
    /// because `PartyCatalog.party(id:)` re-reads the user folder every call.
    @ObservationIgnored var partyResolver: (String) -> PartyDefinition? = { PartyCatalog.party(id: $0) }
    @ObservationIgnored var contestResolver: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }

    /// How many times the engine has actually folded — the cache's test seam.
    @ObservationIgnored private(set) var foldCount = 0

    init(document: LogDocument) {
        self.document = document
    }

    /// The score as the engine computes it — the same value every reader
    /// used to fold for itself.
    var breakdown: ScoreEngine.ScoreBreakdown { refreshed().breakdown }

    /// The current multiplier keys, for the NEW MULT badge and the band map
    /// (`ScoreEngine.wouldAddMultiplier(current:)`).
    var multiplierKeys: Set<ScoreEngine.MultKey> { refreshed().breakdown.multiplierKeys }

    /// Valid-QSO counts per band and mode — the sidebar's matrix, computed
    /// with the same fold cadence as the score.
    var bandModeCounts: [Band: [ModeClass: Int]] { refreshed().bandModeCounts }

    /// Party dupe keys (`DupeChecker.key(_:)`) for the live dupe warning.
    var dupeKeys: Set<DupeChecker.DupeKey> { refreshed().dupeKeys }

    /// Rule-keyed dupes for a v2-only contest (POTA); nil while a party is
    /// live, where `dupeKeys` is the set the warning reads.
    var ruleDupeKeys: Set<DupeChecker.RuleKey>? { refreshed().ruleDupeKeys }

    /// The log table's rows, newest first — sorted once per log change
    /// instead of on every render pass (the table used to re-sort at up to
    /// 2 Hz while the radio poll invalidated the window).
    var displayRows: [QSO] { tableRefreshed().rows }

    /// Each contact group's row count, for the table's ⧉ marker — built once
    /// per change instead of per visible cell.
    var groupSizes: [UUID: Int] { tableRefreshed().groupSizes }

    /// Calls already in the log on this band and mode, uppercased — the spot
    /// filter's grey-out set. Memoised per band|mode within a generation.
    func workedCalls(band: Band, modeClass: ModeClass) -> Set<String> {
        workedSets(band: band, modeClass: modeClass).calls
    }

    /// The same, paired `CALL|LOC`, so a mobile that has moved counties is
    /// not mistaken for a station already worked.
    func workedCallCounties(band: Band, modeClass: ModeClass) -> Set<String> {
        workedSets(band: band, modeClass: modeClass).counties
    }

    // MARK: The cache

    private struct Cache {
        var generation: Int
        var partyID: String
        var breakdown: ScoreEngine.ScoreBreakdown
        var bandModeCounts: [Band: [ModeClass: Int]]
        var dupeKeys: Set<DupeChecker.DupeKey>
        var ruleDupeKeys: Set<DupeChecker.RuleKey>?
    }

    @ObservationIgnored private var cache: Cache?
    @ObservationIgnored private var partyCache: (id: String, party: PartyDefinition?)?
    @ObservationIgnored private var contestCache: (id: String, contest: ContestDefinition?)?
    @ObservationIgnored private var workedCache:
        (generation: Int, sets: [String: (calls: Set<String>, counties: Set<String>)]) = (-1, [:])
    @ObservationIgnored private var tableCache: (generation: Int, rows: [QSO], groupSizes: [UUID: Int])?

    private func tableRefreshed() -> (generation: Int, rows: [QSO], groupSizes: [UUID: Int]) {
        let generation = document.generation
        if let tableCache, tableCache.generation == generation { return tableCache }
        let qsos = document.log.qsos
        let fresh = (generation,
                     Array(qsos.sortedChronologically().reversed()),
                     Dictionary(grouping: qsos, by: \.groupID).mapValues(\.count))
        tableCache = fresh
        return fresh
    }

    private func refreshed() -> Cache {
        // Observed on purpose: reading the score is how a view subscribes to
        // the log. The stamp is what makes "did anything change" O(1).
        let generation = document.generation
        let log = document.log
        if let cache, cache.generation == generation, cache.partyID == log.partyID { return cache }

        var fresh = Cache(
            generation: generation, partyID: log.partyID,
            breakdown: ScoreEngine.ScoreBreakdown(), bandModeCounts: [:],
            dupeKeys: Set(log.qsos.map(DupeChecker.key)), ruleDupeKeys: nil
        )
        if let party = party(id: log.partyID) {
            fresh.breakdown = ScoreEngine.score(log: log, party: party)
            fresh.bandModeCounts = ScoreEngine.bandModeCounts(log: log, party: party)
            foldCount += 1
        } else if let contest = contest(id: log.partyID) {
            fresh.breakdown = ScoreEngine.score(log: log, contest: contest)
            fresh.bandModeCounts = ScoreEngine.bandModeCounts(log: log, contest: contest)
            fresh.ruleDupeKeys = Set(log.qsos.map { DupeChecker.key($0, rule: contest.dupe) })
            foldCount += 1
        }
        cache = fresh
        return fresh
    }

    private func workedSets(band: Band, modeClass: ModeClass) -> (calls: Set<String>, counties: Set<String>) {
        let generation = document.generation
        if workedCache.generation != generation { workedCache = (generation, [:]) }
        let key = "\(band.rawValue)|\(modeClass.rawValue)"
        if let hit = workedCache.sets[key] { return hit }
        var calls = Set<String>()
        var counties = Set<String>()
        for q in document.log.qsos where q.band == band && q.modeClass == modeClass {
            let call = q.call.uppercased()
            calls.insert(call)
            counties.insert("\(call)|\(q.theirLoc.uppercased())")
        }
        workedCache.sets[key] = (calls, counties)
        return (calls, counties)
    }

    private func party(id: String) -> PartyDefinition? {
        if let partyCache, partyCache.id == id { return partyCache.party }
        let looked = partyResolver(id)
        partyCache = (id, looked)
        return looked
    }

    /// Only consulted where no party claims the id (POTA), like
    /// `EntryFlow.standaloneContest`.
    private func contest(id: String) -> ContestDefinition? {
        if let contestCache, contestCache.id == id { return contestCache.contest }
        let looked = contestResolver(id)
        contestCache = (id, looked)
        return looked
    }
}
