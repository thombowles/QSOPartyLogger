import Foundation

/// The scoring engine on the general model (spec §1.4): fold a log against a
/// `ContestDefinition`. `score(log:party:)` and the other `PartyDefinition`
/// overloads in `ScoreEngine.swift` lower first and come here.
///
/// Every row lands in exactly one bucket, in this order of precedence:
/// invalid mode → out of scope (pairing) → out of time → dupe → valid. Only
/// valid rows earn points and multipliers.
extension ScoreEngine {

    // MARK: Classification

    struct Classified {
        /// The entrant's side, resolved against the contest.
        let side: String
        /// Allowed-mode, in-scope rows, chronological — what operating time is measured over.
        let contestRows: [QSO]
        /// `contestRows` less the out-of-time rows — what dupes, points and multipliers are computed over.
        let scoredRows: [QSO]
        let firstIDs: Set<UUID>
        let invalidRowIDs: Set<UUID>
        let outOfScopeRowIDs: Set<UUID>
        let operatingTime: OperatingTime.Result

        /// The rows that count: first occurrences among the scored rows.
        var validRows: [QSO] { scoredRows.filter { firstIDs.contains($0.id) } }
    }

    static func classify(log: ContestLog, contest: ContestDefinition) -> Classified {
        let rows = log.qsos.sortedChronologically()
        let side = contest.resolvedSideID(log.sideID)
        // Invalid-mode rows are not contest QSOs at all (WA: "we cannot
        // accept" digital) — they never enter dupe/point/mult accounting.
        let allowedModes = Set(contest.modeClasses)
        let rawModes = contest.allowedRawModes.map { Set($0.map { $0.uppercased() }) }
        let inAllowedMode = rows.filter {
            allowedModes.contains($0.modeClass) && (rawModes?.contains($0.rawMode.uppercased()) ?? true)
        }
        let invalid = Set(rows.map(\.id)).subtracting(inAllowedMode.map(\.id))
        // Neither are contacts the rules give this entrant no credit for (MDC
        // 10b: non-MDC stations may only work MD/DC) — rows whose worked side
        // is not one this side is paired with.
        let workable = Set(contest.workableSides(for: side))
        let contestRows = inAllowedMode.filter { row in
            workedSideID(of: row, contest: contest).map(workable.contains) ?? false
        }
        let outOfScope = Set(inAllowedMode.map(\.id)).subtracting(contestRows.map(\.id))
        // Rows past the operating-time limit are logged and exported but earn
        // nothing (SS 1.2, WPX FAQ). Measured over every contest row, dupes
        // included — a dupe is still time on the air.
        var operatingTime = OperatingTime.Result.zero
        var scored = contestRows
        if let rule = contest.operatingTime, rule.applies(to: log.categoryValues) {
            operatingTime = OperatingTime.compute(rows: contestRows, rule: rule)
            scored = contestRows.filter { !operatingTime.outOfTimeRowIDs.contains($0.id) }
        }
        return Classified(
            side: side, contestRows: contestRows, scoredRows: scored,
            firstIDs: DupeChecker.firstOccurrenceIDs(scored, rule: contest.dupe),
            invalidRowIDs: invalid, outOfScopeRowIDs: outOfScope, operatingTime: operatingTime
        )
    }

    /// The first side whose `workedPredicate` accepts the row's received
    /// exchange and callsign; nil when none does (a callsign no side claims).
    static func workedSideID(of row: QSO, contest: ContestDefinition) -> String? {
        let needsGeo = contest.sides.contains {
            $0.workedPredicate.kind == .dxccIn || $0.workedPredicate.kind == .continentIn
        }
        let geo = needsGeo ? CTYTable.shared?.match(callsign: row.call) : nil
        let ctx = SidePredicate.Context(
            exchange: row.rcvd.mapValues { [$0] },
            entityCode: geo?.entity.entityCode, continent: geo?.continent,
            sets: { contest.tokenSet(id: $0) }
        )
        return contest.sides.first { $0.workedPredicate.matches(ctx) }?.id
    }

    // MARK: Score

    static func score(log: ContestLog, contest: ContestDefinition) -> ScoreBreakdown {
        var result = ScoreBreakdown()
        let c = classify(log: log, contest: contest)
        result.invalidRowIDs = c.invalidRowIDs
        result.invalidModeCount = c.invalidRowIDs.count
        result.outOfScopeRowIDs = c.outOfScopeRowIDs
        result.outOfScopeCount = c.outOfScopeRowIDs.count
        result.outOfTimeRowIDs = c.operatingTime.outOfTimeRowIDs
        result.operatedMinutes = c.operatingTime.operatedMinutes
        result.offMinutes = c.operatingTime.offMinutes

        let side = c.side
        let sideRules = contest.rules(for: side)
        result.multiplierCap = sideRules.maxScoredMultipliers
        result.multiplierFloor = sideRules.multiplierFloor
        let classes = contest.multipliers.filter { $0.counting[side] != nil }

        // Multipliers the contest hands over without them being worked (PAQP's
        // EPA and WPA). Scoped once, since the sponsor adds them to the tally
        // rather than to a QSO. Only for a class this side counts.
        var distinctValues: [String: Set<String>] = [:]
        for granted in sideRules.granted where classes.contains(where: { $0.id == granted.classID }) {
            result.multiplierKeys.insert(MultKey(classID: granted.classID, value: granted.value, scope: ""))
            distinctValues[granted.classID, default: []].insert(granted.value)
        }

        let memberElement = contest.exchange.first { $0.kind == .memberOrPower }
        let geoNeeded = contest.points.contains { $0.when.contains { $0.relation != nil || $0.bothInContinent != nil } }
        let myGeo = geoNeeded ? CTYTable.shared?.match(callsign: log.station.callsign) : nil
        // The token elements this side receives, their sets resolved once for
        // the whole fold — never per row (`ExchangeValidator.ResolvedSets`).
        let resolved = resolvedTokenSets(for: side, contest: contest)

        for row in c.scoredRows {
            guard c.firstIDs.contains(row.id) else {
                result.dupeCount += 1
                result.dupeRowIDs.insert(row.id)
                continue
            }
            result.validQSOs += 1
            let kind = workedStationKind(row: row, memberElement: memberElement)
            switch kind {
            case "member": result.memberQSOs += 1
            case "qrp": result.qrpQSOs += 1
            case "other": result.otherQSOs += 1
            default: break
            }
            let points = PointRule.points(contest.points, pointsContext(
                row: row, side: side, contest: contest, workedStationKind: kind, myGeo: myGeo, geoNeeded: geoNeeded))
            result.qsoPoints += points
            result.pointsByRowID[row.id] = points

            for (cls, value) in multiplierValues(rcvd: row.rcvd, call: row.call, side: side, classes: classes,
                                                 contest: contest, resolved: resolved) {
                guard let scope = cls.counting[side] else { continue }
                // A per-side cap on distinct values (WA in-state: 10 DX): a
                // value already held may still add a new scope key; a new
                // value past the cap does not.
                if let cap = cls.cap(for: side), let seen = distinctValues[cls.id], seen.count >= cap, !seen.contains(value) {
                    continue
                }
                let key = MultKey(classID: cls.id, value: value, scope: scope.component(band: row.band, modeClass: row.modeClass))
                if result.multiplierKeys.insert(key).inserted {
                    result.newMultRowIDs.insert(row.id)
                    distinctValues[cls.id, default: []].insert(value)
                }
            }
        }

        result.categoryFactor = categoryFactor(contest: contest, log: log)
        result.bonusPoints = bonusPoints(valid: c.validRows, log: log, contest: contest, breakdown: result)
            + declaredBonusPoints(contest: contest, log: log)
        // Deliberately last: after the worked loop, so a forfeiting rule can
        // see which tokens were worked; after the bonuses, so `sweepTiers`
        // keeps counting tokens **worked** rather than one the operator sat in.
        addActivatedMultipliers(to: &result, valid: c.validRows, log: log, contest: contest, side: side)
        return result
    }

    // MARK: Points

    /// `member` / `qrp` / `other` from the received member-or-power element,
    /// or nil where the contest has no such element. A blank element is a QRO
    /// station, not a gap (`MemberExchange.workedClass`).
    static func workedStationKind(row: QSO, memberElement: ExchangeElement?) -> String? {
        guard let element = memberElement, let spec = element.member else { return nil }
        guard let raw = row.rcvd[element.id], let value = MemberExchange.parse(raw) else { return "other" }
        switch value {
        case .member: return "member"
        case .power(let watts): return watts <= spec.qrpMaxWatts.limit(for: row.modeClass) ? "qrp" : "other"
        }
    }

    static func pointsContext(row: QSO, side: String, contest: ContestDefinition, workedStationKind: String?,
                              myGeo: CTYTable.Match?, geoNeeded: Bool) -> PointCondition.Context {
        var relation: PointCondition.Relation?
        var shared: String?
        if geoNeeded, let mine = myGeo, let theirs = CTYTable.shared?.match(callsign: row.call) {
            // The same cty record is the same country (CQ WW's 0-point rule);
            // the continent columns decide the rest.
            if mine.entity.primaryPrefix == theirs.entity.primaryPrefix { relation = .sameEntity }
            else if mine.continent == theirs.continent { relation = .sameContinent }
            else { relation = .differentContinent }
            if mine.continent == theirs.continent { shared = mine.continent }
        }
        return PointCondition.Context(
            modeClass: row.modeClass, band: row.band, relation: relation, sharedContinent: shared,
            side: side, workedSide: workedSideID(of: row, contest: contest) ?? "",
            received: row.rcvd.mapValues { $0.uppercased() }, workedStationKind: workedStationKind,
            call: row.call, sets: { contest.tokenSet(id: $0) }
        )
    }

    // MARK: Multipliers

    private static let dxTokenSet = "dxToken"
    private static let dxccPrefixSet = "dxccPrefix"

    /// The token elements an entrant on `side` receives, each with its sets
    /// resolved once (`ExchangeValidator.resolvedSets`) — built per `score`
    /// or per NEW MULT question, reused for every row.
    static func resolvedTokenSets(for side: String, contest: ContestDefinition) -> [String: ExchangeValidator.ResolvedSets] {
        var out: [String: ExchangeValidator.ResolvedSets] = [:]
        for element in contest.receivedElements(for: side) where element.kind == .token {
            out[element.id] = ExchangeValidator.resolvedSets(for: element, contest: contest, side: side)
        }
        return out
    }

    /// Every (class, value) a row contributes for an entrant on `side`: for
    /// each class the side counts, the first resolver — in order, among those
    /// that apply to the side and callsign — that yields a value.
    static func multiplierValues(rcvd: [String: String], call: String, side: String, classes: [MultiplierClass],
                                 contest: ContestDefinition,
                                 resolved: [String: ExchangeValidator.ResolvedSets]) -> [(MultiplierClass, String)] {
        let owners = tokenOwners(rcvd: rcvd, call: call, side: side, classes: classes, resolved: resolved)
        var out: [(MultiplierClass, String)] = []
        for cls in classes {
            for r in cls.resolvers where r.applies(side: side, call: call) {
                if let value = resolve(r, rcvd: rcvd, call: call, owners: owners, contest: contest) {
                    out.append((cls, value))
                    break
                }
            }
        }
        return out
    }

    /// Element id → the set that owns the row's received token, for every
    /// token element the side receives: `ExchangeValidator.owningSet` — the
    /// classification validation itself uses — plus the callsign override,
    /// applied here, before any class's resolvers run, so a colliding token is
    /// never credited twice.
    static func tokenOwners(rcvd: [String: String], call: String, side: String,
                            classes: [MultiplierClass],
                            resolved: [String: ExchangeValidator.ResolvedSets]) -> [String: String] {
        var owners: [String: String] = [:]
        for (elementID, sets) in resolved {
            guard let raw = rcvd[elementID],
                  var owner = ExchangeValidator.owningSet(of: raw, in: sets)
            else { continue }
            // A token that is BOTH an enumerated set's token and a real DXCC
            // prefix — PA is Pennsylvania and the Netherlands, ON is Ontario
            // and Belgium — is decided by the worked callsign where a class
            // counting entities says so (`callsignOverrides`), and only when
            // the call names the very same entity the token would: PA0AAA
            // sending "PA" is the Netherlands, W3XYZ sending it is
            // Pennsylvania, and a VE5 sending "SK" stays Saskatchewan even
            // though SK is Sweden's. A US or Canadian callsign never triggers
            // it (the ARRL US row is "K, W, N, AA-AK", so Alberta's "AB" falls
            // inside it). N1MM's split: the exchange says which location was
            // sent, the callsign which entity sent it.
            let overrides = classes.flatMap { cls in
                cls.resolvers
                    .filter { $0.kind == .dxccEntity && $0.element == elementID && $0.applies(side: side, call: call) }
                    .flatMap { $0.callsignOverrides ?? [] }
            }
            if overrides.contains(owner),
               let prefixEntity = DXCCTable.shared.entity(forPrefix: raw),
               !DXCCTable.shared.isDomestic(callsign: call),
               DXCCTable.shared.entity(forCallsign: call)?.code == prefixEntity.code {
                owner = dxccPrefixSet
            }
            owners[elementID] = owner
        }
        return owners
    }

    /// The value one resolver yields for a row, or nil.
    static func resolve(_ r: Resolver, rcvd: [String: String], call: String,
                        owners: [String: String], contest: ContestDefinition) -> String? {
        switch r.kind {
        case .receivedToken:
            // Fires only when the token belongs to this resolver's set; the
            // value is the set's canonical token (aliases fold here, not in
            // the log), or the token's group where `mapTo: "group"` (a
            // county's state).
            guard let element = r.element, let setID = r.set, let raw = rcvd[element], owners[element] == setID,
                  let set = contest.tokenSet(id: setID), let canonical = set.canonical(raw) else { return nil }
            return r.mapTo == "group" ? set.token(for: canonical)?.group : canonical
        case .dxccEntity:
            switch r.from {
            case .callsign:
                return entityValue(callsign: call, resolver: r)
            case .receivedToken:
                // The received token read as a prefix; a token the roster does
                // not know is credited as itself.
                guard let element = r.element, let raw = rcvd[element] else { return nil }
                guard r.countEntities, let m = DXCCTable.shared.match(prefix: raw) else { return raw.uppercased() }
                return m.label
            case .receivedTokenOrCallsign:
                // The parties: the literal `DX` names the country by the
                // callsign; a prefix names it itself, and the sponsor's own
                // received datum outranks a prefix match on the call. Where the
                // class does not tell entities apart, `DX` is one multiplier
                // and a prefix token is credited as typed.
                guard let element = r.element, let raw = rcvd[element] else { return nil }
                switch owners[element] {
                case dxTokenSet:
                    guard r.countEntities, let m = DXCCTable.shared.match(callsign: call) else { return MultClass.dxToken }
                    return m.label
                case dxccPrefixSet:
                    guard r.countEntities, let m = DXCCTable.shared.match(prefix: raw) else { return raw.uppercased() }
                    return m.label
                default:
                    return nil
                }
            case .received, nil:
                return nil
            }
        case .cqZone, .ituZone:
            guard let element = r.element, let raw = rcvd[element] else { return nil }
            return (r.kind == .cqZone ? TokenSet.cqZones : TokenSet.ituZones).canonical(raw)
        case .wpxPrefix:
            return WPXPrefix.of(call)
        case .grid:
            guard let element = r.element, let raw = rcvd[element] else { return nil }
            let grid = raw.uppercased()
            return r.precision.map { String(grid.prefix($0)) } ?? grid
        case .workedStation:
            // FOBB: the worked call is the multiplier when the received member
            // element parses as a member number; a power or a blank is not a
            // member. The empty-call guard keeps a locations-only caller (the
            // band map) from minting a valueless key.
            guard !call.isEmpty, let element = r.element, let raw = rcvd[element],
                  case .member = MemberExchange.parse(raw) else { return nil }
            return call.uppercased()
        }
    }

    /// The entity of the worked callsign as a multiplier value: its primary
    /// prefix (`DL` for every German call) where the class tells entities
    /// apart, else the literal `DX`; nil for a call no list resolves or an
    /// excluded entity. `arrl` reads the ARRL roster (`DXCCTable`);
    /// `arrlPlusWAE` reads cty (`CTYTable`), whose WAE-only records count as
    /// their own multipliers (CQ WW).
    static func entityValue(callsign call: String, resolver r: Resolver) -> String? {
        switch r.list ?? .arrl {
        case .arrl:
            guard let m = DXCCTable.shared.match(callsign: call) else { return nil }
            if let code = Int(m.entity.code), r.exclude.contains(code) { return nil }
            return r.countEntities ? m.label : MultClass.dxToken
        case .arrlPlusWAE:
            guard let m = CTYTable.shared?.match(callsign: call) else { return nil }
            if let code = m.entity.entityCode, r.exclude.contains(code), !m.entity.waeOnly { return nil }
            return r.countEntities ? m.entity.primaryPrefix : MultClass.dxToken
        }
    }

    // MARK: Factors and bonuses

    /// power × station × entry class × (1 + Σ selected objectives), exact.
    static func categoryFactor(contest: ContestDefinition, log: ContestLog) -> ScoreFactor {
        guard let f = contest.scoreFactors else { return .one }
        var factor = (f.power?[log.station.categoryPower.rawValue] ?? .one)
            * (f.station?[log.station.categoryStation.rawValue] ?? .one)
        // The match, or the **first** listed class where the id is empty or
        // stale — parties list classes lowest-factor first, and a log that
        // never chose must not claim a multiplier the operator did not.
        if let cls = f.entryClasses.first(where: { $0.id == log.entryClassID }) ?? f.entryClasses.first {
            factor = factor * cls.factor
        }
        let om = f.objectives.filter { log.selectedObjectives.contains($0.id) }.reduce(0) { $0 + $1.om }
        if om > 0 { factor = factor * ScoreFactor(1 + om) }
        return factor
    }

    /// Field Day's checklist: `points × min(count, max)` per claimed bonus,
    /// added after the multiplier and never scaled.
    static func declaredBonusPoints(contest: ContestDefinition, log: ContestLog) -> Int {
        (contest.scoreFactors?.declaredBonuses ?? []).reduce(0) { total, bonus in
            let count = log.declaredBonuses[bonus.id] ?? 0
            guard count > 0 else { return total }
            return total + (bonus.perCount.map { bonus.points * min(count, $0.max) } ?? bonus.points)
        }
    }

    /// The party bonus rules on the model. The county-keyed cases read the
    /// `location` element and the `county` class's roster (spec §1.2).
    static func bonusPoints(valid: [QSO], log: ContestLog, contest: ContestDefinition, breakdown: ScoreBreakdown) -> Int {
        let counties = contest.countyRoster()?.abbrs ?? []
        func isCounty(_ token: String) -> Bool { counties.contains(token.uppercased()) }
        var total = 0
        for bonus in contest.bonuses {
            switch bonus {
            case .workStation(let call, let points, let scope):
                let matches = valid.filter { $0.call.uppercased() == call.uppercased() }
                guard !matches.isEmpty else { break }
                switch scope {
                case .once: total += points
                case .perMode: total += Set(matches.map(\.modeClass)).count * points
                case .perBandMode: total += Set(matches.map { "\($0.band.rawValue)/\($0.modeClass.rawValue)" }).count * points
                case .perQSO: total += matches.count * points
                }
            case .mobileCountyCount(let per, let points):
                // One contact per county per station; every `per` distinct
                // counties a (mobile) station is worked in earns the bonus.
                var countiesByCall: [String: Set<String>] = [:]
                for row in valid where isCounty(row.theirLoc) {
                    countiesByCall[row.call.uppercased(), default: []].insert(row.theirLoc.uppercased())
                }
                for (_, worked) in countiesByCall { total += (worked.count / per) * points }
            case .activatedCountyCount(let minQSOs, let points):
                // My own activation bonus: mobile/rover/portable earning per
                // county operated from with ≥ minQSOs valid QSOs made from it.
                // Only a county-valued sent location qualifies, so an entrant
                // sending a state earns nothing here.
                guard isRovingCategory(log.station.categoryStation) else { break }
                for (county, rows) in Dictionary(grouping: valid, by: { $0.myLoc.uppercased() })
                where isCounty(county) && rows.count >= minQSOs {
                    total += points
                }
            case .sweepTiers(let tiers):
                let worked = breakdown.workedValues(classID: MultClass.county.rawValue).count
                if let best = tiers.filter({ worked >= $0.count }).max(by: { $0.count < $1.count }) { total += best.points }
            case .designatedCountySweep(let designated, let need, let points):
                // "If at least one QSO is made with a station in five of the
                // 'Rarest of NC' counties, 500 additional bonus points" — once,
                // at the threshold or past it.
                if designatedCounties(designated, workedIn: valid).count >= need { total += points }
            case .callAreaSum(let target, let points):
                // Skeeter Hunt Blackjack: each DISTINCT worked callsign
                // contributes its call-area digit once, 0 counts as 10, and
                // the bonus pays once when any subset lands on the target.
                let values = Set(valid.map { $0.call.uppercased() }).compactMap(callAreaValue)
                if subsetSumsExactly(values, target: target) { total += points }
            }
        }
        return total
    }

    // MARK: Activated multipliers

    /// The multiplier a side gives an entrant for each roster token they
    /// **operate from** (`SideRules.activated`) — five parties, no two alike.
    static func addActivatedMultipliers(to result: inout ScoreBreakdown, valid: [QSO], log: ContestLog,
                                        contest: ContestDefinition, side: String) {
        guard let act = contest.rules(for: side).activated,
              act.categories.contains(log.station.categoryStation),
              let cls = contest.multipliers.first(where: { $0.id == act.classID }),
              cls.counting[side] != nil,
              let rosterID = cls.roster, let roster = contest.tokenSet(id: rosterID)
        else { return }
        // The sent element the class reads — a party's `location`.
        let element = cls.resolvers.first { $0.kind == .receivedToken }?.element ?? ExchangeElementID.location
        for (token, rows) in Dictionary(grouping: valid, by: { ($0.sent[element] ?? "").uppercased() })
        where roster.abbrs.contains(token) {
            // The threshold reads all of that token's valid rows, not one
            // scope's worth: every sponsor words it that way ("50 or more
            // valid contacts from a county").
            let count = switch act.countUnit {
            case .qsos: rows.count
            case .stations: Set(rows.map { $0.call.uppercased() }).count
            }
            guard count >= act.minCount else { continue }
            // "…if they do not earn a multiplier for that county otherwise"
            // (TnQP) / "if not otherwise worked" (VAQP) — checked at **any**
            // scope, which set semantics alone cannot handle.
            if act.notOtherwiseWorked, worked(classID: cls.id, value: token, in: result) { continue }
            // One key per scope component present among that token's own rows,
            // which collapses to a single key under `once` and gives SCQP the
            // "ONCE PER MODE PER BAND" it asks for.
            for scope in Set(rows.map { act.countScope.component(band: $0.band, modeClass: $0.modeClass) }) {
                let key = MultKey(classID: cls.id, value: token, scope: scope, activated: true)
                if result.multiplierKeys.insert(key).inserted { result.selfActivatedCounties.insert(token) }
            }
        }
    }

    /// Was this value earned by working somebody, at any scope?
    static func worked(classID: String, value: String, in result: ScoreBreakdown) -> Bool {
        result.multiplierKeys.contains { !$0.activated && $0.classID == classID && $0.value == value }
    }
}
