import XCTest
@testable import QSOPartyLogger

/// `MultRule.activatedCountyMultiplier` — the multiplier five sponsors give an
/// in-state station for each county it **operates from**, as against each county
/// it works.
///
/// Pinned on one synthetic party in the manner of `BonusScopeTests`, because no
/// two of the five sponsors agree on any of the five axes and the arithmetic
/// that separates them belongs in one place rather than spread across the
/// parties that happen to use each. Its own commit under Article 4, adding no
/// party — `testNoBundledPartyCarriesTheFieldYet` is the proof that every
/// already-bundled party still scores identically.
///
/// See `docs/superpowers/specs/2026-07-28-activated-county-multipliers-design.md`.
final class ActivatedCountyMultiplierTests: XCTestCase {

    // MARK: A synthetic party, configurable on all five axes

    /// `activation` is the JSON body of `activatedCountyMultiplier`, or nil for
    /// a party without one. `countScope` is the *side's* scope, deliberately
    /// separate from the activation's own — TnQP's differ.
    func party(
        countScope: String = "once",
        activation: String? = nil,
        maxScoredMultipliers: Int? = nil,
        bonuses: String = "[]"
    ) throws -> PartyDefinition {
        let act = activation.map { ",\"activatedCountyMultiplier\":\($0)" } ?? ""
        let cap = maxScoredMultipliers.map { ",\"maxScoredMultipliers\":\($0)" } ?? ""
        let json = """
        {"schemaVersion":1,"id":"acm","name":"Activation","cabrilloContest":"ACM",
        "homeState":"KS","countyAbbrLength":3,
        "validBands":["160m","80m","40m","20m"],
        "points":{"phone":1,"cw":1,"digital":1},"dupeScope":"bandMode",
        "allowedModes":["phone","cw"],
        "multipliers":{
          "inState":{"classes":["county"],"homeStateCountsViaCounty":false,
                     "countScope":"\(countScope)"\(cap)\(act)},
          "outState":{"classes":["county"],"homeStateCountsViaCounty":false,
                      "countScope":"\(countScope)"}},
        "bonuses":\(bonuses),
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"BAR","name":"Barton"},
                    {"abbr":"CHA","name":"Chase"}]}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    /// The five axes, spelled out as JSON so each test reads as the sponsor's
    /// sentence rather than as a struct literal.
    func activation(
        minCount: Int,
        unit: String = "qsos",
        scope: String = "once",
        categories: [String] = ["MOBILE"],
        notOtherwiseWorked: Bool = false
    ) -> String {
        let cats = categories.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"minCount":\(minCount),"countUnit":"\(unit)","countScope":"\(scope)",
         "categories":[\(cats)],"notOtherwiseWorked":\(notOtherwiseWorked)}
        """
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0A",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "ALL",
        their: String = "TX"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "599", rstRcvd: "599", myLoc: my, theirLoc: their
        )
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "ALL",
        station: StationProfile.CategoryStation = .mobile
    ) -> ContestLog {
        var log = ContestLog(partyID: "acm")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    /// `n` QSOs made from `county`, each with a distinct callsign unless
    /// `stations` is given — which is how the QSO/station distinction is forced.
    func rows(from county: String, qsos n: Int, stations: Int? = nil,
              band: Band = .m40, mode: ModeClass = .cw) -> [QSO] {
        (0..<n).map { i in
            let station = stations.map { i % $0 } ?? i
            // A repeat station must land on a different band to avoid the dupe
            // check, since a dupe is not a valid QSO and would confound the count.
            let b: Band = stations == nil ? band : [Band.m160, .m80, .m40, .m20][i / (stations ?? 1) % 4]
            return qso(call: "W0\(county)\(station)", band: b, mode: mode,
                       my: county, their: "TX")
        }
    }

    // MARK: Axis 1 and 2 — the threshold, and what it counts

    /// MOQP wants "50 or more valid contacts"; VAQP wants "10 (ten) or more
    /// different stations". One log, two readings.
    func testTheThresholdUnitIsQSOsOrDistinctStations() throws {
        // Twelve QSOs from ALL, but only four distinct callsigns.
        let log = inLog(rows(from: "ALL", qsos: 12, stations: 4))

        let byQSOs = try party(activation: activation(minCount: 10, unit: "qsos"))
        XCTAssertEqual(
            ScoreEngine.score(log: log, party: byQSOs).selfActivatedCounties, ["ALL"],
            "twelve QSOs clears a threshold of ten QSOs"
        )

        let byStations = try party(activation: activation(minCount: 10, unit: "stations"))
        XCTAssertEqual(
            ScoreEngine.score(log: log, party: byStations).selfActivatedCounties, [],
            "four distinct stations does not clear a threshold of ten stations"
        )

        let lowerBar = try party(activation: activation(minCount: 4, unit: "stations"))
        XCTAssertEqual(
            ScoreEngine.score(log: log, party: lowerBar).selfActivatedCounties, ["ALL"]
        )
    }

    /// The threshold is a floor, and it is applied per county rather than to the
    /// log as a whole.
    func testThresholdIsAppliedPerCountyAndIsInclusive() throws {
        let p = try party(activation: activation(minCount: 10))
        var log = inLog(rows(from: "ALL", qsos: 10) + rows(from: "BAR", qsos: 9))
        log.myLocation = .inState(counties: ["ALL"])
        let s = ScoreEngine.score(log: log, party: p)
        XCTAssertEqual(s.selfActivatedCounties, ["ALL"], "ten qualifies, nine does not")
    }

    /// Dupes and rows in a mode the party does not run are not valid QSOs and
    /// must not push a county over the bar.
    func testDupesAndDisallowedModesDoNotCountTowardTheThreshold() throws {
        let p = try party(activation: activation(minCount: 3))
        let good = qso(call: "W0X", band: .m40, mode: .cw, my: "ALL", their: "TX")
        var dupe = good
        dupe.id = UUID()
        let digital = qso(call: "W0Y", band: .m40, mode: .digital, my: "ALL", their: "OK")
        let third = qso(call: "W0Z", band: .m40, mode: .cw, my: "ALL", their: "NE")

        let s = ScoreEngine.score(log: inLog([good, dupe, digital, third]), party: p)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.invalidModeCount, 1, "the party allows phone and CW only")
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.selfActivatedCounties, [], "two valid QSOs is short of three")
    }

    // MARK: Axis 3 — the granted multiplier's own scope

    /// SCQP grants it "ONCE PER MODE PER BAND"; the other four grant it once.
    /// The scope is the activation's own, **not** the side's — TnQP counts
    /// worked multipliers per band and grants this one once.
    func testScopeIsTheActivationsOwnAndNotTheSides() throws {
        // Four QSOs from ALL across two bands × two modes.
        let spread = [
            qso(call: "W0A", band: .m40, mode: .cw, my: "ALL"),
            qso(call: "W0B", band: .m40, mode: .phone, my: "ALL"),
            qso(call: "W0C", band: .m20, mode: .cw, my: "ALL"),
            qso(call: "W0D", band: .m20, mode: .phone, my: "ALL"),
        ]

        let once = try party(countScope: "perBandMode",
                             activation: activation(minCount: 1, scope: "once"))
        XCTAssertEqual(
            ScoreEngine.score(log: inLog(spread), party: once)
                .multiplierKeys.filter { $0.activated }.count, 1,
            "granted once however many band/mode slots were used"
        )

        let perBandMode = try party(countScope: "once",
                                    activation: activation(minCount: 1, scope: "perBandMode"))
        XCTAssertEqual(
            ScoreEngine.score(log: inLog(spread), party: perBandMode)
                .multiplierKeys.filter { $0.activated }.count, 4,
            "one per band/mode slot actually operated from that county"
        )

        let perBand = try party(countScope: "once",
                                activation: activation(minCount: 1, scope: "perBand"))
        XCTAssertEqual(
            ScoreEngine.score(log: inLog(spread), party: perBand)
                .multiplierKeys.filter { $0.activated }.count, 2, "40 m and 20 m"
        )
    }

    /// The scoped keys come from **that county's own rows** — a band used from
    /// one county does not grant the other county a key on it.
    func testScopedKeysComeFromEachCountysOwnRows() throws {
        let p = try party(activation: activation(minCount: 1, scope: "perBand"))
        let log = inLog([
            qso(call: "W0A", band: .m40, my: "ALL"),
            qso(call: "W0B", band: .m20, my: "ALL"),
            qso(call: "W0C", band: .m80, my: "BAR"),
        ])
        let activated = ScoreEngine.score(log: log, party: p).multiplierKeys.filter { $0.activated }
        XCTAssertEqual(
            Set(activated.map { "\($0.value)/\($0.scope)" }),
            ["ALL/40m", "ALL/20m", "BAR/80m"]
        )
    }

    // MARK: Axis 4 — which entrant categories qualify

    /// NCQP gives it to every NC station including fixed; MOQP names mobile and
    /// portable; TnQP names mobiles and rovers. The list is the sponsor's.
    func testOnlyTheCategoriesTheSponsorNamesQualify() throws {
        let mobileOnly = try party(activation: activation(minCount: 1, categories: ["MOBILE"]))
        let everyone = try party(activation: activation(
            minCount: 1,
            categories: ["FIXED", "MOBILE", "PORTABLE", "ROVER", "EXPEDITION", "SCHOOL"]
        ))
        let rows = [qso(call: "W0A", my: "ALL")]

        for category in StationProfile.CategoryStation.allCases {
            let log = inLog(rows, station: category)
            XCTAssertEqual(
                ScoreEngine.score(log: log, party: mobileOnly).selfActivatedCounties,
                category == .mobile ? ["ALL"] : [],
                "\(category.rawValue) against a mobile-only rule"
            )
            XCTAssertEqual(
                ScoreEngine.score(log: log, party: everyone).selfActivatedCounties, ["ALL"],
                "\(category.rawValue) against a rule naming every category"
            )
        }
    }

    /// The rule lives on the in-state side, so an out-of-state entrant can never
    /// reach it — and neither can a county token that is not this party's.
    func testOutOfStateEntrantsAndForeignCountiesNeverActivate() throws {
        let p = try party(activation: activation(
            minCount: 1, categories: ["FIXED", "MOBILE", "PORTABLE", "ROVER", "EXPEDITION", "SCHOOL"]
        ))
        var out = ContestLog(partyID: "acm")
        out.myLocation = .outOfState(location: "TX")
        out.station.categoryStation = .mobile
        out.qsos = [qso(call: "W0A", my: "TX", their: "ALL")]
        XCTAssertEqual(ScoreEngine.score(log: out, party: p).selfActivatedCounties, [])

        // In-state, but sending a token this party has no county for.
        var odd = inLog([qso(call: "W0A", my: "ZZZ", their: "TX")])
        odd.myLocation = .inState(counties: ["ZZZ"])
        XCTAssertEqual(ScoreEngine.score(log: odd, party: p).selfActivatedCounties, [])
    }

    // MARK: Axis 5 — whether working the county forfeits the activation

    /// TnQP: "if they do not earn a multiplier for that county otherwise".
    /// VAQP: "if not otherwise worked". NCQP and MOQP say it by arithmetic —
    /// their printed maxima are exactly their entity lists. SCQP alone lists
    /// worked and activated counties as separate numbered multipliers.
    func testNotOtherwiseWorkedForfeitsAndTheAdditiveReadingDoesNot() throws {
        // Sitting in ALL, and also working somebody in ALL.
        let log = inLog([
            qso(call: "W0A", my: "ALL", their: "ALL"),
            qso(call: "W0B", my: "ALL", their: "BAR"),
        ])

        let forfeits = try party(activation: activation(minCount: 1, notOtherwiseWorked: true))
        let f = ScoreEngine.score(log: log, party: forfeits)
        XCTAssertEqual(f.selfActivatedCounties, [], "ALL was worked, so the activation is forfeit")
        XCTAssertEqual(f.multiplierCount, 2, "ALL and BAR, each once")

        let additive = try party(activation: activation(minCount: 1, notOtherwiseWorked: false))
        let a = ScoreEngine.score(log: log, party: additive)
        XCTAssertEqual(a.selfActivatedCounties, ["ALL"])
        XCTAssertEqual(a.multiplierCount, 3, "ALL worked, ALL activated, and BAR")
    }

    /// The forfeit looks at the county at **any** scope, which is the case that
    /// set semantics alone cannot handle: TnQP counts worked multipliers per
    /// band and grants the activation once, so the two keys never collide.
    func testTheForfeitLooksAcrossScopes() throws {
        let p = try party(countScope: "perBand",
                          activation: activation(minCount: 1, scope: "once",
                                                 notOtherwiseWorked: true))
        let worked = inLog([qso(call: "W0A", band: .m40, my: "ALL", their: "ALL")])
        let s = ScoreEngine.score(log: worked, party: p)
        XCTAssertEqual(s.selfActivatedCounties, [])
        XCTAssertEqual(s.multiplierCount, 1, "ALL on 40 m, and nothing for sitting in it")

        // Working a different county leaves the activation intact.
        let elsewhere = inLog([qso(call: "W0A", band: .m40, my: "ALL", their: "BAR")])
        let e = ScoreEngine.score(log: elsewhere, party: p)
        XCTAssertEqual(e.selfActivatedCounties, ["ALL"])
        XCTAssertEqual(e.multiplierCount, 2, "BAR on 40 m, plus ALL for sitting in it")
    }

    // MARK: Interaction with the rest of the engine

    /// An activated county is a multiplier: it multiplies QSO points and it is
    /// subject to the party's scored-multiplier cap.
    func testActivationMultipliesPointsAndObeysTheCap() throws {
        let log = inLog([
            qso(call: "W0A", my: "ALL", their: "BAR"),
            qso(call: "W0B", my: "ALL", their: "CHA"),
        ])
        let p = try party(activation: activation(minCount: 1))
        let s = ScoreEngine.score(log: log, party: p)
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 3, "BAR and CHA worked, ALL activated")
        XCTAssertEqual(s.total, 2 * 3)

        let capped = try party(activation: activation(minCount: 1), maxScoredMultipliers: 2)
        let c = ScoreEngine.score(log: log, party: capped)
        XCTAssertEqual(c.multiplierKeys.count, 3, "all three are still tallied")
        XCTAssertEqual(c.multiplierCount, 2, "only two are paid for")
    }

    /// `sweepTiers` counts counties **worked**. A county the operator merely sat
    /// in must not carry them over a sweep threshold, which is why the
    /// activation block runs after bonuses are computed.
    func testASweepCountsWorkedCountiesAndNotActivatedOnes() throws {
        let p = try party(
            activation: activation(minCount: 1),
            bonuses: #"[{"type":"sweepTiers","tiers":[{"count":2,"points":500}]}]"#
        )
        // One county worked, one county sat in.
        let s = ScoreEngine.score(log: inLog([qso(call: "W0A", my: "ALL", their: "BAR")]), party: p)
        XCTAssertEqual(s.selfActivatedCounties, ["ALL"])
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.bonusPoints, 0, "only BAR was worked; the sweep needs two")

        let two = ScoreEngine.score(log: inLog([
            qso(call: "W0A", my: "ALL", their: "BAR"),
            qso(call: "W0B", my: "ALL", their: "CHA"),
        ]), party: p)
        XCTAssertEqual(two.bonusPoints, 500)
    }

    // MARK: The NEW MULT badge

    /// A forfeiting rule means the first contact into a county you have already
    /// activated is **not** a new multiplier — it trades one key for another.
    /// The badge must not send the operator chasing it, which is the same
    /// failure the `maxScoredMultipliers` guard exists to prevent.
    func testTheBadgeDoesNotPromiseAForfeitedMultiplier() throws {
        let p = try party(countScope: "perBand",
                          activation: activation(minCount: 1, scope: "once",
                                                 notOtherwiseWorked: true))
        let activated = inLog([qso(call: "W0A", band: .m40, my: "ALL", their: "BAR")])
        XCTAssertEqual(ScoreEngine.score(log: activated, party: p).selfActivatedCounties, ["ALL"])

        XCTAssertFalse(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: ["ALL"], band: .m40, modeClass: .cw, log: activated, party: p
            ),
            "working ALL forfeits the activation multiplier — no net gain"
        )
        XCTAssertTrue(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: ["CHA"], band: .m40, modeClass: .cw, log: activated, party: p
            ),
            "a county neither worked nor activated is still a new multiplier"
        )

        // Once ALL has been worked on 40 m the activation is already gone, so a
        // second band genuinely adds one.
        let worked = inLog([
            qso(call: "W0A", band: .m40, my: "ALL", their: "BAR"),
            qso(call: "W0B", band: .m40, my: "ALL", their: "ALL"),
        ])
        XCTAssertTrue(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: ["ALL"], band: .m20, modeClass: .cw, log: worked, party: p
            ),
            "ALL on a second band, with nothing left to forfeit"
        )
    }

    /// Under the additive reading the same contact **is** a new multiplier,
    /// because the activated key and the worked key coexist.
    func testTheBadgeFiresUnderTheAdditiveReading() throws {
        let p = try party(countScope: "perBandMode",
                          activation: activation(minCount: 1, scope: "perBandMode",
                                                 notOtherwiseWorked: false))
        let activated = inLog([qso(call: "W0A", band: .m40, mode: .cw, my: "ALL", their: "BAR")])
        XCTAssertTrue(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: ["ALL"], band: .m40, modeClass: .cw, log: activated, party: p
            ),
            "worked and activated are separate multipliers here"
        )
    }

    /// Every party without the field keeps the old badge path exactly.
    func testTheBadgeIsUnchangedWithoutAnActivationRule() throws {
        let p = try party()
        let log = inLog([qso(call: "W0A", band: .m40, my: "ALL", their: "BAR")])
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["BAR"], band: .m40, modeClass: .cw, log: log, party: p))
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["CHA"], band: .m40, modeClass: .cw, log: log, party: p))
    }

    // MARK: Schema

    /// Article 4: absent decodes to nil, and a party without one scores exactly
    /// as it did before this field existed.
    func testAbsentDecodesToNilAndChangesNothing() throws {
        let p = try party()
        XCTAssertNil(p.multipliers.inState.activatedCountyMultiplier)
        XCTAssertNil(p.multipliers.outState.activatedCountyMultiplier)

        // Twenty QSOs from ALL — far past any threshold — plus one worked county.
        let log = inLog(rows(from: "ALL", qsos: 20) + [qso(call: "W0Z", my: "ALL", their: "BAR")])
        let s = ScoreEngine.score(log: log, party: p)
        XCTAssertEqual(s.validQSOs, 21)
        XCTAssertEqual(s.selfActivatedCounties, [])
        XCTAssertEqual(s.multiplierKeys.filter { $0.activated }.count, 0)
        XCTAssertEqual(
            s.multiplierCount, 1,
            "BAR worked. The twenty QSOs from ALL earn nothing, and the twenty "
                + "TX contacts earn nothing either — this side counts counties only."
        )
    }

    /// Every field is required, so no future party inherits one sponsor's rule
    /// by omission. A partial object is a decode failure, not a default.
    func testEveryFieldIsRequired() throws {
        let complete = #"{"minCount":1,"countUnit":"qsos","countScope":"once","categories":["MOBILE"],"notOtherwiseWorked":false}"#
        XCTAssertNoThrow(try party(activation: complete))

        for missing in ["minCount", "countUnit", "countScope", "categories", "notOtherwiseWorked"] {
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(complete.utf8)) as? [String: Any]
            )
            var partial = object
            partial.removeValue(forKey: missing)
            let json = String(
                decoding: try JSONSerialization.data(withJSONObject: partial), as: UTF8.self
            )
            XCTAssertThrowsError(try party(activation: json), "missing \(missing) must not decode")
        }
    }

    /// Raw values are what a party JSON writes, so they are storage.
    func testRawValuesAreStorage() {
        XCTAssertEqual(PartyDefinition.ActivatedCountyMultiplier.CountUnit.qsos.rawValue, "qsos")
        XCTAssertEqual(PartyDefinition.ActivatedCountyMultiplier.CountUnit.stations.rawValue, "stations")
    }

    /// The Article 4 guarantee stated as a roster: this commit adds the field
    /// and no party uses it, so no bundled score can have moved. Each party
    /// commit that follows adds itself here.
    func testNoBundledPartyCarriesTheFieldYet() {
        let users = PartyCatalog.loadBundled()
            .filter {
                $0.multipliers.inState.activatedCountyMultiplier != nil
                    || $0.multipliers.outState.activatedCountyMultiplier != nil
            }
            .map(\.id)
            .sorted()
        XCTAssertEqual(users, ["scqp"])
    }
}
