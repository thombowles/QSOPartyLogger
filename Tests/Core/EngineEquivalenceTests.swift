import XCTest
@testable import QSOPartyLogger

/// SplitMix64: a tiny deterministic generator, so the corpus is the same on
/// every machine and every run.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
}

/// The equivalence corpus: for each party and seed, one log per side, ~60
/// rows drawn from the party's own data plus a fixed pool of callsigns and
/// prefixes. Every id and timestamp is a function of the seed.
enum EquivalenceCorpus {
    static let seeds: [UInt64] = [11, 23, 37]
    static let entrantCall = "KE5CW"
    static let calls = ["W0BH", "K5TR", "N5NA", "VE3ABC", "VE5ABC", "VE6DEF", "PA0AAA", "OK1BBB", "LA1CCC", "ON4DDD",
                        "DL1EEE", "G3XYZ", "JA1AAA", "W3XYZ", "W5ABC", "N0XYZ/M", "KH6ABC", "KL7XYZ", "XE1AAA", "VP9ABC",
                        "F5ABC", "EA3ABC", "SM0ABC", "OZ1ABC", "HB9ABC", "VK2ABC", "ZL1ABC", "AA0AA", "K0AA", "W1AW/1", "W7DX"]
    static let prefixes = ["DL", "G", "JA", "F", "EA", "SM", "OZ", "HB", "VK", "ZL", "PA", "OK", "LA", "ON", "SK", "I", "LZ", "YU", "SP", "XE", "VP9", "KP4", "KH6", "KL7"]
    static let names = ["TOM", "BOB", "MARY-ANN", "O'NEIL", "SUE"]
    static let members = ["13", "5W", "100W", "", "2.5W", "1KW", "027", "500MW"]
    static let stations: [StationProfile.CategoryStation] = [.fixed, .mobile, .rover, .portable, .expedition]
    static let powers: [StationProfile.CategoryPower] = [.low, .high, .qrp]

    static func uuid(_ n: UInt64) -> UUID {
        UUID(uuidString: String(format: "%08llX-0000-4000-8000-%012llX", n >> 32, n & 0xFFFF_FFFF_FFFF))!
    }

    /// Every received token a party can produce, from its own data — **the
    /// domain of its own exchange parser**, plus one plain typo the engines
    /// must both ignore.
    ///
    /// The corpus deliberately stays inside what `ExchangeParser` accepts for
    /// the party, because outside it the two engines genuinely differ and the
    /// difference is not a bug: the old engine credits a **bare DXCC prefix in
    /// a token-style entity-counting party** (`collidesWithDXCC` fires for any
    /// known prefix whose entity matches the worked callsign — MEQP, NHQP,
    /// NMQP, 7QP, TQP, New England) and a **literal `DX` in a prefix-style
    /// party that does not accept the token** (its `theirLoc == "DX"` branch is
    /// unconditional), and the model refuses both because no side sends them.
    /// The party's own home-state token is the same case: LAQP excludes `LA`,
    /// yet the old engine credits Norway for `LA` received from `LA1CCC`. Those
    /// rows cannot be produced by the entry field, `BulkEdit` (which does not
    /// edit `theirLoc`) or any import; a hand-edited `.qplog` could, and the
    /// model's narrowing is the correct reading — the field accepts only what
    /// the sponsor's exchange carries.
    static func receivedPool(_ p: PartyDefinition) -> [String] {
        var pool: [String] = p.counties.map(\.abbr)
        if p.usesSections {
            pool += p.sections.sorted()
        } else {
            pool += MultClass.acceptedStateTokens.subtracting(p.excludedStateTokens).sorted()
            pool += p.stateAliases.keys.sorted()
            pool += p.provinces.sorted()
        }
        if p.acceptsDXToken { pool.append(MultClass.dxToken) }
        if p.dxStyle == .prefix { pool += prefixes }
        pool += p.dxTokenAliases.sorted()
        pool.append("ZZZ")   // a typo: no owner, no credit, in either engine
        return pool
    }

    /// The entrant's own token(s) per side: counties (one or two, a county
    /// line) for `inside`; a state, a province, DX or a prefix for `outside`;
    /// for a party with no home region, whatever the single side may be.
    static func entrantLocations(_ p: PartyDefinition, seed: UInt64) -> [MyLocation] {
        var rng = SplitMix64(state: seed &* 7919)
        let counties = p.counties.map(\.abbr)
        let states = MultClass.acceptedStateTokens.subtracting(p.excludedStateTokens).sorted()
        var out: [MyLocation] = []
        if p.hasHomeRegion {
            let mine = counties.isEmpty ? [] : (rng.chance(50) && counties.count > 1
                ? [rng.pick(counties), rng.pick(counties)].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                : [rng.pick(counties)])
            out.append(.inState(counties: mine))
            let outside = [rng.pick(states), rng.pick(p.provinces.sorted().isEmpty ? states : p.provinces.sorted()),
                           p.acceptsDXToken ? MultClass.dxToken : rng.pick(states),
                           p.dxStyle == .prefix ? "DL" : rng.pick(states)]
            out.append(.outOfState(location: rng.pick(outside)))
        } else {
            let own = (counties + states).isEmpty ? ["TX"] : counties + states
            out.append(.outOfState(location: rng.pick(own)))
        }
        return out
    }

    static func logs(for p: PartyDefinition, seed: UInt64) -> [ContestLog] {
        entrantLocations(p, seed: seed).enumerated().map { index, location in
            log(for: p, seed: seed, location: location, index: index)
        }
    }

    static func log(for p: PartyDefinition, seed: UInt64, location: MyLocation, index: Int) -> ContestLog {
        var rng = SplitMix64(state: seed &* 104_729 &+ UInt64(index) &* 31)
        var log = ContestLog(partyID: p.id, myLocation: location,
                             exchangeName: p.exchangeIncludesName ? "TOM" : "",
                             exchangeMember: p.memberExchange == nil ? "" : rng.pick(["13", "5W"]),
                             entryClassID: p.entryClasses.isEmpty ? "" : rng.pick(p.entryClasses.map(\.id) + [""]))
        log.station.callsign = entrantCall
        log.station.categoryStation = rng.pick(stations)
        log.station.categoryPower = rng.pick(powers)
        log.setupCompleted = true
        if rng.chance(30) { log.myPotaRefs = ["US-3315"] }

        let bonusCalls = p.bonuses.compactMap { bonus -> String? in
            if case .workStation(let call, _, _) = bonus { return call } else { return nil }
        }
        let callPool = calls + bonusCalls + bonusCalls   // bonus calls twice as likely
        let pool = receivedPool(p)
        let counties = p.counties.map(\.abbr)
        let bands = p.validBands.isEmpty ? [Band.m20] : p.validBands
        let modes = p.allowedModeClasses.isEmpty ? [ModeClass.cw] : p.allowedModeClasses
        let base = 1_789_900_000.0 + Double(seed) * 3600 + Double(index) * 90_000
        var clock = 0.0
        var rows: [QSO] = []
        var contacts: [(call: String, band: Band, mode: ModeClass, theirs: [String])] = []
        var n: UInt64 = seed << 20 | UInt64(index) << 16
        var serial = 0
        while rows.count < 60 {
            clock += Double(20 + rng.int(380))
            let call: String, band: Band, mode: ModeClass, theirs: [String]
            if !contacts.isEmpty, rng.chance(15) {
                let again = rng.pick(contacts)                            // a dupe candidate
                call = again.call; band = again.band; mode = again.mode; theirs = again.theirs
            } else {
                call = rng.pick(callPool)
                band = rng.chance(90) ? rng.pick(bands) : rng.pick(Band.allCases)
                mode = rng.chance(88) ? rng.pick(modes) : rng.pick(ModeClass.allCases)
                theirs = rng.chance(10) && counties.count > 1
                    ? [rng.pick(counties), rng.pick(counties)].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    : [rng.pick(pool)]
                contacts.append((call, band, mode, theirs))
            }
            serial += 1
            let raw = mode == .phone ? rng.pick(["SSB", "USB", "LSB", "FM"]) : mode == .cw ? "CW" : rng.pick(["RTTY", "FT8"])
            let rst = mode == .phone ? "59" : "599"
            let name = p.exchangeIncludesName ? rng.pick(names) : nil
            let member = p.memberExchange == nil ? nil : rng.pick(members)
            let theirParks: [String]? = rng.chance(5) ? ["US-0088"] : nil
            let group = uuid(n); n += 1
            let stamp = Date(timeIntervalSince1970: base + clock)
            for mine in location.sentExchanges {
                for their in theirs {
                    rows.append(QSO(
                        id: uuid(n), groupID: group, timestampUTC: stamp, call: call, band: band, modeClass: mode, rawMode: raw,
                        freqKHz: nil, rstSent: rst, rstRcvd: rst,
                        serialSent: p.exchangeIncludesSerial ? serial : nil,
                        serialRcvd: p.exchangeIncludesSerial ? 1 + rng.int(500) : nil,
                        nameSent: p.exchangeIncludesName ? "TOM" : nil, nameRcvd: name,
                        memberSent: p.memberExchange == nil ? nil : log.exchangeMember, memberRcvd: member.flatMap { $0.isEmpty ? nil : $0 },
                        myPotaRefs: log.myPotaRefs.isEmpty ? nil : log.myPotaRefs, theirPotaRefs: theirParks,
                        myLoc: mine, theirLoc: their))
                    n += 1
                }
            }
        }
        log.qsos = rows
        return log
    }
}

/// A `ScoreBreakdown` as a stable, diffable record: row ids become indices
/// into the log, keys become sorted strings.
struct GoldenBreakdown: Codable, Equatable {
    var validQSOs: Int, dupeCount: Int, invalidModeCount: Int, outOfScopeCount: Int, outOfTimeCount: Int
    var qsoPoints: Int, bonusPoints: Int, memberQSOs: Int, qrpQSOs: Int, otherQSOs: Int
    var multiplierCount: Int, multiplierCap: Int?, multiplierFloor: Int, total: Int
    var categoryFactor: ScoreFactor
    var multiplierKeys: [String]
    var dupeRows: [Int], invalidRows: [Int], outOfScopeRows: [Int], newMultRows: [Int]
    var points: [Int]
    var selfActivated: [String]

    init(_ s: ScoreEngine.ScoreBreakdown, rows: [QSO]) {
        let index = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
        func indices(_ ids: Set<UUID>) -> [Int] { ids.compactMap { index[$0] }.sorted() }
        validQSOs = s.validQSOs; dupeCount = s.dupeCount; invalidModeCount = s.invalidModeCount
        outOfScopeCount = s.outOfScopeCount; outOfTimeCount = s.outOfTimeCount
        qsoPoints = s.qsoPoints; bonusPoints = s.bonusPoints
        memberQSOs = s.memberQSOs; qrpQSOs = s.qrpQSOs; otherQSOs = s.otherQSOs
        multiplierCount = s.multiplierCount; multiplierCap = s.multiplierCap; multiplierFloor = s.multiplierFloor; total = s.total
        categoryFactor = s.categoryFactor
        multiplierKeys = s.multiplierKeys.map { "\($0.classID)|\($0.value)|\($0.scope)|\($0.activated ? "A" : "")" }.sorted()
        dupeRows = indices(s.dupeRowIDs); invalidRows = indices(s.invalidRowIDs)
        outOfScopeRows = indices(s.outOfScopeRowIDs); newMultRows = indices(s.newMultRowIDs)
        points = rows.map { s.pointsByRowID[$0.id] ?? -1 }
        selfActivated = s.selfActivatedCounties.sorted()
    }
}

struct GoldenCase: Codable, Equatable {
    let party: String
    let seed: UInt64
    let side: String
    let breakdown: GoldenBreakdown
}

final class EngineEquivalenceTests: XCTestCase {

    /// The whole corpus, every party, old engine == model engine.
    func testEveryPartyScoresIdenticallyThroughTheModel() throws {
        var compared = 0
        for p in PartyCatalog.loadBundled() {
            let contest = try PartyLowering.lower(p)
            for seed in EquivalenceCorpus.seeds {
                for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                    let label = "\(p.id) seed \(seed) side \(log.sideID) (\(log.myLocation.displayText))"
                    let old = ScoreEngine.score(log: log, party: p)
                    let new = ScoreEngine.score(log: log, contest: contest)
                    XCTAssertEqual(old, new, label)
                    if old != new {   // one readable diff per divergence, then stop the flood
                        XCTFail("\(label): keys only in old \(old.multiplierKeys.subtracting(new.multiplierKeys)); only in new \(new.multiplierKeys.subtracting(old.multiplierKeys)); points \(old.qsoPoints) vs \(new.qsoPoints); bonus \(old.bonusPoints) vs \(new.bonusPoints); valid \(old.validQSOs) vs \(new.validQSOs); scope \(old.outOfScopeCount) vs \(new.outOfScopeCount)")
                    }
                    XCTAssertEqual(ScoreEngine.bandModeCounts(log: log, party: p), ScoreEngine.bandModeCounts(log: log, contest: contest), label)
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(compared, 250, "50 parties × 3 seeds × 1–2 sides")
    }

    /// The NEW MULT question, asked of every probe token on the first band in every mode.
    func testWouldAddMultiplierAgreesOnEveryProbe() throws {
        for p in PartyCatalog.loadBundled() {
            let contest = try PartyLowering.lower(p)
            let seed = EquivalenceCorpus.seeds[0]
            for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                for token in EquivalenceCorpus.receivedPool(p).prefix(8) {
                    for mode in p.allowedModeClasses {
                        for (call, member) in [("W0BH", nil), ("PA0AAA", "13"), ("DL1EEE", "5W")] as [(String, String?)] {
                            let old = ScoreEngine.wouldAddMultiplier(theirLocs: [token], band: p.validBands[0], modeClass: mode,
                                                                     log: log, party: p, call: call, memberRcvd: member)
                            var rcvd = ["location": token]
                            if let member { rcvd["member"] = member }
                            let new = ScoreEngine.wouldAddMultiplier(received: [rcvd], call: call, band: p.validBands[0], modeClass: mode,
                                                                     log: log, contest: contest)
                            XCTAssertEqual(old, new, "\(p.id) \(log.sideID) probe \(token) \(mode) \(call)")
                        }
                    }
                }
            }
        }
    }

    /// The two sidebar predicates the score also pays on.
    func testDesignatedSweepAndCallAreaSumAgree() throws {
        for p in PartyCatalog.loadBundled() {
            let contest = try PartyLowering.lower(p)
            for bonus in p.bonuses {
                for seed in EquivalenceCorpus.seeds {
                    for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                        switch bonus {
                        case .designatedCountySweep(let counties, _, _):
                            XCTAssertEqual(ScoreEngine.designatedCountiesWorked(counties, log: log, party: p),
                                           ScoreEngine.designatedCountiesWorked(counties, log: log, contest: contest), p.id)
                        case .callAreaSum(let target, _):
                            XCTAssertEqual(ScoreEngine.callAreaSumAchieved(target: target, log: log, party: p),
                                           ScoreEngine.callAreaSumAchieved(target: target, log: log, contest: contest), p.id)
                        default: break
                        }
                    }
                }
            }
        }
    }

    func testTheCorpusIsDeterministic() throws {
        let p = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        XCTAssertEqual(EquivalenceCorpus.logs(for: p, seed: 11), EquivalenceCorpus.logs(for: p, seed: 11))
        XCTAssertNotEqual(EquivalenceCorpus.logs(for: p, seed: 11), EquivalenceCorpus.logs(for: p, seed: 23))
        XCTAssertGreaterThanOrEqual(EquivalenceCorpus.logs(for: p, seed: 11).map(\.qsos.count).reduce(0, +), 120)
    }

    /// Where the recording test writes (the sandboxed test host cannot touch
    /// the source tree); the shell copies it to `Tests/Fixtures/Equivalence/`.
    static let goldenURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("QPLRecord/Equivalence/engine-golden.json")

    /// Every corpus log scored through the party overload, in a fixed order.
    static func corpusCases() throws -> [GoldenCase] {
        var out: [GoldenCase] = []
        for p in PartyCatalog.loadBundled() {
            for seed in EquivalenceCorpus.seeds {
                for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                    out.append(GoldenCase(party: p.id, seed: seed, side: log.sideID,
                                          breakdown: GoldenBreakdown(ScoreEngine.score(log: log, party: p), rows: log.qsos)))
                }
            }
        }
        return out
    }

    /// Writes the golden file. Recorded once from the engine as it was before
    /// the switch (`TEST_RUNNER_QPL_RECORD_GOLDEN=1`); re-record only for a
    /// deliberate, party-by-party scoring change, never to make a red run green.
    func testRecordGoldenWhenAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QPL_RECORD_GOLDEN"] == "1", "recording is opt-in")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: Self.goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(try Self.corpusCases()).write(to: Self.goldenURL, options: .atomic)
        print("QPL_RECORD_GOLDEN_PATH=\(Self.goldenURL.path)")
    }

    /// The permanent oracle: the corpus, scored by the engine that shipped
    /// before the switch, reproduced field by field.
    func testEveryPartyMatchesTheGoldenBreakdowns() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "engine-golden", withExtension: "json"),
                                "missing engine-golden.json — record with TEST_RUNNER_QPL_RECORD_GOLDEN=1")
        let golden = try JSONDecoder().decode([GoldenCase].self, from: Data(contentsOf: url))
        let now = try Self.corpusCases()
        XCTAssertEqual(now.count, golden.count)
        for (g, n) in zip(golden, now) {
            XCTAssertEqual(n.party, g.party); XCTAssertEqual(n.seed, g.seed); XCTAssertEqual(n.side, g.side)
            if n.breakdown != g.breakdown {
                XCTFail("\(g.party) seed \(g.seed) side \(g.side): keys only golden \(Set(g.breakdown.multiplierKeys).subtracting(n.breakdown.multiplierKeys)); only now \(Set(n.breakdown.multiplierKeys).subtracting(g.breakdown.multiplierKeys)); points \(g.breakdown.qsoPoints)/\(n.breakdown.qsoPoints) bonus \(g.breakdown.bonusPoints)/\(n.breakdown.bonusPoints) valid \(g.breakdown.validQSOs)/\(n.breakdown.validQSOs) total \(g.breakdown.total)/\(n.breakdown.total)")
            }
        }
    }
}
