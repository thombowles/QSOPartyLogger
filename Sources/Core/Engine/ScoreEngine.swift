import Foundation

/// Pure rules-driven scoring: fold the log against a party definition.
/// Score = QSO points × multipliers × category factors + bonuses.
enum ScoreEngine {

    /// One counted multiplier. `scope` is "" (once), a mode raw value
    /// (perMode), a band raw value (perBand), or "band/mode" (perBandMode).
    struct MultKey: Hashable, Sendable {
        let multClass: MultClass
        let value: String
        let scope: String
    }

    struct ScoreBreakdown: Equatable {
        var validQSOs = 0
        var dupeCount = 0
        var invalidModeCount = 0
        var qsoPoints = 0
        var multiplierKeys: Set<MultKey> = []
        var bonusPoints = 0
        var categoryFactor = 1
        var outOfScopeCount = 0
        var dupeRowIDs: Set<UUID> = []
        var invalidRowIDs: Set<UUID> = []
        /// Rows the party gives this entrant no credit for at all — an
        /// out-of-state log's contacts with other out-of-state stations, where
        /// the rules restrict credit to home-state stations.
        var outOfScopeRowIDs: Set<UUID> = []
        /// Rows that added at least one new multiplier when first logged.
        var newMultRowIDs: Set<UUID> = []
        /// Set from the entrant's `MultRule.maxScoredMultipliers` where the
        /// party pays for fewer multipliers than it recognises (CQP: 58 of 63).
        var multiplierCap: Int?

        /// Multipliers that reach the score. Every key is still tallied in
        /// `multiplierKeys` — the cap limits what is paid for, not what counts
        /// as worked, which is the sponsor's own distinction.
        var multiplierCount: Int {
            min(multiplierKeys.count, multiplierCap ?? .max)
        }

        var total: Int {
            qsoPoints * multiplierCount * categoryFactor + bonusPoints
        }

        /// Unique values worked for a class, regardless of scope — for the
        /// sidebar county grid and per-class chips.
        func workedValues(_ multClass: MultClass) -> Set<String> {
            Set(multiplierKeys.filter { $0.multClass == multClass }.map(\.value))
        }

        /// Per-class scoped counts, for the sidebar breakdown.
        var classCounts: [MultClass: Int] {
            Dictionary(grouping: multiplierKeys, by: \.multClass).mapValues(\.count)
        }
    }

    static func score(log: ContestLog, party: PartyDefinition) -> ScoreBreakdown {
        var result = ScoreBreakdown()
        let rows = log.qsos.sortedChronologically()
        let allowedModes = Set(party.allowedModeClasses)
        let countyAbbrs = Set(party.counties.map(\.abbr))

        // Invalid-mode rows are not contest QSOs at all (WA: "we cannot
        // accept" digital) — they never enter dupe/point/mult accounting.
        let inAllowedMode = rows.filter { allowedModes.contains($0.modeClass) }
        result.invalidRowIDs = Set(rows.map(\.id)).subtracting(inAllowedMode.map(\.id))
        result.invalidModeCount = result.invalidRowIDs.count

        // Neither are contacts the rules give this entrant no credit for
        // (MDC 10b: non-MDC stations may only work MD/DC).
        let contestRows = inScopeRows(inAllowedMode, log: log, party: party, countyAbbrs: countyAbbrs)
        result.outOfScopeRowIDs = Set(inAllowedMode.map(\.id)).subtracting(contestRows.map(\.id))
        result.outOfScopeCount = result.outOfScopeRowIDs.count

        let firstIDs = DupeChecker.firstOccurrenceIDs(contestRows)
        let rule = log.myLocation.isInState ? party.multipliers.inState : party.multipliers.outState
        let wantedClasses = Set(rule.classes)
        result.multiplierCap = rule.maxScoredMultipliers
        var dxCount = 0

        // Multipliers the party hands over without them being worked (PAQP's
        // EPA and WPA, which no station ever sends). Scoped once, since the
        // sponsor adds them to the tally rather than to a QSO.
        for granted in rule.granted where wantedClasses.contains(granted.multClass) {
            result.multiplierKeys.insert(
                MultKey(multClass: granted.multClass, value: granted.value, scope: "")
            )
        }

        for row in contestRows {
            guard firstIDs.contains(row.id) else {
                result.dupeCount += 1
                result.dupeRowIDs.insert(row.id)
                continue
            }
            result.validQSOs += 1
            result.qsoPoints += party
                .pointsTable(forTheirLoc: row.theirLoc, countyAbbrs: countyAbbrs)
                .points(for: row.modeClass)

            for (multClass, value) in multContributions(
                theirLoc: row.theirLoc.uppercased(),
                call: row.call,
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) where wantedClasses.contains(multClass) || isHomeStateViaCounty(multClass, value, party, rule) {
                if multClass == .dx, let cap = rule.dxMultCap,
                   dxCount >= cap,
                   !result.multiplierKeys.contains(where: { $0.multClass == .dx && $0.value == value }) {
                    continue
                }
                let key = MultKey(
                    multClass: multClass,
                    value: value,
                    scope: scopeComponent(rule.countScope, row: row)
                )
                if result.multiplierKeys.insert(key).inserted {
                    result.newMultRowIDs.insert(row.id)
                    if multClass == .dx,
                       result.workedValues(.dx).count > dxCount {
                        dxCount = result.workedValues(.dx).count
                    }
                }
            }
        }

        result.categoryFactor = party.scoreMultipliers?.factor(
            power: log.station.categoryPower,
            station: log.station.categoryStation
        ) ?? 1

        result.bonusPoints = bonusPoints(
            rows: contestRows,
            firstIDs: firstIDs,
            log: log,
            party: party,
            countyAbbrs: countyAbbrs,
            breakdown: result
        )
        return result
    }

    /// Drops contacts an out-of-state entrant earns no credit for, in parties
    /// that restrict them to home-state stations. A no-op everywhere else.
    private static func inScopeRows(
        _ rows: [QSO],
        log: ContestLog,
        party: PartyDefinition,
        countyAbbrs: Set<String>
    ) -> [QSO] {
        guard party.outStateWorksHomeStationsOnly, !log.myLocation.isInState else { return rows }
        return rows.filter { countyAbbrs.contains($0.theirLoc.uppercased()) }
    }

    private static func scopeComponent(_ scope: PartyDefinition.CountScope, row: QSO) -> String {
        scopeComponent(scope, band: row.band, modeClass: row.modeClass)
    }

    private static func scopeComponent(
        _ scope: PartyDefinition.CountScope, band: Band, modeClass: ModeClass
    ) -> String {
        switch scope {
        case .once: ""
        case .perMode: modeClass.rawValue
        case .perBand: band.rawValue
        case .perBandMode: "\(band.rawValue)/\(modeClass.rawValue)"
        }
    }

    private static func isHomeStateViaCounty(
        _ multClass: MultClass, _ value: String,
        _ party: PartyDefinition, _ rule: PartyDefinition.MultRule
    ) -> Bool {
        rule.homeStateCountsViaCounty && multClass == .state && value == party.homeState
    }

    /// Which multiplier(s) a received location contributes under the rule.
    private static func multContributions(
        theirLoc: String,
        call: String,
        countyAbbrs: Set<String>,
        party: PartyDefinition,
        rule: PartyDefinition.MultRule
    ) -> [(MultClass, String)] {
        if countyAbbrs.contains(theirLoc) {
            var out: [(MultClass, String)] = [(.county, theirLoc)]
            if rule.homeStateCountsViaCounty {
                out.append((.state, party.homeState))
            }
            return out
        }
        // A section party counts sections and nothing else alongside them, so
        // this returns before the state/province tables are consulted: in PAQP
        // "NTX" is a section and "TX" is not a token at all.
        if party.usesSections {
            if party.sections.contains(theirLoc) {
                return [(.section, theirLoc)]
            }
            if theirLoc == MultClass.dxToken {
                return [(.dx, MultClass.dxToken)]
            }
            return []
        }
        if let aliased = party.stateAliases[theirLoc] {
            return [(.state, aliased)]
        }
        if MultClass.acceptedStateTokens.contains(theirLoc),
           !party.excludedStateTokens.contains(theirLoc) {
            return [(.state, theirLoc)]
        }
        if party.provinces.contains(theirLoc) {
            return [(.province, theirLoc)]
        }
        if theirLoc == MultClass.dxToken {
            return [(.dx, MultClass.dxToken)]
        }
        if party.isPlausibleDXPrefix(theirLoc) {
            return [(.dx, theirLoc)]
        }
        return []
    }

    private static func bonusPoints(
        rows: [QSO],
        firstIDs: Set<UUID>,
        log: ContestLog,
        party: PartyDefinition,
        countyAbbrs: Set<String>,
        breakdown: ScoreBreakdown
    ) -> Int {
        var total = 0
        let valid = rows.filter { firstIDs.contains($0.id) }
        for bonus in party.bonuses {
            switch bonus {
            case .workStation(let call, let points, let scope):
                let matches = valid.filter { $0.call.uppercased() == call.uppercased() }
                guard !matches.isEmpty else { break }
                switch scope {
                case .once:
                    total += points
                case .perMode:
                    total += Set(matches.map(\.modeClass)).count * points
                case .perBandMode:
                    total += Set(matches.map { "\($0.band.rawValue)/\($0.modeClass.rawValue)" })
                        .count * points
                case .perQSO:
                    total += matches.count * points
                }

            case .mobileCountyCount(let per, let points):
                // One contact per county per station; every `per` distinct
                // counties a (mobile) station is worked in earns the bonus.
                var countiesByCall: [String: Set<String>] = [:]
                for row in valid where countyAbbrs.contains(row.theirLoc.uppercased()) {
                    countiesByCall[row.call.uppercased(), default: []].insert(row.theirLoc.uppercased())
                }
                for (_, counties) in countiesByCall {
                    total += (counties.count / per) * points
                }

            case .activatedCountyCount(let minQSOs, let points):
                // My own activation bonus: in-state mobile/rover/portable
                // earning per county with >= minQSOs valid QSOs made from it.
                guard log.myLocation.isInState, isRovingCategory(log.station.categoryStation) else { break }
                let byMyCounty = Dictionary(grouping: valid) { $0.myLoc.uppercased() }
                for (county, qsos) in byMyCounty
                where countyAbbrs.contains(county) && qsos.count >= minQSOs {
                    total += points
                }

            case .sweepTiers(let tiers):
                let worked = breakdown.workedValues(.county).count
                if let best = tiers.filter({ worked >= $0.count }).max(by: { $0.count < $1.count }) {
                    total += best.points
                }
            }
        }
        return total
    }

    private static func isRovingCategory(_ category: StationProfile.CategoryStation) -> Bool {
        switch category {
        case .mobile, .rover, .portable, .expedition: true
        case .fixed, .school: false
        }
    }

    /// Valid (non-dupe, allowed-mode) QSO counts per band and mode class —
    /// the sidebar's "QSOs by band" matrix.
    static func bandModeCounts(log: ContestLog, party: PartyDefinition) -> [Band: [ModeClass: Int]] {
        let allowed = Set(party.allowedModeClasses)
        let rows = inScopeRows(
            log.qsos.sortedChronologically().filter { allowed.contains($0.modeClass) },
            log: log,
            party: party,
            countyAbbrs: Set(party.counties.map(\.abbr))
        )
        let firstIDs = DupeChecker.firstOccurrenceIDs(rows)
        var out: [Band: [ModeClass: Int]] = [:]
        for row in rows where firstIDs.contains(row.id) {
            out[row.band, default: [:]][row.modeClass, default: 0] += 1
        }
        return out
    }

    /// Would logging this contact add a new multiplier? (Live "NEW MULT" badge.)
    static func wouldAddMultiplier(
        theirLocs: [String],
        band: Band,
        modeClass: ModeClass,
        log: ContestLog,
        party: PartyDefinition
    ) -> Bool {
        guard party.allowedModeClasses.contains(modeClass) else { return false }
        let current = score(log: log, party: party).multiplierKeys
        let rule = log.myLocation.isInState ? party.multipliers.inState : party.multipliers.outState
        // Past the party's scored ceiling, a further multiplier pays nothing, so
        // the badge must not send the operator chasing it (CQP: 58 of 63).
        if let cap = rule.maxScoredMultipliers, current.count >= cap { return false }
        let wantedClasses = Set(rule.classes)
        let countyAbbrs = Set(party.counties.map(\.abbr))
        let scope = scopeComponent(rule.countScope, band: band, modeClass: modeClass)

        for loc in theirLocs {
            for (multClass, value) in multContributions(
                theirLoc: loc.uppercased(),
                call: "",
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) where wantedClasses.contains(multClass) || isHomeStateViaCounty(multClass, value, party, rule) {
                let key = MultKey(multClass: multClass, value: value, scope: scope)
                if !current.contains(key) {
                    return true
                }
            }
        }
        return false
    }
}
