import Foundation

/// Pure rules-driven scoring: fold the log against a contest definition.
/// Score = QSO points × multipliers × category factors + bonuses.
///
/// The engine itself lives in `ScoreEngine+Contest.swift`, on
/// `ContestDefinition`. The `PartyDefinition` overloads here lower the party
/// (`PartyLowering.lowered`, cached) and delegate, so a QSO party is scored
/// by exactly the same fold as any other contest — every per-party test
/// exercises the general engine through them.
///
/// The category factor may be a fraction (VTQP and WIQP both pay ×1.5 for low
/// power), so it is applied to the `QSO points × multipliers` product and
/// resolved down to a whole number there — **before** bonuses, which the
/// sponsors add afterwards and never scale. Wisconsin states the order
/// outright: *"Then multiply by your multiplier count under MULTIPLIERS.
/// Finally, add your bonus points."*
enum ScoreEngine {

    /// One counted multiplier. `scope` is "" (once), a mode raw value
    /// (perMode), a band raw value (perBand), or "band/mode" (perBandMode).
    struct MultKey: Hashable, Sendable {
        /// The multiplier class — `MultiplierClass.id`. The six party classes
        /// keep `MultClass`'s raw values (`county`, `state`, `province`, `dx`,
        /// `section`, `member`), so persisted snapshots and sidebar keys read
        /// unchanged; a general contest adds `zone`, `country`, `prefix`…
        let classID: String
        let value: String
        let scope: String
        /// Earned by **operating from** the token rather than by working it
        /// (`SideRules.activated`). Defaults false, so every key built before
        /// this existed is unchanged.
        ///
        /// It is part of the key because SCQP 9.2.2 lists "Each South Carolina
        /// county" and "Each SC county activated" as separate numbered
        /// multipliers with no ceiling, so the two must be able to coexist at
        /// the same scope. Where a sponsor forfeits one for the other,
        /// `notOtherwiseWorked` suppresses the activated key instead.
        let activated: Bool

        init(classID: String, value: String, scope: String, activated: Bool = false) {
            self.classID = classID
            self.value = value
            self.scope = scope
            self.activated = activated
        }

        /// The party classes, by enum.
        init(multClass: MultClass, value: String, scope: String, activated: Bool = false) {
            self.init(classID: multClass.rawValue, value: value, scope: scope, activated: activated)
        }

        /// The class as a `MultClass`, for the party-shaped readers (sidebar,
        /// roster); nil for a class the parties do not have.
        var multClass: MultClass? { MultClass(rawValue: classID) }
    }

    struct ScoreBreakdown: Equatable {
        var validQSOs = 0
        var dupeCount = 0
        var invalidModeCount = 0
        var qsoPoints = 0
        var multiplierKeys: Set<MultKey> = []
        var bonusPoints = 0
        /// Valid-QSO counts by the received member element's class — the
        /// three lines the Skeeter Hunt's summary email asks for ("Skeeter
        /// QSOs - 23 / Non-Skeeter QRP QSOs - 5 / Non-Skeeter QRO QSOs").
        /// All zero for every contest without a member-or-power element.
        var memberQSOs = 0
        var qrpQSOs = 0
        var otherQSOs = 0
        var categoryFactor: ScoreFactor = .one
        var outOfScopeCount = 0
        var dupeRowIDs: Set<UUID> = []
        var invalidRowIDs: Set<UUID> = []
        /// Rows the contest gives this entrant no credit for at all — an
        /// out-of-state log's contacts with other out-of-state stations, where
        /// the rules restrict credit to home-state stations (`pairing`).
        var outOfScopeRowIDs: Set<UUID> = []
        /// Rows that added at least one new multiplier when first logged.
        var newMultRowIDs: Set<UUID> = []
        /// Tokens credited by `SideRules.activated` — earned by operating from
        /// them rather than by working them. Empty for every contest without
        /// that rule, which is every party but five and every out-of-state log.
        var selfActivatedCounties: Set<String> = []
        /// Set from the entrant's `SideRules.maxScoredMultipliers` where the
        /// contest pays for fewer multipliers than it recognises (CQP: 58 of 63).
        var multiplierCap: Int?
        /// Set from the entrant's `SideRules.multiplierFloor` — the count that
        /// reaches the score never drops below it (FOBB's printed "Defaults
        /// to … = 1"). 0 everywhere else, which is inert.
        var multiplierFloor = 0
        /// What each row was paid, for the log list's `Pts` column — set for
        /// every row that earned points; a dupe, an invalid-mode row, an
        /// out-of-scope or out-of-time row is absent. The list prints this and
        /// computes nothing of its own (the Skeeter Hunt lesson, 2026-08-16).
        var pointsByRowID: [UUID: Int] = [:]
        /// Rows past the contest's operating-time limit — logged and exported,
        /// unscored (SS 1.2, WPX FAQ). Empty for every contest without a rule.
        var outOfTimeRowIDs: Set<UUID> = []
        var outOfTimeCount: Int { outOfTimeRowIDs.count }
        /// Operating and credited off minutes under the contest's rule; 0 without one.
        var operatedMinutes = 0
        var offMinutes = 0

        /// Multipliers that reach the score. Every key is still tallied in
        /// `multiplierKeys` — the cap limits what is paid for and the floor
        /// holds the product up, neither changing what counts as worked,
        /// which is the sponsors' own distinction.
        var multiplierCount: Int {
            max(min(multiplierKeys.count, multiplierCap ?? .max), multiplierFloor)
        }

        var total: Int {
            categoryFactor.applied(to: qsoPoints * multiplierCount) + bonusPoints
        }

        /// Unique values worked for a class, regardless of scope — for the
        /// sidebar county grid and per-class chips.
        func workedValues(_ multClass: MultClass) -> Set<String> {
            workedValues(classID: multClass.rawValue)
        }

        func workedValues(classID: String) -> Set<String> {
            Set(multiplierKeys.filter { $0.classID == classID }.map(\.value))
        }

        /// Per-class scoped counts for the party classes, for the sidebar breakdown.
        var classCounts: [MultClass: Int] {
            var out: [MultClass: Int] = [:]
            for key in multiplierKeys { if let c = key.multClass { out[c, default: 0] += 1 } }
            return out
        }

        /// Per-class scoped counts by class id — every class, party or not.
        var countsByClassID: [String: Int] {
            Dictionary(grouping: multiplierKeys, by: \.classID).mapValues(\.count)
        }
    }

    // MARK: The party overloads — lower, then the model engine

    static func score(log: ContestLog, party: PartyDefinition) -> ScoreBreakdown {
        score(log: log, contest: PartyLowering.lowered(party))
    }

    /// Would logging this contact add a new multiplier? (Live "NEW MULT" badge.)
    /// A county line's several received locations are several candidate rows.
    static func wouldAddMultiplier(
        theirLocs: [String],
        band: Band,
        modeClass: ModeClass,
        log: ContestLog,
        party: PartyDefinition,
        call: String = "",
        memberRcvd: String? = nil
    ) -> Bool {
        wouldAddMultiplier(received: multiplierCandidates(theirLocs: theirLocs, memberRcvd: memberRcvd),
                           call: call, band: band, modeClass: modeClass,
                           log: log, contest: PartyLowering.lowered(party))
    }

    /// The badge against a key set the caller already holds — the entry row's
    /// per-keystroke path, answered without re-scoring the log.
    static func wouldAddMultiplier(
        theirLocs: [String],
        band: Band,
        modeClass: ModeClass,
        log: ContestLog,
        party: PartyDefinition,
        call: String = "",
        memberRcvd: String? = nil,
        current: Set<MultKey>
    ) -> Bool {
        wouldAddMultiplier(received: multiplierCandidates(theirLocs: theirLocs, memberRcvd: memberRcvd),
                           call: call, band: band, modeClass: modeClass,
                           log: log, contest: PartyLowering.lowered(party), current: current)
    }

    /// A county line's several received locations are several candidate rows.
    private static func multiplierCandidates(theirLocs: [String], memberRcvd: String?) -> [[String: String]] {
        theirLocs.map { loc in
            var rcvd = [ExchangeElementID.location: loc]
            if let memberRcvd { rcvd[ExchangeElementID.member] = memberRcvd }
            return rcvd
        }
    }

    /// Valid (non-dupe, allowed-mode) QSO counts per band and mode class —
    /// the sidebar's "QSOs by band" matrix.
    static func bandModeCounts(log: ContestLog, party: PartyDefinition) -> [Band: [ModeClass: Int]] {
        bandModeCounts(log: log, contest: PartyLowering.lowered(party))
    }

    /// Which of a designated county list this log has valid-QSO credit for —
    /// the predicate behind `.designatedCountySweep`, exposed so the sidebar's
    /// progress readout is the same set the score pays on.
    static func designatedCountiesWorked(
        _ designated: [String], log: ContestLog, party: PartyDefinition
    ) -> Set<String> {
        designatedCountiesWorked(designated, log: log, contest: PartyLowering.lowered(party))
    }

    /// Whether the call-area blackjack target is met by this log's valid rows
    /// — the predicate behind `.callAreaSum`, exposed so the sidebar's badge
    /// is the same computation the score pays on.
    static func callAreaSumAchieved(
        target: Int, log: ContestLog, party: PartyDefinition
    ) -> Bool {
        callAreaSumAchieved(target: target, log: log, contest: PartyLowering.lowered(party))
    }

    // MARK: Shared arithmetic

    /// Internal rather than private so `NeededMult` can ask the same question
    /// the scorer answers. Two implementations of "what does *worked on 20 m*
    /// mean" is a scoring bug factory.
    static func scopeComponent(
        _ scope: PartyDefinition.CountScope, band: Band, modeClass: ModeClass
    ) -> String {
        scope.component(band: band, modeClass: modeClass)
    }

    /// The call-area value of a callsign: its first decimal digit, with 0
    /// worth 10 — "Each call area number is worth that many points with the
    /// '0' area call signs being worth 10 points." A call with no digit
    /// contributes nothing. The first digit is an inference for non-US call
    /// shapes, recorded in the carrying party's notes.
    static func callAreaValue(_ call: String) -> Int? {
        guard let digit = call.first(where: \.isWholeNumber),
              let value = digit.wholeNumberValue
        else { return nil }
        return value == 0 ? 10 : value
    }

    /// Whether some subset of `values` (each usable once) sums to exactly
    /// `target`. Plain 0/1 subset-sum over a boolean table — values are
    /// call-area digits, so both axes stay tiny.
    static func subsetSumsExactly(_ values: [Int], target: Int) -> Bool {
        guard target >= 0 else { return false }
        var reachable = [Bool](repeating: false, count: target + 1)
        reachable[0] = true
        for value in values where value > 0 && value <= target {
            for sum in stride(from: target, through: value, by: -1)
            where reachable[sum - value] {
                reachable[sum] = true
            }
            if reachable[target] { return true }
        }
        return reachable[target]
    }

    /// The designated tokens among the rows' received locations.
    static func designatedCounties(_ designated: [String], workedIn rows: [QSO]) -> Set<String> {
        Set(rows.map { $0.theirLoc.uppercased() })
            .intersection(designated.map { $0.uppercased() })
    }

    static func isRovingCategory(_ category: StationProfile.CategoryStation) -> Bool {
        switch category {
        case .mobile, .rover, .portable, .expedition: true
        case .fixed, .school: false
        }
    }

    /// Would working `value` of `classID` at `scope` raise this log's
    /// multiplier total? Only asked where the entrant's rule forfeits the
    /// activation multiplier on a worked token — everywhere else a key that
    /// is absent is a gain.
    ///
    /// Internal for the same reason as `scopeComponent`: the NEW MULT badge,
    /// the advisor's needed-mult chips and the score itself must agree about
    /// which tokens still pay.
    static func gains(classID: String, value: String, addingScope scope: String, to current: Set<MultKey>) -> Bool {
        let keys = current.filter { $0.classID == classID && $0.value == value }
        let worked = Set(keys.filter { !$0.activated }.map(\.scope))
        let activated = keys.filter(\.activated).count
        let before = worked.count + activated
        let after = worked.union([scope]).count      // the forfeited activation goes to zero
        return after > before
    }

    /// `gains` for the county class — what `NeededMult` asks.
    static func countyGains(_ county: String, addingScope scope: String, to current: Set<MultKey>) -> Bool {
        gains(classID: MultClass.county.rawValue, value: county, addingScope: scope, to: current)
    }
}
