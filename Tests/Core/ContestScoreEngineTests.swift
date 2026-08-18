// Tests/Core/ContestScoreEngineTests.swift
import XCTest
@testable import QSOPartyLogger

/// The engine on `ContestDefinition`. The lowered parties are checked against
/// the old engine over a corpus in `EngineEquivalenceTests`; here the model's
/// own semantics are pinned: sides and pairing, token ownership and the
/// callsign override, resolvers, points context, caps, granted, factors,
/// bonuses, activated multipliers, operating time.
final class ContestScoreEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_795_824_000)   // 2026-11-28 00:00:00Z
    var seq = 0

    override func setUp() { seq = 0 }

    // MARK: Builders

    func cqww() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    func lowered(_ id: String) throws -> ContestDefinition {
        try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: id)))
    }

    /// One row; every call advances the clock a minute (or `minutes`).
    func row(_ call: String, band: Band = .m20, mode: ModeClass = .cw, raw: String? = nil,
             rcvd: [String: String] = ["rst": "599"], sent: [String: String] = ["rst": "599"], minutes: Int? = nil) -> QSO {
        seq += minutes ?? 1
        return QSO(timestampUTC: t0.addingTimeInterval(Double(seq) * 60), call: call, band: band, modeClass: mode,
                   rawMode: raw ?? (mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY"), sent: sent, rcvd: rcvd)
    }

    func log(_ contest: ContestDefinition, call: String = "KE5CW", side: String = "all",
             sent: [String: [String]] = ["rst": ["599"]], rows: [QSO],
             configure: (inout ContestLog) -> Void = { _ in }) -> ContestLog {
        var log = ContestLog(partyID: contest.id)
        log.station.callsign = call
        log.sideID = side
        log.sentExchange = sent
        log.qsos = rows
        configure(&log)
        return log
    }

    /// A small contest for one rule at a time.
    func contest(sides: [Side] = [Side(id: "all", label: "Everyone", predicate: .always, workedPredicate: .always)],
                 exchange: [ExchangeElement] = [ExchangeElement(id: "rst", kind: .rst, sentBy: ["all": .init()])],
                 multipliers: [MultiplierClass] = [], points: [PointRule] = [PointRule(points: 1)],
                 dupe: DupeRule = DupeRule(scope: .band), pairing: [String: [String]]? = nil,
                 sideRules: [String: SideRules] = [:], bonuses: [BonusRule] = [], scoreFactors: ScoreFactors? = nil,
                 operatingTime: OperatingTimeRule? = nil, modeClasses: [ModeClass] = [.cw],
                 allowedRawModes: [String]? = nil, tokenSets: [TokenSet] = []) throws -> ContestDefinition {
        let c = ContestDefinition(
            id: "t", name: "T", family: .dx, bands: [.m20, .m40], modeClasses: modeClasses, allowedRawModes: allowedRawModes,
            tokenSets: tokenSets, sides: sides, exchange: exchange, multipliers: multipliers, points: points, dupe: dupe,
            pairing: pairing, sideRules: sideRules, bonuses: bonuses, scoreFactors: scoreFactors, operatingTime: operatingTime,
            cabrillo: CabrilloSpec(contest: "T", location: .state))
        try c.validate()
        return c
    }

    func keys(_ s: ScoreEngine.ScoreBreakdown, _ classID: String) -> Set<String> {
        Set(s.multiplierKeys.filter { $0.classID == classID }.map { "\($0.value)|\($0.scope)" })
    }

    // MARK: CQ WW (the fixture): points by relation, zone and country per band, /MM

    func testCQWWPointsFollowTheSponsorsFourCases() throws {
        let c = try cqww()
        // A US entrant: same country 0 (still a multiplier), another NA country 2, another continent 3.
        let us = ScoreEngine.score(log: log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("W1AW", rcvd: ["rst": "599", "zone": "5"]),
            row("VE3ABC", rcvd: ["rst": "599", "zone": "4"]),
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("PY1AA", band: .m40, rcvd: ["rst": "599", "zone": "11"]),
        ]), contest: c)
        XCTAssertEqual(us.validQSOs, 4)
        XCTAssertEqual(us.qsoPoints, 0 + 2 + 3 + 3)
        XCTAssertEqual(keys(us, "zone"), ["5|20m", "4|20m", "14|20m", "11|40m"])
        XCTAssertEqual(keys(us, "country"), ["K|20m", "VE|20m", "DL|20m", "PY|40m"], "the primary prefix names the country")
        XCTAssertEqual(us.multiplierCount, 8)
        XCTAssertEqual(us.total, 8 * 8)
        // A German entrant: same continent 1.
        let de = ScoreEngine.score(log: log(c, call: "DL1QPL", sent: ["rst": ["599"], "zone": ["14"]], rows: [
            row("DL2AA", rcvd: ["rst": "599", "zone": "14"]),
            row("F5ABC", rcvd: ["rst": "599", "zone": "14"]),
            row("W1AW", rcvd: ["rst": "599", "zone": "5"]),
        ]), contest: c)
        XCTAssertEqual(de.qsoPoints, 0 + 1 + 3)
        XCTAssertEqual(de.pointsByRowID.values.sorted(), [0, 1, 3])
    }

    func testMaritimeMobileCountsForAZoneOnly() throws {
        let c = try cqww()
        let s = ScoreEngine.score(log: log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("DL1AA/MM", rcvd: ["rst": "599", "zone": "33"]),
        ]), contest: c)
        XCTAssertEqual(keys(s, "zone"), ["33|20m"])
        XCTAssertEqual(keys(s, "country"), [], "unlessSuffix MM: no country for a maritime mobile")
        XCTAssertEqual(s.qsoPoints, 3)
    }

    func testDupesOncePerBandAndZoneLeadingZeroFolds() throws {
        let c = try cqww()
        let s = ScoreEngine.score(log: log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("DL1AA", band: .m40, rcvd: ["rst": "599", "zone": "014"]),
        ]), contest: c)
        XCTAssertEqual(s.validQSOs, 2); XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(keys(s, "zone"), ["14|20m", "14|40m"])
    }

    // MARK: Operating time

    func testRowsPastTheOperatingLimitAreLoggedButNotScored() throws {
        let c = try contest(operatingTime: OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30))
        let rows = [row("W1AW", minutes: 0), row("W2AA", minutes: 20), row("W3AA", minutes: 20), row("W4AA", minutes: 20),
                    row("W5AA", minutes: 1), row("W5AA", band: .m40, minutes: 1)]
        let s = ScoreEngine.score(log: log(c, rows: rows), contest: c)
        XCTAssertEqual(s.validQSOs, 4, "0, 20, 40, 60 minutes are within the hour")
        XCTAssertEqual(s.outOfTimeRowIDs, Set(rows.suffix(2).map(\.id)))
        XCTAssertEqual(s.outOfTimeCount, 2)
        XCTAssertEqual(s.dupeCount, 0, "an out-of-time row is not a dupe either — it is out of time")
        XCTAssertNil(s.pointsByRowID[rows[4].id])
        XCTAssertEqual(s.operatedMinutes, 60)
        // A 49-minute gap is off time (≥ 30): the clock does not run through it.
        let spaced = [row("W1AW", minutes: 0), row("W2AA", minutes: 50), row("W3AA", minutes: 50)]
        let sp = ScoreEngine.score(log: log(c, rows: spaced), contest: c)
        XCTAssertEqual(sp.validQSOs, 3); XCTAssertEqual(sp.offMinutes, 98); XCTAssertEqual(sp.operatedMinutes, 0)
        // A rule that applies to a category this log is not in does nothing.
        let classic = try contest(operatingTime: OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30, appliesTo: ["overlay": "CLASSIC"]))
        XCTAssertEqual(ScoreEngine.score(log: log(classic, rows: rows), contest: classic).validQSOs, 6)
    }

    // MARK: Modes, pairing, sides

    func testRawModesRefineAClass() throws {
        let c = try contest(modeClasses: [.digital], allowedRawModes: ["RTTY"])
        let s = ScoreEngine.score(log: log(c, rows: [row("W1AW", mode: .digital, raw: "RTTY"), row("W2AA", mode: .digital, raw: "FT8")]), contest: c)
        XCTAssertEqual(s.validQSOs, 1); XCTAssertEqual(s.invalidModeCount, 1)
    }

    func testPairingByCallsignSides() throws {
        // ARRL DX shape: W/VE (USA 291, Canada 1) work DX and vice versa.
        let wve = Side(id: "wve", label: "W/VE", predicate: SidePredicate(kind: .dxccIn, codes: [291, 1]),
                       workedPredicate: SidePredicate(kind: .dxccIn, codes: [291, 1]))
        let dx = Side(id: "dx", label: "DX", predicate: .always, workedPredicate: .always)
        let c = try contest(sides: [wve, dx],
                            exchange: [ExchangeElement(id: "rst", kind: .rst, sentBy: ["wve": .init(), "dx": .init()])],
                            points: [PointRule(points: 3)], pairing: ["wve": ["dx"], "dx": ["wve"]])
        let s = ScoreEngine.score(log: log(c, side: "wve", rows: [row("W1AW"), row("VE3ABC"), row("DL1AA"), row("KH6ABC")]), contest: c)
        XCTAssertEqual(s.validQSOs, 2, "DL and KH6 (Hawaii, its own entity) are DX; W1AW and VE3 are out of scope")
        XCTAssertEqual(s.outOfScopeCount, 2)
        XCTAssertEqual(s.qsoPoints, 6)
    }

    func testAnUndeclaredSideResolvesToTheOnlySide() throws {
        // A legacy NAQP log says `outside`; the lowered party has one side, `all`.
        let c = try lowered("naqpcw")
        var legacy = ContestLog(partyID: c.id, myLocation: .outOfState(location: "TX"), exchangeName: "TOM")
        legacy.station.callsign = "KE5CW"
        legacy.qsos = [QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "", rstRcvd: "",
                           nameSent: "TOM", nameRcvd: "BOB", myLoc: "TX", theirLoc: "CA")]
        XCTAssertEqual(legacy.sideID, "outside")
        var v2 = legacy; v2.sideID = "all"
        XCTAssertEqual(ScoreEngine.score(log: legacy, contest: c), ScoreEngine.score(log: v2, contest: c))
        XCTAssertEqual(ScoreEngine.score(log: legacy, contest: c).validQSOs, 1)
    }

    // MARK: Token ownership and the callsign override (the parties, through the model)

    func testTheCallsignDecidesAPrefixThatEqualsAStateCode() throws {
        let wa = try lowered("warun"), c = try XCTUnwrap(PartyCatalog.party(id: "warun")).counties[0].abbr
        func inLog(_ rows: [(String, String)]) -> ContestLog {
            var log = ContestLog(partyID: wa.id, myLocation: .inState(counties: [c]))
            log.station.callsign = "W7QPL"
            log.qsos = rows.map { call, their in
                seq += 1
                return QSO(timestampUTC: t0.addingTimeInterval(Double(seq) * 60), call: call, band: .m40, modeClass: .cw, rawMode: "CW",
                           rstSent: "599", rstRcvd: "599", myLoc: c, theirLoc: their)
            }
            return log
        }
        let dx = ScoreEngine.score(log: inLog([("PA0AAA", "PA"), ("OK1BBB", "OK"), ("LA1CCC", "LA"), ("ON4DDD", "ON"), ("DL1EEE", "DL")]), contest: wa)
        XCTAssertEqual(dx.workedValues(classID: "state"), [])
        XCTAssertEqual(dx.workedValues(classID: "province"), [])
        XCTAssertEqual(dx.workedValues(classID: "dx"), ["PA", "OK", "LA", "ON", "DL"])
        let home = ScoreEngine.score(log: inLog([("W3XYZ", "PA"), ("W5ABC", "OK"), ("W5DEF", "LA"), ("VE3GHI", "ON")]), contest: wa)
        XCTAssertEqual(home.workedValues(classID: "state"), ["PA", "OK", "LA"])
        XCTAssertEqual(home.workedValues(classID: "province"), ["ON"])
        XCTAssertEqual(home.workedValues(classID: "dx"), [])
        // The tie breaks only when the callsign names the very entity the token would.
        let near = ScoreEngine.score(log: inLog([("VE5ABC", "SK"), ("VE6DEF", "AB")]), contest: wa)
        XCTAssertEqual(near.workedValues(classID: "province"), ["SK", "AB"])
        XCTAssertEqual(near.workedValues(classID: "dx"), [])
        // A county is owned by the counties set whatever the callsign; the excluded home state credits nothing.
        let county = ScoreEngine.score(log: inLog([("PA0AAA", c), ("W7ABC", "WA")]), contest: wa)
        XCTAssertEqual(county.workedValues(classID: "county"), [c])
        XCTAssertEqual(county.workedValues(classID: "state"), [])
        XCTAssertEqual(county.multiplierCount, 1)
    }

    func testOneTokenOneClassAndAliasesFoldAtCountTime() throws {
        // ALQP: DC is credited as MD; a county credits county and (via group) the home state; a section party takes DX as a literal.
        let al = try lowered("alqp"), alCounties = try XCTUnwrap(PartyCatalog.party(id: "alqp")).counties.map(\.abbr)
        var log = ContestLog(partyID: al.id, myLocation: .inState(counties: [alCounties[0]]))
        log.station.callsign = "W4QPL"
        log.qsos = [row("W3DC", rcvd: ["rst": "599", "location": "DC"], sent: ["rst": "599", "location": alCounties[0]]),
                    row("W4AA", rcvd: ["rst": "599", "location": alCounties[1]], sent: ["rst": "599", "location": alCounties[0]])]
        let s = ScoreEngine.score(log: log, contest: al)
        XCTAssertEqual(s.workedValues(classID: "state"), ["MD", "AL"], "DC folds to MD; the county's group is AL")
        XCTAssertEqual(s.workedValues(classID: "county"), [alCounties[1]])
        let pa = try lowered("paqp"), paCounties = try XCTUnwrap(PartyCatalog.party(id: "paqp")).counties.map(\.abbr)
        var plog = ContestLog(partyID: pa.id, myLocation: .inState(counties: [paCounties[0]]))
        plog.station.callsign = "W3QPL"
        plog.qsos = [row("DL1AA", rcvd: ["serial": "1", "location": "DX"], sent: ["serial": "1", "location": paCounties[0]]),
                     row("K5TR", rcvd: ["serial": "2", "location": "TX"], sent: ["serial": "2", "location": paCounties[0]]),
                     row("W5ABC", rcvd: ["serial": "3", "location": "NTX"], sent: ["serial": "3", "location": paCounties[0]])]
        let ps = ScoreEngine.score(log: plog, contest: pa)
        XCTAssertEqual(ps.workedValues(classID: "dx"), ["DX"])
        XCTAssertEqual(ps.workedValues(classID: "section"), ["NTX", "EPA", "WPA"], "the granted sections ride along")
        XCTAssertEqual(ps.multiplierKeys.filter { $0.value == "EPA" }.first?.scope, "", "granted: once, unscoped")
        XCTAssertEqual(ps.validQSOs, 3, "TX is a valid QSO worth points and no multiplier in a section party")
    }

    // MARK: Caps, floors, member kinds, factors, declared bonuses

    func testDistinctValueCapAndFloor() throws {
        let wa = try lowered("warun"), c = try XCTUnwrap(PartyCatalog.party(id: "warun")).counties[0].abbr
        var log = ContestLog(partyID: wa.id, myLocation: .inState(counties: [c]))
        log.station.callsign = "W7QPL"
        let prefixes = ["DL", "G", "JA", "F", "I", "EA", "SM", "OZ", "HB", "LZ", "YU", "SP"]
        log.qsos = prefixes.enumerated().map { i, p in row("X\(i)", rcvd: ["rst": "599", "location": p], sent: ["rst": "599", "location": c]) }
        let s = ScoreEngine.score(log: log, contest: wa)
        XCTAssertEqual(s.validQSOs, 12)
        XCTAssertEqual(s.workedValues(classID: "dx").count, 10, "caps.inside = 10 distinct entities")
        let fobb = try lowered("fobb")
        var f = ContestLog(partyID: fobb.id, myLocation: .outOfState(location: "TX"), exchangeMember: "5W")
        f.station.callsign = "KE5CW"
        f.qsos = [row("W1AW", rcvd: ["rst": "599", "location": "CT", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "5W"])]
        let fs = ScoreEngine.score(log: f, contest: fobb)
        XCTAssertEqual(fs.multiplierFloor, 1); XCTAssertEqual(fs.multiplierCount, 1); XCTAssertEqual(fs.total, fs.qsoPoints)
    }

    func testMemberKindsDecidePointsAndCounts() throws {
        let sk = try lowered("skeeter"), p = try XCTUnwrap(PartyCatalog.party(id: "skeeter")), m = try XCTUnwrap(p.memberExchange)
        var log = ContestLog(partyID: sk.id, myLocation: .outOfState(location: "TX"), exchangeMember: "13")
        log.station.callsign = "KE5CW"
        log.qsos = [row("W2LJ", rcvd: ["rst": "599", "location": "NJ", "member": "1"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                    row("K3WWP", rcvd: ["rst": "599", "location": "PA", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                    row("VE3ABC", rcvd: ["rst": "599", "location": "ON"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                    row("K1ABC", mode: .phone, rcvd: ["rst": "59", "location": "CT", "member": "8W"], sent: ["rst": "59", "location": "TX", "member": "13"])]
        let s = ScoreEngine.score(log: log, contest: sk)
        XCTAssertEqual(s.memberQSOs, 1)
        XCTAssertEqual(s.qrpQSOs, 2, "8 W on phone is QRP (10 W ceiling)")
        XCTAssertEqual(s.otherQSOs, 1, "a blank element is QRO")
        XCTAssertEqual(s.qsoPoints, m.memberPoints + 2 * m.qrpPoints + m.otherPoints)
    }

    func testFactorsObjectivesEntryClassAndDeclaredBonuses() throws {
        let f = ScoreFactors(power: ["QRP": ScoreFactor(2)], station: ["PORTABLE": ScoreFactor(3)],
                             entryClasses: [.init(id: "X1", label: "One", factor: .one), .init(id: "X2", label: "Two", factor: ScoreFactor(2))],
                             objectives: [.init(id: "1o", label: "a", om: 1), .init(id: "2o", label: "b", om: 2)],
                             declaredBonuses: [.init(id: "emergency", label: "Emergency power", points: 100, perCount: .init(label: "transmitters", max: 20)),
                                               .init(id: "media", label: "Media publicity", points: 100, perCount: nil)])
        let c = try contest(scoreFactors: f)
        let s = ScoreEngine.score(log: log(c, rows: [row("W1AW")]) { log in
            log.station.categoryPower = .qrp; log.station.categoryStation = .portable
            log.entryClassID = "X2"; log.selectedObjectives = ["1o", "2o", "nope"]
            log.declaredBonuses = ["emergency": 25, "media": 1, "unknown": 4]
        }, contest: c)
        XCTAssertEqual(s.categoryFactor, ScoreFactor(2 * 3 * 2 * (1 + 3)))
        XCTAssertEqual(s.bonusPoints, 100 * 20 + 100)
        XCTAssertEqual(s.total, s.categoryFactor.applied(to: s.qsoPoints * s.multiplierCount) + s.bonusPoints)
        let none = ScoreEngine.score(log: log(c, rows: [row("W1AW")]), contest: c)
        XCTAssertEqual(none.categoryFactor, .one, "a log that never chose takes the first (lowest) class")
    }

    // MARK: Bonuses and activated multipliers through the lowered parties

    func testActivatedMultiplierIsForfeitedWhereTheCountyIsAlsoWorked() throws {
        let tn = try lowered("tnqp"), p = try XCTUnwrap(PartyCatalog.party(id: "tnqp"))
        let act = try XCTUnwrap(p.multipliers.inState.activatedCountyMultiplier), c = p.counties.map(\.abbr)
        func mobile(_ rows: [QSO]) -> ContestLog {
            var log = ContestLog(partyID: tn.id, myLocation: .inState(counties: [c[0]]))
            log.station.callsign = "W4QPL"; log.station.categoryStation = .mobile
            log.qsos = rows
            return log
        }
        let enough = (0..<act.minCount).map { i in row("W\(i)AA", rcvd: ["rst": "599", "location": "TX"], sent: ["rst": "599", "location": c[0]]) }
        let s = ScoreEngine.score(log: mobile(enough), contest: tn)
        XCTAssertEqual(s.selfActivatedCounties, [c[0]])
        XCTAssertTrue(s.multiplierKeys.contains(ScoreEngine.MultKey(classID: "county", value: c[0], scope: "", activated: true)))
        let worked = ScoreEngine.score(log: mobile(enough + [row("W4XYZ", rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": c[0]])]), contest: tn)
        XCTAssertEqual(worked.selfActivatedCounties, [], "TnQP: not if the county is earned otherwise")
        XCTAssertEqual(ScoreEngine.score(log: mobile(Array(enough.dropLast())), contest: tn).selfActivatedCounties, [], "one short of the threshold")
    }

    func testWorkStationAndSweepBonuses() throws {
        let vt = try lowered("vtqp"), c = try XCTUnwrap(PartyCatalog.party(id: "vtqp")).counties.map(\.abbr)
        var log = ContestLog(partyID: vt.id, myLocation: .outOfState(location: "TX"))
        log.station.callsign = "KE5CW"
        log.qsos = [row("W1AW/1", rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": "TX"]),
                    row("W1AW/1", band: .m40, rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": "TX"])]
        XCTAssertEqual(ScoreEngine.score(log: log, contest: vt).bonusPoints, 4, "2 per QSO")
        let md = try lowered("mdc"), mdp = try XCTUnwrap(PartyCatalog.party(id: "mdc")), mc = mdp.counties.map(\.abbr)
        guard case .sweepTiers(let tiers)? = mdp.bonuses.first(where: { if case .sweepTiers = $0 { return true } else { return false } }),
              let lowest = tiers.min(by: { $0.count < $1.count }) else { return XCTFail("MDC has sweep tiers") }
        var mlog = ContestLog(partyID: md.id, myLocation: .outOfState(location: "TX"))
        mlog.station.callsign = "KE5CW"
        mlog.qsos = (0..<lowest.count).map { i in row("W3X\(i)", rcvd: ["rst": "599", "location": mc[i]], sent: ["rst": "599", "location": "TX"]) }
        XCTAssertEqual(ScoreEngine.score(log: mlog, contest: md).bonusPoints, lowest.points)
    }

    /// The `tokenIn` worked predicate is what replaces the old engine's
    /// county filter for the 45 parties whose outside entrant may work home
    /// stations only — the commonest log shape in the catalogue.
    func testAnOutsideEntrantWorksHomeStationsOnly() throws {
        let wa = try lowered("warun"), p = try XCTUnwrap(PartyCatalog.party(id: "warun"))
        XCTAssertTrue(p.outStateWorksHomeStationsOnly)
        let c = p.counties.map(\.abbr)
        var log = ContestLog(partyID: wa.id, myLocation: .outOfState(location: "TX"))
        log.station.callsign = "KE5CW"
        log.qsos = [row("W7ABC", rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": "TX"]),
                    row("W8DEF", rcvd: ["rst": "599", "location": "OH"], sent: ["rst": "599", "location": "TX"]),
                    row("VE3GHI", rcvd: ["rst": "599", "location": "ON"], sent: ["rst": "599", "location": "TX"])]
        let s = ScoreEngine.score(log: log, contest: wa)
        XCTAssertEqual(s.validQSOs, 1, "only the Washington county row is in scope")
        XCTAssertEqual(s.outOfScopeCount, 2)
        XCTAssertEqual(s.workedValues(classID: "county"), [c[0]])
        XCTAssertEqual(s.qsoPoints, ScoreEngine.score(log: log, party: p).qsoPoints, "same as the engine that ships today")
    }

    // MARK: Derived queries

    func testWouldAddMultiplierOnTheModel() throws {
        let c = try cqww()
        let held = log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [row("DL1AA", rcvd: ["rst": "599", "zone": "14"])])
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "DL2BB", band: .m20, modeClass: .cw, log: held, contest: c),
                       "zone 14 and DL are both held on 20 m")
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "DL2BB", band: .m40, modeClass: .cw, log: held, contest: c),
                      "per band: 40 m is new")
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "F5ABC", band: .m20, modeClass: .cw, log: held, contest: c),
                      "a new country on a held zone")
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "F5ABC", band: .m20, modeClass: .phone, log: held, contest: c),
                       "a mode the contest does not run")
        // A county line: any of the received values may be the new one.
        let ks = try lowered("ksqp"), kc = try XCTUnwrap(PartyCatalog.party(id: "ksqp")).counties.map(\.abbr)
        var klog = ContestLog(partyID: ks.id, myLocation: .outOfState(location: "TX"))
        klog.station.callsign = "KE5CW"
        klog.qsos = [row("W0BH", rcvd: ["rst": "599", "location": kc[0]], sent: ["rst": "599", "location": "TX"])]
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["location": kc[0]], ["location": kc[1]]], call: "N0XYZ", band: .m20, modeClass: .cw, log: klog, contest: ks))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["location": kc[0]]], call: "N0XYZ", band: .m20, modeClass: .cw, log: klog, contest: ks))
        // Past CQP's scored ceiling nothing pays.
        let cq = try lowered("cqp"), cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let cap = try XCTUnwrap(cqp.multipliers.inState.maxScoredMultipliers)
        var clog = ContestLog(partyID: cq.id, myLocation: .inState(counties: [cqp.counties[0].abbr]))
        clog.station.callsign = "W6QPL"
        let tokens = MultClass.acceptedStateTokens.subtracting(cqp.excludedStateTokens).subtracting(cqp.stateAliases.keys).sorted()
            + cqp.provinces.sorted()                                   // 49 states + DC-less list + 13 provinces > 58
        clog.qsos = tokens.prefix(cap).enumerated().map { i, s in
            row("W\(i % 10)A\(i)", rcvd: ["serial": "\(i + 1)", "location": s], sent: ["serial": "\(i + 1)", "location": cqp.counties[0].abbr])
        }
        XCTAssertGreaterThanOrEqual(ScoreEngine.score(log: clog, contest: cq).multiplierKeys.count, cap)
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["location": "ON"]], call: "VE3ABC", band: .m20, modeClass: .cw, log: clog, contest: cq))
    }

    func testWouldAddMultiplierRespectsAForfeitedActivation() throws {
        let tn = try lowered("tnqp"), p = try XCTUnwrap(PartyCatalog.party(id: "tnqp"))
        let act = try XCTUnwrap(p.multipliers.inState.activatedCountyMultiplier), c = p.counties.map(\.abbr)
        var log = ContestLog(partyID: tn.id, myLocation: .inState(counties: [c[0]]))
        log.station.callsign = "W4QPL"; log.station.categoryStation = .mobile
        log.qsos = (0..<act.minCount).map { i in row("W\(i)AA", rcvd: ["rst": "599", "location": "TX"], sent: ["rst": "599", "location": c[0]]) }
        XCTAssertEqual(ScoreEngine.score(log: log, contest: tn).selfActivatedCounties, [c[0]])
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["location": c[0]]], call: "W4XYZ", band: .m20, modeClass: .cw, log: log, contest: tn),
                       "working the activated county trades one key for another")
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["location": c[1]]], call: "W4XYZ", band: .m20, modeClass: .cw, log: log, contest: tn))
    }

    func testBandModeCountsDesignatedCountiesAndCallAreaSum() throws {
        let c = try cqww()
        let l = log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]), row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("F5ABC", band: .m40, rcvd: ["rst": "599", "zone": "14"]), row("G3XYZ", mode: .phone, rcvd: ["rst": "59", "zone": "14"]),
        ])
        XCTAssertEqual(ScoreEngine.bandModeCounts(log: l, contest: c), [.m20: [.cw: 1], .m40: [.cw: 1]], "the dupe and the phone row do not count")
        let nc = try lowered("ncqp"), ncp = try XCTUnwrap(PartyCatalog.party(id: "ncqp"))
        guard case .designatedCountySweep(let designated, _, _)? = ncp.bonuses.first(where: { if case .designatedCountySweep = $0 { return true } else { return false } })
        else { return XCTFail("NCQP has a designated sweep") }
        var nlog = ContestLog(partyID: nc.id, myLocation: .outOfState(location: "TX"))
        nlog.station.callsign = "KE5CW"
        nlog.qsos = [row("W4AA", rcvd: ["rst": "599", "location": designated[0]], sent: ["rst": "599", "location": "TX"]),
                     row("W4BB", rcvd: ["rst": "599", "location": designated[1]], sent: ["rst": "599", "location": "TX"])]
        XCTAssertEqual(ScoreEngine.designatedCountiesWorked(designated, log: nlog, contest: nc), Set(designated.prefix(2).map { $0.uppercased() }))
        let sk = try lowered("skeeter")
        var slog = ContestLog(partyID: sk.id, myLocation: .outOfState(location: "TX"), exchangeMember: "13")
        slog.station.callsign = "KE5CW"
        slog.qsos = [row("W1AA", rcvd: ["rst": "599", "location": "CT", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                     row("K0BB", rcvd: ["rst": "599", "location": "CO", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "13"])]
        XCTAssertTrue(ScoreEngine.callAreaSumAchieved(target: 11, log: slog, contest: sk), "1 + 10")
        XCTAssertFalse(ScoreEngine.callAreaSumAchieved(target: 12, log: slog, contest: sk))
    }

    /// The callsign override is decided over **every** class, gated by each
    /// resolver's own `sides` — not only the classes this side counts. Today's
    /// `dxCountsEntities` gate is independent of the class list, so a side that
    /// tells entities apart without counting them still must not credit
    /// Pennsylvania for `PA` received from `PA0AAA`.
    func testTheCallsignOverrideAppliesEvenWhereTheSideDoesNotCountTheClass() throws {
        let states = TokenSet(id: "states", term: "state", termPlural: "states",
                              tokens: [.init(abbr: "PA"), .init(abbr: "TX")])
        let location = ExchangeElement(id: "location", kind: .token,
                                       sentBy: ["all": .init(sets: ["states", "dxccPrefix"])], fixed: true)
        let stateClass = MultiplierClass(
            id: "state", term: "state",
            resolvers: [Resolver(kind: .receivedToken, element: "location", set: "states")],
            counting: ["all": .once], roster: "states")
        // Nobody counts this class — but its resolver still decides ownership.
        let countryClass = MultiplierClass(
            id: "country", term: "country", termPlural: "countries",
            resolvers: [Resolver(kind: .dxccEntity, element: "location", from: .receivedTokenOrCallsign,
                                 list: .arrl, callsignOverrides: ["states"])],
            counting: [:], layout: .workedOnly)
        let c = try contest(exchange: [location], multipliers: [stateClass, countryClass], tokenSets: [states])

        let dx = ScoreEngine.score(log: log(c, sent: ["location": ["TX"]],
                                            rows: [row("PA0AAA", rcvd: ["location": "PA"])]), contest: c)
        XCTAssertEqual(dx.workedValues(classID: "state"), [],
                       "the callsign moved the token to dxccPrefix, and no side counts the country class")
        XCTAssertEqual(dx.workedValues(classID: "country"), [])
        let home = ScoreEngine.score(log: log(c, sent: ["location": ["TX"]],
                                              rows: [row("W3XYZ", rcvd: ["location": "PA"])]), contest: c)
        XCTAssertEqual(home.workedValues(classID: "state"), ["PA"], "a US callsign never triggers the override")
    }
}
