import XCTest
@testable import QSOPartyLogger

/// The one question the advisor's needed-mult chips rest on: would working
/// this county, on this band, in this mode, add a multiplier the log does not
/// already hold?
///
/// Pinned on a synthetic party configurable by scope, in the manner of
/// `BonusScopeTests` and `ActivatedCountyMultiplierTests` — the axes that
/// separate the answers are the scope, the entrant's side, and the two rules
/// that make a multiplier pay nothing. Spreading them across whichever bundled
/// parties happen to use each would hide the arithmetic.
final class NeededMultTests: XCTestCase {

    // MARK: A party per scope

    func party(
        countScope: String = "once",
        outStateCountScope: String? = nil,
        outStateClasses: String = "[\"county\"]",
        maxScoredMultipliers: Int? = nil,
        activation: String? = nil
    ) throws -> PartyDefinition {
        let cap = maxScoredMultipliers.map { ",\"maxScoredMultipliers\":\($0)" } ?? ""
        let act = activation.map { ",\"activatedCountyMultiplier\":\($0)" } ?? ""
        let json = """
        {"schemaVersion":1,"id":"nmt","name":"Needed","cabrilloContest":"NMT",
        "homeState":"KS","countyAbbrLength":3,
        "validBands":["80m","40m","20m"],
        "points":{"phone":1,"cw":1,"digital":1},"dupeScope":"bandMode",
        "allowedModes":["phone","cw"],
        "multipliers":{
          "inState":{"classes":["county"],"homeStateCountsViaCounty":false,
                     "countScope":"\(countScope)"\(cap)\(act)},
          "outState":{"classes":\(outStateClasses),"homeStateCountsViaCounty":false,
                      "countScope":"\(outStateCountScope ?? countScope)"\(cap)}},
        "bonuses":[],
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"BAR","name":"Barton"},
                    {"abbr":"CHA","name":"Chase"}]}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    private var seq: TimeInterval = 0

    private func qso(
        call: String = "W0A", band: Band = .m40, mode: ModeClass = .cw,
        my: String = "ALL", their: String
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: "599", rstRcvd: "599", myLoc: my, theirLoc: their
        )
    }

    private func score(
        _ qsos: [QSO], party: PartyDefinition, inState: Bool = false,
        station: StationProfile.CategoryStation = .fixed, myCounty: String = "ALL"
    ) -> ScoreEngine.ScoreBreakdown {
        var log = ContestLog(partyID: party.id)
        log.myLocation = inState ? .inState(counties: [myCounty]) : .outOfState(location: "TX")
        log.station.categoryStation = station
        log.qsos = qsos
        return ScoreEngine.score(log: log, party: party)
    }

    private func needed(
        _ county: String, band: Band = .m40, mode: ModeClass = .cw,
        score: ScoreEngine.ScoreBreakdown, party: PartyDefinition, inState: Bool = false
    ) -> Bool {
        NeededMult.isNeeded(
            county: county, band: band, modeClass: mode, score: score, party: party,
            myLocation: inState ? .inState(counties: ["ALL"]) : .outOfState(location: "TX")
        )
    }

    // MARK: Worked and unworked, at each scope

    /// Under `once`, working a county anywhere finishes it everywhere. A chip
    /// offering it again on another band would be pointing at nothing.
    func testOnceScopeIsSatisfiedByAnyBandAndMode() throws {
        let p = try party(countScope: "once")
        let s = score([qso(band: .m40, their: "BAR")], party: p)

        XCTAssertFalse(needed("BAR", band: .m40, score: s, party: p))
        XCTAssertFalse(needed("BAR", band: .m20, score: s, party: p),
                       "a once-scope county does not come back on another band")
        XCTAssertFalse(needed("BAR", band: .m40, mode: .phone, score: s, party: p))
        XCTAssertTrue(needed("CHA", band: .m40, score: s, party: p))
    }

    /// Under `perBand` the same county is a fresh multiplier on every band —
    /// which is exactly the case where a needed-mult chip earns its place.
    func testPerBandScopeMakesTheSameCountyNeededAgainOnAnotherBand() throws {
        let p = try party(countScope: "perBand")
        let s = score([qso(band: .m40, their: "BAR")], party: p)

        XCTAssertFalse(needed("BAR", band: .m40, score: s, party: p))
        XCTAssertTrue(needed("BAR", band: .m20, score: s, party: p))
        XCTAssertTrue(needed("BAR", band: .m80, score: s, party: p))
        // Mode is not part of a per-band scope, so 40 m phone is still worked.
        XCTAssertFalse(needed("BAR", band: .m40, mode: .phone, score: s, party: p))
    }

    func testPerModeAndPerBandModeScopesSplitTheRightWay() throws {
        let perMode = try party(countScope: "perMode")
        let sMode = score([qso(band: .m40, mode: .cw, their: "BAR")], party: perMode)
        XCTAssertFalse(needed("BAR", band: .m20, mode: .cw, score: sMode, party: perMode))
        XCTAssertTrue(needed("BAR", band: .m40, mode: .phone, score: sMode, party: perMode))

        let perBandMode = try party(countScope: "perBandMode")
        let sBoth = score([qso(band: .m40, mode: .cw, their: "BAR")], party: perBandMode)
        XCTAssertFalse(needed("BAR", band: .m40, mode: .cw, score: sBoth, party: perBandMode))
        XCTAssertTrue(needed("BAR", band: .m40, mode: .phone, score: sBoth, party: perBandMode))
        XCTAssertTrue(needed("BAR", band: .m20, mode: .cw, score: sBoth, party: perBandMode))
    }

    /// An empty log needs every county the party lists.
    func testAnEmptyLogNeedsEveryCounty() throws {
        let p = try party()
        let s = score([], party: p)
        for county in ["ALL", "BAR", "CHA"] {
            XCTAssertTrue(needed(county, score: s, party: p), county)
        }
    }

    // MARK: Both sides

    /// The two sides can carry different scopes — HQP and NHQP both count once
    /// inside the state and per band outside it — so the answer has to follow
    /// the entrant's own side.
    func testTheEntrantsSideDecidesTheScope() throws {
        let p = try party(countScope: "once", outStateCountScope: "perBand")
        let rows = [qso(band: .m40, their: "BAR")]

        let inside = score(rows, party: p, inState: true)
        XCTAssertFalse(needed("BAR", band: .m20, score: inside, party: p, inState: true),
                       "once, inside the state")

        let outside = score(rows, party: p)
        XCTAssertTrue(needed("BAR", band: .m20, score: outside, party: p),
                      "per band, outside it")
    }

    /// A side that does not count counties at all has no county multiplier to
    /// be needed — the chip must not appear for an entrant the rules do not
    /// pay for it.
    func testASideThatDoesNotCountCountiesNeedsNone() throws {
        let p = try party(outStateClasses: "[\"state\"]")
        let s = score([], party: p)
        XCTAssertFalse(needed("BAR", score: s, party: p))
        XCTAssertTrue(needed("BAR", score: score([], party: p, inState: true),
                             party: p, inState: true))
    }

    // MARK: What the party does not count

    func testABandOrModeThePartyDoesNotRunIsNeverNeeded() throws {
        let p = try party()
        let s = score([], party: p)
        // 160 m is not in this party's validBands.
        XCTAssertFalse(needed("BAR", band: .m160, score: s, party: p))
        // Digital is not one of its allowed modes.
        XCTAssertFalse(needed("BAR", band: .m40, mode: .digital, score: s, party: p))
    }

    func testATokenThatIsNotOneOfThePartysCountiesIsNeverNeeded() throws {
        let p = try party()
        let s = score([], party: p)
        // v1 sees county-class needs only: a state, a province, DX and a
        // county from some other party are all silent rather than guessed at.
        for token in ["TX", "ON", "DX", "ZZZ", "", "   "] {
            XCTAssertFalse(needed(token, score: s, party: p), token)
        }
    }

    /// Spot counties arrive from a third party's web form, so case and stray
    /// whitespace are the norm rather than the exception.
    func testCountyTokensAreFoldedBeforeTheyAreLookedUp() throws {
        let p = try party()
        let s = score([qso(their: "BAR")], party: p)
        XCTAssertFalse(needed(" bar ", score: s, party: p))
        XCTAssertTrue(needed("cha", score: s, party: p))
    }

    // MARK: The two rules that make a multiplier pay nothing

    /// Past the party's scored ceiling a further multiplier pays nothing, so
    /// the chip must not send the operator chasing it — the same guard the
    /// NEW MULT badge applies (CQP: 58 of 63).
    func testTheScoredMultiplierCeilingSilencesEveryRemainingCounty() throws {
        let p = try party(maxScoredMultipliers: 2)
        let s = score([qso(call: "W0A", band: .m40, their: "ALL"),
                       qso(call: "W0B", band: .m40, their: "BAR")], party: p)
        XCTAssertEqual(s.multiplierKeys.count, 2)
        XCTAssertFalse(needed("CHA", score: s, party: p), "the ceiling is reached")

        let uncapped = try party()
        XCTAssertTrue(needed("CHA", score: score([qso(their: "ALL"), qso(call: "W0B", their: "BAR")],
                                                 party: uncapped),
                             party: uncapped))
    }

    /// A county already self-activated under a forfeiting rule ("if they do not
    /// earn a multiplier for that county otherwise") trades one key for another
    /// rather than adding one — TnQP and VAQP both word it that way.
    func testAForfeitedActivationCountyIsNotAGain() throws {
        let activation = """
        {"minCount":2,"countUnit":"qsos","countScope":"once",
         "categories":["MOBILE"],"notOtherwiseWorked":true}
        """
        let p = try party(activation: activation)
        // Two QSOs made from ALL, so ALL is self-activated; nobody in ALL has
        // been worked.
        let s = score([qso(call: "W0A", their: "TX"), qso(call: "W0B", their: "TX")],
                      party: p, inState: true, station: .mobile, myCounty: "ALL")
        XCTAssertEqual(s.selfActivatedCounties, ["ALL"])

        XCTAssertFalse(needed("ALL", score: s, party: p, inState: true),
                       "working ALL would forfeit the activation key it replaces")
        XCTAssertTrue(needed("BAR", score: s, party: p, inState: true))
    }

    /// SCQP lists "Each South Carolina county" and "Each SC county activated"
    /// as separate multipliers, so where the sponsor does **not** forfeit, the
    /// worked county is still a gain.
    func testANonForfeitingActivationLeavesTheCountyNeeded() throws {
        let activation = """
        {"minCount":2,"countUnit":"qsos","countScope":"once",
         "categories":["MOBILE"],"notOtherwiseWorked":false}
        """
        let p = try party(activation: activation)
        let s = score([qso(call: "W0A", their: "TX"), qso(call: "W0B", their: "TX")],
                      party: p, inState: true, station: .mobile, myCounty: "ALL")
        XCTAssertEqual(s.selfActivatedCounties, ["ALL"])
        XCTAssertTrue(needed("ALL", score: s, party: p, inState: true))
    }

    // MARK: Against the real catalogue

    /// The synthetic party proves the arithmetic; this proves the same answers
    /// come out of a sponsor's own file. TnQP counts multipliers per band, so
    /// a worked county returns on the next one.
    func testRealPartiesAnswerThroughTheirOwnRules() throws {
        let tnqp = try XCTUnwrap(PartyCatalog.party(id: "tnqp"))
        var log = ContestLog(partyID: "tnqp")
        log.myLocation = .outOfState(location: "TX")
        let county = try XCTUnwrap(tnqp.counties.first).abbr
        log.qsos = [qso(band: .m40, their: county)]
        let s = ScoreEngine.score(log: log, party: tnqp)

        XCTAssertFalse(NeededMult.isNeeded(county: county, band: .m40, modeClass: .cw,
                                           score: s, party: tnqp,
                                           myLocation: log.myLocation))
        XCTAssertTrue(NeededMult.isNeeded(county: county, band: .m20, modeClass: .cw,
                                          score: s, party: tnqp,
                                          myLocation: log.myLocation),
                      "TnQP counts multipliers per band")
    }

    /// CQP is the catalogue's sharpest case of the two sides wanting different
    /// things: a California entrant counts **states and provinces**, not
    /// counties, so no county is ever a multiplier for them — while the same
    /// county is the whole game for everyone outside. v1 sees the second and
    /// stays silent for the first, which is spec §8's stated limit made
    /// concrete rather than papered over.
    func testACaliforniaEntrantIsOfferedNoCountyChipsAtAll() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        XCTAssertEqual(cqp.multipliers.inState.classes, [.state, .province])
        XCTAssertEqual(cqp.multipliers.outState.classes, [.county])

        let home = try XCTUnwrap(cqp.counties.first).abbr
        let away = try XCTUnwrap(cqp.counties.last).abbr

        var caLog = ContestLog(partyID: "cqp")
        caLog.myLocation = .inState(counties: [home])
        let caScore = ScoreEngine.score(log: caLog, party: cqp)
        XCTAssertFalse(NeededMult.isNeeded(county: away, band: .m40, modeClass: .cw,
                                           score: caScore, party: cqp,
                                           myLocation: caLog.myLocation))

        var txLog = ContestLog(partyID: "cqp")
        txLog.myLocation = .outOfState(location: "TX")
        let txScore = ScoreEngine.score(log: txLog, party: cqp)
        XCTAssertTrue(NeededMult.isNeeded(county: away, band: .m40, modeClass: .cw,
                                          score: txScore, party: cqp,
                                          myLocation: txLog.myLocation))
    }

    // MARK: Filtering a spot list

    func testOnlySpotsThatNameANeededCountySurvive() throws {
        let p = try party(countScope: "once")
        let s = score([qso(band: .m40, their: "BAR")], party: p)

        func spot(_ call: String, kHz: Double, county: String?) -> Spot {
            Spot(call: call, freqKHz: kHz, spotter: "W0X", comment: "",
                 receivedAt: Date(timeIntervalSince1970: 1_770_000_000),
                 county: county, source: county == nil ? .cluster : .hub)
        }
        let spots = [
            spot("W0NEED", kHz: 7040, county: "CHA"),      // unworked county
            spot("W0DONE", kHz: 7041, county: "BAR"),      // already worked
            spot("W0BLIND", kHz: 7042, county: nil),       // a cluster spot names no county
            spot("W0OFF", kHz: 10120, county: "CHA"),      // 30 m: not one of this party's bands
            spot("W0JUNK", kHz: 999_999, county: "CHA"),   // no band at all
        ]
        XCTAssertEqual(
            NeededMult.spots(spots, currentMode: .cw, followBandPlan: false,
                             score: s, party: p, myLocation: .outOfState(location: "TX"))
                .map(\.call),
            ["W0NEED"]
        )
    }

    /// Order is the caller's, so the chips come out in the order the band map
    /// would list them rather than in some order of this function's own.
    func testFilteringPreservesTheGivenOrder() throws {
        let p = try party(countScope: "once")
        let s = score([], party: p)
        let calls = ["W0C", "W0A", "W0B"]
        let spots = zip(calls, ["CHA", "ALL", "BAR"]).map { call, county in
            Spot(call: call, freqKHz: 7040, spotter: "W0X", comment: "",
                 receivedAt: Date(timeIntervalSince1970: 1_770_000_000),
                 county: county, source: .hub)
        }
        XCTAssertEqual(
            NeededMult.spots(spots, currentMode: .cw, followBandPlan: false,
                             score: s, party: p, myLocation: .outOfState(location: "TX"))
                .map(\.call),
            calls
        )
    }

    // MARK: Which mode a contact there would be in

    /// The scope in a per-mode party depends on the mode the contact lands in,
    /// so this defers to `BandPlan` — the same rule the tune path obeys — and
    /// leaves the mode alone where the band plan has no opinion or the
    /// operator has switched following off.
    func testWorkedModeClassFollowsTheBandPlanOnlyWhenItIsOn() {
        // 40 m phone starts at 7125.
        XCTAssertEqual(
            NeededMult.workedModeClass(atKHz: 7200, currentMode: .cw, followBandPlan: true),
            .phone
        )
        XCTAssertEqual(
            NeededMult.workedModeClass(atKHz: 7200, currentMode: .cw, followBandPlan: false),
            .cw
        )
        XCTAssertEqual(
            NeededMult.workedModeClass(atKHz: 7040, currentMode: .phone, followBandPlan: true),
            .cw
        )
        // A digital operator in the CW/data segment is left where they are —
        // BandPlan's own promise, inherited rather than restated.
        XCTAssertEqual(
            NeededMult.workedModeClass(atKHz: 7040, currentMode: .digital, followBandPlan: true),
            .digital
        )
        // 60 m has no defensible crossover, so nothing is claimed there.
        XCTAssertEqual(
            NeededMult.workedModeClass(atKHz: 5332, currentMode: .cw, followBandPlan: true),
            .cw
        )
    }

    /// Following the band plan can change the answer in a per-mode party: the
    /// same spot is a needed multiplier in one mode and worked in the other.
    func testTheBandPlanModeCanDecideWhetherAMultiplierIsNeeded() throws {
        let p = try party(countScope: "perMode")
        let s = score([qso(band: .m40, mode: .cw, their: "BAR")], party: p)
        let spot = Spot(call: "W0BAR", freqKHz: 7200, spotter: "W0X", comment: "",
                        receivedAt: Date(timeIntervalSince1970: 1_770_000_000),
                        county: "BAR", source: .hub)

        XCTAssertEqual(
            NeededMult.spots([spot], currentMode: .cw, followBandPlan: true,
                             score: s, party: p, myLocation: .outOfState(location: "TX")).count,
            1, "tuning to 7200 lands in phone, where BAR is unworked"
        )
        XCTAssertEqual(
            NeededMult.spots([spot], currentMode: .cw, followBandPlan: false,
                             score: s, party: p, myLocation: .outOfState(location: "TX")).count,
            0, "staying in CW, BAR is already worked"
        )
    }
}
