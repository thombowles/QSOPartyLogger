import Foundation

/// Pure rules-driven scoring: fold the log against a party definition.
/// Score = QSO points × multipliers + bonuses.
enum ScoreEngine {

    struct ScoreBreakdown: Equatable {
        var validQSOs = 0
        var dupeCount = 0
        var qsoPoints = 0
        var multipliers: [MultClass: Set<String>] = [:]
        var bonusPoints = 0
        var dupeRowIDs: Set<UUID> = []
        /// Rows that added at least one new multiplier when first logged.
        var newMultRowIDs: Set<UUID> = []

        var multiplierCount: Int {
            multipliers.values.reduce(0) { $0 + $1.count }
        }

        var total: Int {
            qsoPoints * multiplierCount + bonusPoints
        }
    }

    static func score(log: ContestLog, party: PartyDefinition) -> ScoreBreakdown {
        var result = ScoreBreakdown()
        let rows = log.qsos.sortedChronologically()
        let firstIDs = DupeChecker.firstOccurrenceIDs(rows)
        let countyAbbrs = Set(party.counties.map(\.abbr))
        let rule = log.myLocation.isInState ? party.multipliers.inState : party.multipliers.outState
        let wantedClasses = Set(rule.classes)

        for row in rows {
            guard firstIDs.contains(row.id) else {
                result.dupeCount += 1
                result.dupeRowIDs.insert(row.id)
                continue
            }
            result.validQSOs += 1
            result.qsoPoints += party.points.points(for: row.modeClass)

            for (multClass, value) in multContributions(
                theirLoc: row.theirLoc.uppercased(),
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) where wantedClasses.contains(multClass) || isHomeStateViaCounty(multClass, value, party, rule) {
                if result.multipliers[multClass, default: []].insert(value).inserted {
                    result.newMultRowIDs.insert(row.id)
                }
            }
        }

        result.bonusPoints = bonusPoints(
            rows: rows,
            firstIDs: firstIDs,
            party: party,
            countyAbbrs: countyAbbrs
        )
        return result
    }

    private static func isHomeStateViaCounty(
        _ multClass: MultClass, _ value: String,
        _ party: PartyDefinition, _ rule: PartyDefinition.MultRule
    ) -> Bool {
        rule.homeStateCountsViaCounty && multClass == .state && value == party.homeState
    }

    /// Which multiplier a received location contributes under the given rule.
    private static func multContributions(
        theirLoc: String,
        countyAbbrs: Set<String>,
        party: PartyDefinition,
        rule: PartyDefinition.MultRule
    ) -> [(MultClass, String)] {
        if countyAbbrs.contains(theirLoc) {
            var out: [(MultClass, String)] = [(.county, theirLoc)]
            if rule.homeStateCountsViaCounty {
                // KSQP: the first home-state county logged doubles as the state mult.
                out.append((.state, party.homeState))
            }
            return out
        }
        if MultClass.acceptedStateTokens.contains(theirLoc) {
            return [(.state, theirLoc)]
        }
        if MultClass.canadianProvinces.contains(theirLoc) {
            return [(.province, theirLoc)]
        }
        if theirLoc == MultClass.dxToken {
            return [(.dx, theirLoc)]
        }
        return []
    }

    private static func bonusPoints(
        rows: [QSO],
        firstIDs: Set<UUID>,
        party: PartyDefinition,
        countyAbbrs: Set<String>
    ) -> Int {
        var total = 0
        let valid = rows.filter { firstIDs.contains($0.id) }
        for bonus in party.bonuses {
            switch bonus {
            case .workStation(let call, let points):
                if valid.contains(where: { $0.call.uppercased() == call.uppercased() }) {
                    total += points
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
            }
        }
        return total
    }

    /// Would logging this contact add a new multiplier? (Live "NEW MULT" badge.)
    static func wouldAddMultiplier(
        theirLocs: [String],
        log: ContestLog,
        party: PartyDefinition
    ) -> Bool {
        let current = score(log: log, party: party).multipliers
        let rule = log.myLocation.isInState ? party.multipliers.inState : party.multipliers.outState
        let wantedClasses = Set(rule.classes)
        let countyAbbrs = Set(party.counties.map(\.abbr))
        for loc in theirLocs {
            for (multClass, value) in multContributions(
                theirLoc: loc.uppercased(),
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) where wantedClasses.contains(multClass) || isHomeStateViaCounty(multClass, value, party, rule) {
                if !(current[multClass]?.contains(value) ?? false) {
                    return true
                }
            }
        }
        return false
    }
}
