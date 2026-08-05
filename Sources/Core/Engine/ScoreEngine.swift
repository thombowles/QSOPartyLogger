import Foundation

/// Pure rules-driven scoring: fold the log against a party definition.
/// Score = QSO points × multipliers × category factors + bonuses.
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
        let multClass: MultClass
        let value: String
        let scope: String
        /// Earned by **operating from** the county rather than by working it
        /// (`MultRule.activatedCountyMultiplier`). Defaults false, so every key
        /// built before this existed is unchanged.
        ///
        /// It is part of the key because SCQP 9.2.2 lists "Each South Carolina
        /// county" and "Each SC county activated" as separate numbered
        /// multipliers with no ceiling, so the two must be able to coexist at
        /// the same scope. Where a sponsor forfeits one for the other,
        /// `notOtherwiseWorked` suppresses the activated key instead.
        let activated: Bool

        init(multClass: MultClass, value: String, scope: String, activated: Bool = false) {
            self.multClass = multClass
            self.value = value
            self.scope = scope
            self.activated = activated
        }
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
        /// All zero for every party without `memberExchange`.
        var memberQSOs = 0
        var qrpQSOs = 0
        var otherQSOs = 0
        var categoryFactor: ScoreFactor = .one
        var outOfScopeCount = 0
        var dupeRowIDs: Set<UUID> = []
        var invalidRowIDs: Set<UUID> = []
        /// Rows the party gives this entrant no credit for at all — an
        /// out-of-state log's contacts with other out-of-state stations, where
        /// the rules restrict credit to home-state stations.
        var outOfScopeRowIDs: Set<UUID> = []
        /// Rows that added at least one new multiplier when first logged.
        var newMultRowIDs: Set<UUID> = []
        /// Counties credited by `MultRule.activatedCountyMultiplier` — earned by
        /// operating from them rather than by working them. Empty for every
        /// party without that rule, which is every party and every out-of-state
        /// log.
        var selfActivatedCounties: Set<String> = []
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
            categoryFactor.applied(to: qsoPoints * multiplierCount) + bonusPoints
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
            // A member-exchange party pays by what the worked station IS —
            // the received element decides (Skeeter 3 / QRP 2 / QRO 1),
            // regardless of mode. An unreadable or absent element falls back
            // to the mode table rather than guessing.
            if let member = party.memberExchange,
               let value = row.memberRcvd.flatMap(MemberExchange.parse) {
                switch value {
                case .member:
                    result.qsoPoints += member.memberPoints
                    result.memberQSOs += 1
                case .power(let watts):
                    if watts <= member.qrpMaxWatts.limit(for: row.modeClass) {
                        result.qsoPoints += member.qrpPoints
                        result.qrpQSOs += 1
                    } else {
                        result.qsoPoints += member.otherPoints
                        result.otherQSOs += 1
                    }
                }
            } else {
                result.qsoPoints += party
                    .pointsTable(forTheirLoc: row.theirLoc, countyAbbrs: countyAbbrs)
                    .points(for: row.modeClass)
            }

            for contribution in multContributions(
                theirLoc: row.theirLoc.uppercased(),
                call: row.call,
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) {
                let multClass = contribution.multClass
                let value = contribution.value
                guard wantedClasses.contains(multClass)
                        || isHomeStateViaCounty(multClass, value, party, rule) else { continue }
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
        ) ?? .one
        // A self-declared entry class (Skeeter Hunt X1–X4) multiplies into
        // the same factor — the sidebar row and the archive's exact pair
        // follow without further plumbing. Absent classes leave `.one`.
        if let entryClass = party.resolvedEntryClass(id: log.entryClassID) {
            result.categoryFactor = result.categoryFactor * entryClass.factor
        }

        result.bonusPoints = bonusPoints(
            rows: contestRows,
            firstIDs: firstIDs,
            log: log,
            party: party,
            countyAbbrs: countyAbbrs,
            breakdown: result
        )

        // Deliberately last. After the worked loop, so a forfeiting rule can see
        // which counties were worked; after the bonuses, so `sweepTiers` keeps
        // counting counties **worked** rather than one the operator sat in.
        addActivatedCountyMultipliers(
            to: &result,
            rows: contestRows.filter { firstIDs.contains($0.id) },
            log: log,
            rule: rule,
            countyAbbrs: countyAbbrs
        )
        return result
    }

    /// The multiplier five sponsors give an in-state entrant for each home-state
    /// county they operate from. A no-op for every party without the rule.
    private static func addActivatedCountyMultipliers(
        to result: inout ScoreBreakdown,
        rows valid: [QSO],
        log: ContestLog,
        rule: PartyDefinition.MultRule,
        countyAbbrs: Set<String>
    ) {
        guard let act = rule.activatedCountyMultiplier,
              log.myLocation.isInState,
              rule.classes.contains(.county),
              act.categories.contains(log.station.categoryStation)
        else { return }

        for (county, rows) in Dictionary(grouping: valid, by: { $0.myLoc.uppercased() })
        where countyAbbrs.contains(county) {
            // The threshold reads all of that county's valid rows, not one
            // scope's worth: every sponsor words it that way ("50 or more valid
            // contacts from a county", "10 or more different stations while
            // operating from a county").
            let count = switch act.countUnit {
            case .qsos: rows.count
            case .stations: Set(rows.map { $0.call.uppercased() }).count
            }
            guard count >= act.minCount else { continue }

            // "…if they do not earn a multiplier for that county otherwise"
            // (TnQP) / "if not otherwise worked" (VAQP). Checked at **any**
            // scope, which is the case set semantics alone cannot handle: TnQP
            // counts worked multipliers per band and grants this one once, so
            // the two keys would never have collided.
            if act.notOtherwiseWorked, workedCounty(county, in: result) { continue }

            // One key per scope component present among that county's own rows,
            // which collapses to a single key under `once` and gives SCQP the
            // "ONCE PER MODE PER BAND" it asks for.
            for scope in Set(rows.map { scopeComponent(act.countScope, row: $0) }) {
                let key = MultKey(multClass: .county, value: county, scope: scope, activated: true)
                if result.multiplierKeys.insert(key).inserted {
                    result.selfActivatedCounties.insert(county)
                }
            }
        }
    }

    /// Was this county earned by working somebody in it, at any scope?
    private static func workedCounty(_ county: String, in result: ScoreBreakdown) -> Bool {
        result.multiplierKeys.contains {
            !$0.activated && $0.multClass == .county && $0.value == county
        }
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
        scope.component(band: band, modeClass: modeClass)
    }

    private static func isHomeStateViaCounty(
        _ multClass: MultClass, _ value: String,
        _ party: PartyDefinition, _ rule: PartyDefinition.MultRule
    ) -> Bool {
        rule.homeStateCountsViaCounty && multClass == .state && value == party.homeState
    }

    /// One multiplier a received location contributes.
    ///
    /// `value` is what the operator sees. For a DX entity that is its primary
    /// prefix, so `DL1AA` and `DJ2BB` both read `DL` and are one multiplier —
    /// the label no longer depends on which you worked first. `dxEntityCode`
    /// is carried anyway, because the primary prefix is a display choice and
    /// the entity code is what actually decides sameness.
    struct Contribution {
        let multClass: MultClass
        let value: String
        var dxEntityCode: String?
    }

    /// Which multiplier(s) a received location contributes under the rule.
    private static func multContributions(
        theirLoc: String,
        call: String,
        countyAbbrs: Set<String>,
        party: PartyDefinition,
        rule: PartyDefinition.MultRule
    ) -> [Contribution] {
        if countyAbbrs.contains(theirLoc) {
            var out: [Contribution] = [Contribution(multClass: .county, value: theirLoc)]
            if rule.homeStateCountsViaCounty {
                // The county's own state, which for every single-state party is
                // the party's — and for a 7QP log is whichever of the seven the
                // county lies in.
                out.append(Contribution(multClass: .state,
                                        value: party.state(forCounty: theirLoc)))
            }
            return out
        }
        // A section party counts sections and nothing else alongside them, so
        // this returns before the state/province tables are consulted: in PAQP
        // "NTX" is a section and "TX" is not a token at all.
        if party.usesSections {
            if party.sections.contains(theirLoc) {
                return [Contribution(multClass: .section, value: theirLoc)]
            }
            if theirLoc == MultClass.dxToken {
                return [Contribution(multClass: .dx, value: MultClass.dxToken)]
            }
            return []
        }
        // A token that is BOTH a state or province code and a real DXCC
        // prefix — PA is Pennsylvania and the Netherlands, ON is Ontario and
        // Belgium — is decided by the worked callsign, and only when the call
        // names the very same entity the token would. So PA0AAA sending "PA"
        // is the Netherlands, while W3XYZ sending it is Pennsylvania, and a
        // VE5 sending "SK" stays Saskatchewan even though SK is Sweden's.
        //
        // The two-channel split is N1MM's: the exchange field says which
        // location was sent, the callsign says which entity sent it. Its
        // manual is blunt about the exchange half — "There is a check on
        // provinces and states, no check on countries."
        //
        // A US or Canadian callsign never triggers it, however well the token
        // matches: the ARRL list's US row is "K, W, N, AA-AK", so Alberta's
        // "AB" falls inside it, and a Canadian entrant would lose AB and SK to
        // a country they are not in. Salmon Run's own rule says the same thing
        // from the other side — "DXCC entities other than US and VE".
        let collidesWithDXCC = rule.dxCountsEntities
            && !DXCCTable.shared.isDomestic(callsign: call)
            && DXCCTable.shared.entity(forPrefix: theirLoc) != nil
            && DXCCTable.shared.entity(forCallsign: call)?.code
                == DXCCTable.shared.entity(forPrefix: theirLoc)?.code

        if !collidesWithDXCC {
            if let aliased = party.stateAliases[theirLoc] {
                return [Contribution(multClass: .state, value: aliased)]
            }
            if MultClass.acceptedStateTokens.contains(theirLoc),
               !party.excludedStateTokens.contains(theirLoc) {
                return [Contribution(multClass: .state, value: theirLoc)]
            }
            if party.provinces.contains(theirLoc) {
                return [Contribution(multClass: .province, value: theirLoc)]
            }
        }
        if theirLoc == MultClass.dxToken {
            // The exchange carries no country, so the callsign names it —
            // which is the whole reason NHQP's "up to 10 DXCC country" and
            // MEQP's uncapped entities could not be counted before.
            guard rule.dxCountsEntities,
                  let m = DXCCTable.shared.match(callsign: call)
            else { return [Contribution(multClass: .dx, value: MultClass.dxToken)] }
            return [Contribution(multClass: .dx, value: m.label, dxEntityCode: m.entity.code)]
        }
        if party.isDXPrefix(theirLoc) || collidesWithDXCC {
            // Here the exchange DOES carry the country, and the sponsor's own
            // received datum outranks a prefix match on the call.
            guard rule.dxCountsEntities,
                  let m = DXCCTable.shared.match(prefix: theirLoc)
            else { return [Contribution(multClass: .dx, value: theirLoc)] }
            return [Contribution(multClass: .dx, value: m.label, dxEntityCode: m.entity.code)]
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

            case .designatedCountySweep(let counties, let need, let points):
                // "If at least one QSO is made with a station in five of the
                // 'Rarest of NC' counties, 500 additional bonus points" — once,
                // at the threshold or past it, however many of the ten are
                // worked.
                if designatedCounties(counties, workedIn: valid).count >= need {
                    total += points
                }

            case .callAreaSum(let target, let points):
                // Skeeter Hunt Blackjack: each DISTINCT worked callsign
                // contributes its call-area digit once ("You can use any
                // call sign worked ONCE"), 0 counts as 10, and the bonus
                // pays once when any subset lands on the target exactly.
                let values = Set(valid.map { $0.call.uppercased() })
                    .compactMap(callAreaValue)
                if subsetSumsExactly(values, target: target) {
                    total += points
                }
            }
        }
        return total
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

    /// Which of a designated county list this log has valid-QSO credit for —
    /// the predicate behind `.designatedCountySweep`, exposed so the sidebar's
    /// progress readout is the same set the score pays on.
    static func designatedCountiesWorked(
        _ designated: [String], log: ContestLog, party: PartyDefinition
    ) -> Set<String> {
        let allowed = Set(party.allowedModeClasses)
        let rows = inScopeRows(
            log.qsos.sortedChronologically().filter { allowed.contains($0.modeClass) },
            log: log,
            party: party,
            countyAbbrs: Set(party.counties.map(\.abbr))
        )
        return designatedCounties(designated, workedIn: rows)
    }

    private static func designatedCounties(_ designated: [String], workedIn rows: [QSO]) -> Set<String> {
        Set(rows.map { $0.theirLoc.uppercased() })
            .intersection(designated.map { $0.uppercased() })
    }

    /// Whether the call-area blackjack target is met by this log's valid rows
    /// — the predicate behind `.callAreaSum`, exposed so the sidebar's badge
    /// is the same computation the score pays on (the
    /// `designatedCountiesWorked` arrangement).
    static func callAreaSumAchieved(
        target: Int, log: ContestLog, party: PartyDefinition
    ) -> Bool {
        let allowed = Set(party.allowedModeClasses)
        let rows = inScopeRows(
            log.qsos.sortedChronologically().filter { allowed.contains($0.modeClass) },
            log: log,
            party: party,
            countyAbbrs: Set(party.counties.map(\.abbr))
        )
        let firstIDs = DupeChecker.firstOccurrenceIDs(rows)
        let values = Set(rows.filter { firstIDs.contains($0.id) }.map { $0.call.uppercased() })
            .compactMap(callAreaValue)
        return subsetSumsExactly(values, target: target)
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
            for c in multContributions(
                theirLoc: loc.uppercased(),
                call: "",
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) where wantedClasses.contains(c.multClass)
                    || isHomeStateViaCounty(c.multClass, c.value, party, rule) {
                let key = MultKey(multClass: c.multClass, value: c.value, scope: scope)
                if !current.contains(key) {
                    // A county the operator has already self-activated under a
                    // forfeiting rule trades one key for another rather than
                    // adding one, so the badge would send them chasing a
                    // multiplier that pays nothing — the same failure the cap
                    // guard above exists to prevent.
                    if c.multClass == .county,
                       let act = rule.activatedCountyMultiplier, act.notOtherwiseWorked,
                       !countyGains(c.value, addingScope: scope, to: current) {
                        continue
                    }
                    return true
                }
            }
        }
        return false
    }

    /// Would working `county` at `scope` raise this log's multiplier total?
    /// Only asked where the entrant's rule forfeits the activation multiplier on
    /// a worked county — everywhere else a key that is absent is a gain.
    private static func countyGains(
        _ county: String, addingScope scope: String, to current: Set<MultKey>
    ) -> Bool {
        let keys = current.filter { $0.multClass == .county && $0.value == county }
        let worked = Set(keys.filter { !$0.activated }.map(\.scope))
        let activated = keys.filter(\.activated).count
        let before = worked.count + activated
        let after = worked.union([scope]).count      // the forfeited activation goes to zero
        return after > before
    }
}
