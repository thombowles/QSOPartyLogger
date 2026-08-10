import XCTest
@testable import QSOPartyLogger

/// Every advisory the engine can raise, on fixed dates.
///
/// The engine owns its own copy, so the wording is asserted here rather than
/// left to a view — the `RateColumn` arrangement. Nothing in this file reads a
/// wall clock: `now` is an argument, and every sustain window is walked by
/// handing the engine a later `now` with the state it returned.
final class AdvisorTests: XCTestCase {

    // MARK: Fixtures

    private static func utc(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    /// Mid-afternoon in EM13: the sun well up, no crossing within hours.
    private let now = AdvisorTests.utc("2026-08-09 18:00:00")
    private let em13 = "EM13LE"

    private func party(
        validBands: String = #"["80m","40m","20m","10m"]"#,
        bonuses: String = "[]",
        schedule: String? = nil,
        countScope: String = "once"
    ) throws -> PartyDefinition {
        let windows = schedule.map { ",\"schedule\":\($0)" } ?? ""
        let json = """
        {"schemaVersion":1,"id":"adv","name":"Advisory","cabrilloContest":"ADV",
        "homeState":"KS","countyAbbrLength":3,
        "validBands":\(validBands),
        "points":{"phone":1,"cw":1,"digital":1},"dupeScope":"bandMode",
        "allowedModes":["phone","cw"],
        "multipliers":{
          "inState":{"classes":["county"],"homeStateCountsViaCounty":false,
                     "countScope":"\(countScope)"},
          "outState":{"classes":["county"],"homeStateCountsViaCounty":false,
                      "countScope":"\(countScope)"}},
        "bonuses":\(bonuses)\(windows),
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"BAR","name":"Barton"},
                    {"abbr":"CHA","name":"Chase"},{"abbr":"DGL","name":"Douglas"},
                    {"abbr":"ELK","name":"Elk"},{"abbr":"FOR","name":"Ford"}]
        }
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    private func spot(
        _ call: String, kHz: Double, county: String? = nil, spotter: String = "W0X"
    ) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: spotter, comment: "",
             receivedAt: now, county: county, source: county == nil ? .cluster : .hub)
    }

    /// `n` spots on a band, none of them a multiplier this log needs.
    private func filler(_ n: Int, kHz: Double) -> [Spot] {
        (0..<n).map { spot("W\($0)FILL", kHz: kHz + Double($0)) }
    }

    private func input(
        goal: Advisor.Goal = .score,
        mode: OperatingMode = .searchPounce,
        band: Band? = .m20,
        lastTen: Int? = nil,
        lastHour: Int = 0,
        spots: [Spot] = [],
        recent: [Advisor.PostureSample] = [],
        grid: String? = nil,
        spaceWeather: SpaceWeather? = nil,
        inState: Bool = false,
        score: ScoreEngine.ScoreBreakdown = .init(),
        bonusWorked: [String: Set<Advisor.BonusSlot>] = [:],
        muted: Set<Advisor.Advisory.Kind> = [],
        party: PartyDefinition? = nil
    ) throws -> Advisor.Input {
        Advisor.Input(
            goal: goal,
            reading: RateMeter.Reading(lastTen: lastTen, lastHour: lastHour),
            mode: mode,
            currentBand: band,
            currentModeClass: .cw,
            recent: recent,
            score: score,
            party: try party ?? self.party(),
            myLocation: inState ? .inState(counties: ["ALL"]) : .outOfState(location: "TX"),
            gridLocator: grid,
            spaceWeather: spaceWeather,
            spots: spots,
            bonusWorked: bonusWorked,
            followsBandPlan: false,
            mutedKinds: muted
        )
    }

    /// Evaluate repeatedly, threading state, and return the last result — how
    /// a sustain window is actually crossed.
    @discardableResult
    private func run(
        _ input: Advisor.Input, from state: Advisor.State = .init(),
        at times: [Date]
    ) -> (advisories: [Advisor.Advisory], state: Advisor.State) {
        var state = state
        var advisories: [Advisor.Advisory] = []
        for time in times {
            (advisories, state) = Advisor.evaluate(input, state: state, now: time)
        }
        return (advisories, state)
    }

    private func kinds(_ advisories: [Advisor.Advisory]) -> [Advisor.Advisory.Kind] {
        advisories.map(\.kind)
    }

    // MARK: 1 — runFading

    /// The worked example: a run that was doing 46 an hour is doing 18, and
    /// the operator is told the two figures rather than told what to do.
    func testRunFadingFiresAtHalfTheTrailingHourAfterTheSustainWindow() throws {
        let fading = try input(mode: .run, band: .m20, lastTen: 18, lastHour: 46)

        let early = Advisor.evaluate(fading, state: .init(), now: now)
        XCTAssertTrue(early.advisories.isEmpty, "one reading is not a trend")

        let later = run(fading, from: early.state,
                        at: [now.addingTimeInterval(60), now.addingTimeInterval(181)])
        let advisory = try XCTUnwrap(later.advisories.first { $0.kind == .runFading })
        XCTAssertEqual(advisory.headline,
                       "Run fading: 18/hr last 10, down from 46 the past hour.")
        XCTAssertTrue(advisory.detail.contains("⌘R"), "the S&P sweep is named")
        XCTAssertTrue(advisory.detail.contains("⌘J"), "and the way back")
    }

    /// A trailing hour under the floor was not much of a run, and halving it
    /// is noise rather than a fade.
    func testABarelyRunningHourNeverFades() throws {
        let quiet = try input(mode: .run, band: .m20, lastTen: 4, lastHour: 19)
        XCTAssertTrue(run(quiet, at: [now, now.addingTimeInterval(600)]).advisories.isEmpty)
    }

    /// Above 0.5× it never starts.
    func testARunAtOverHalfItsHourDoesNotFade() throws {
        let healthy = try input(mode: .run, band: .m20, lastTen: 24, lastHour: 46)
        XCTAssertTrue(run(healthy, at: [now, now.addingTimeInterval(600)]).advisories.isEmpty)
    }

    /// Hysteresis: it takes 0.5× to start and 0.75× to stop, so a rate sitting
    /// near the line cannot flap the advisory on and off.
    func testTheFadeClearsAtThreeQuartersNotAtAHalf() throws {
        let fading = try input(mode: .run, band: .m20, lastTen: 18, lastHour: 46)
        let live = run(fading, at: [now, now.addingTimeInterval(200)])
        XCTAssertEqual(kinds(live.advisories), [.runFading])

        // 30/46 = 0.65 — recovered past the fire threshold but not past the
        // clear one, so it is still live.
        let recovering = try input(mode: .run, band: .m20, lastTen: 30, lastHour: 46)
        let stillLive = Advisor.evaluate(recovering, state: live.state,
                                         now: now.addingTimeInterval(260))
        XCTAssertEqual(kinds(stillLive.advisories), [.runFading])

        // 35/46 = 0.76 — clear.
        let recovered = try input(mode: .run, band: .m20, lastTen: 35, lastHour: 46)
        XCTAssertTrue(
            Advisor.evaluate(recovered, state: stillLive.state,
                             now: now.addingTimeInterval(320)).advisories.isEmpty
        )
    }

    func testLeavingRunOrChangingBandClearsTheFade() throws {
        let fading = try input(mode: .run, band: .m20, lastTen: 18, lastHour: 46)
        let live = run(fading, at: [now, now.addingTimeInterval(200)])
        XCTAssertEqual(kinds(live.advisories), [.runFading])

        let searching = try input(mode: .searchPounce, band: .m20, lastTen: 18, lastHour: 46)
        XCTAssertFalse(kinds(
            Advisor.evaluate(searching, state: live.state,
                             now: now.addingTimeInterval(260)).advisories
        ).contains(.runFading))

        // A band change ends this run and starts another, so the sustain
        // window begins again rather than the advisory following the operator
        // to a band it has measured nothing on.
        let moved = try input(mode: .run, band: .m40, lastTen: 18, lastHour: 46)
        XCTAssertTrue(
            Advisor.evaluate(moved, state: live.state,
                             now: now.addingTimeInterval(260)).advisories.isEmpty
        )
    }

    func testADismissedFadeStaysDismissedThroughReEvaluation() throws {
        let fading = try input(mode: .run, band: .m20, lastTen: 18, lastHour: 46)
        var (advisories, state) = run(fading, at: [now, now.addingTimeInterval(200)])
        state.dismiss(try XCTUnwrap(advisories.first))

        for offset in [260.0, 400.0, 900.0] {
            (advisories, state) = Advisor.evaluate(
                fading, state: state, now: now.addingTimeInterval(offset))
            XCTAssertTrue(advisories.isEmpty, "still dismissed at +\(offset)s")
        }
    }

    // MARK: 2 — moveCall

    /// The census worked example. 20 m is dead, 40 m has nine workable
    /// stations and four of them are multipliers this log needs.
    func testMoveCallNamesTheCensusAndTheBandYouAreOn() throws {
        let needed = ["ALL", "BAR", "CHA", "DGL"].enumerated().map { index, county in
            spot("W\(index)MULT", kHz: 7040 + Double(index), county: county)
        }
        let moving = try input(
            mode: .searchPounce, band: .m20, lastTen: 12,
            spots: [spot("W0HERE", kHz: 14_040)] + needed + filler(5, kHz: 7100)
        )
        let result = run(moving, at: [now, now.addingTimeInterval(200)])
        let advisory = try XCTUnwrap(result.advisories.first { $0.kind == .moveCall })
        XCTAssertEqual(
            advisory.headline,
            "S&P 40m: 9 workable spots, 4 needed mults — this 20m S&P: 12/hr last 10."
        )
        XCTAssertTrue(advisory.detail.contains("A move needs 2.0× that."))
        XCTAssertTrue(advisory.detail.contains("Nothing moves the radio but you."))
    }

    /// **The goal switch changes the answer.** One census, two yardsticks: the
    /// multiplier-heavy band wins under Score, the busy one under QSOs, where
    /// a new multiplier is worth precisely one QSO.
    func testTheSameCensusRecommendsDifferentBandsUnderTheTwoGoals() throws {
        let multBand = ["ALL", "BAR", "CHA", "DGL"].enumerated().map { index, county in
            spot("W\(index)MULT", kHz: 7040 + Double(index), county: county)
        }
        let busyBand = filler(14, kHz: 3560)
        let spots = [spot("W0HERE", kHz: 14_040)] + multBand + busyBand

        let byScore = run(try input(goal: .score, spots: spots),
                          at: [now, now.addingTimeInterval(200)]).advisories
        XCTAssertTrue(
            try XCTUnwrap(byScore.first { $0.kind == .moveCall }).headline.hasPrefix("S&P 40m:"),
            "four needed multipliers outbid fourteen contacts under Score"
        )

        let byQSOs = run(try input(goal: .qsos, spots: spots),
                         at: [now, now.addingTimeInterval(200)]).advisories
        let qsoCall = try XCTUnwrap(byQSOs.first { $0.kind == .moveCall })
        XCTAssertTrue(qsoCall.headline.hasPrefix("S&P 80m:"),
                      "under QSOs the multiplier premium is zero: got \(qsoCall.headline)")
        XCTAssertFalse(qsoCall.headline.contains("needed mult"),
                       "and the premium is not advertised where it does not apply")
    }

    /// A working run is not interrupted by arithmetic.
    func testAHealthyRunIsNeverInterruptedByAMoveCall() throws {
        let busy = filler(20, kHz: 7100)
        let healthy = try input(mode: .run, band: .m20, lastTen: 40, lastHour: 46, spots: busy)
        XCTAssertTrue(run(healthy, at: [now, now.addingTimeInterval(200),
                                        now.addingTimeInterval(400)]).advisories.isEmpty)

        // Once the run is dying, the same census is allowed to speak.
        let fading = try input(mode: .run, band: .m20, lastTen: 18, lastHour: 46, spots: busy)
        let result = run(fading, at: [now, now.addingTimeInterval(200),
                                      now.addingTimeInterval(400)])
        XCTAssertEqual(kinds(result.advisories), [.runFading, .moveCall])
    }

    func testInSearchAndPounceAMoveCallFiresFreely() throws {
        let searching = try input(mode: .searchPounce, band: .m20, spots: filler(20, kHz: 7100))
        XCTAssertEqual(kinds(run(searching, at: [now, now.addingTimeInterval(200)]).advisories),
                       [.moveCall])
    }

    /// It takes the sustain window here too — one tick of a busy band is not a
    /// reason to abandon where you are.
    func testAMoveCallAlsoWaitsOutTheSustainWindow() throws {
        let searching = try input(spots: filler(20, kHz: 7100))
        XCTAssertTrue(Advisor.evaluate(searching, state: .init(), now: now).advisories.isEmpty)
    }

    /// A QSY makes it a different question — from *this* band to that one —
    /// so the clock starts again rather than the advice following the radio.
    func testAQSYClearsTheMoveCallAndRestartsItsClock() throws {
        let spots = filler(20, kHz: 7100)
        let onTwenty = try input(band: .m20, spots: spots)
        let live = run(onTwenty, at: [now, now.addingTimeInterval(200)])
        XCTAssertEqual(kinds(live.advisories), [.moveCall])

        let onEighty = try input(band: .m80, spots: spots)
        XCTAssertTrue(
            Advisor.evaluate(onEighty, state: live.state,
                             now: now.addingTimeInterval(260)).advisories.isEmpty
        )
    }

    /// The posture strands read stamped rows and nothing else. Ten contacts
    /// on 40 m with no posture on them say nothing about running there.
    func testPostureStrandsReadStampedRowsAndIgnoreEverythingElse() throws {
        let stamped = (0..<10).map { index in
            Advisor.PostureSample(band: .m40, posture: .run,
                                  timestamp: now.addingTimeInterval(-1800 + Double(index) * 120))
        }
        let withEvidence = try input(
            band: .m20, spots: [spot("W0HERE", kHz: 14_040)],
            recent: stamped, inState: true
        )
        let advisory = try XCTUnwrap(
            run(withEvidence, at: [now, now.addingTimeInterval(200)])
                .advisories.first { $0.kind == .moveCall }
        )
        XCTAssertTrue(advisory.headline.hasPrefix("Run 40m:"),
                      "got \(advisory.headline)")
        XCTAssertTrue(advisory.detail.contains("yours here 30/hr over 18 min"),
                      "the measured rate is the evidence: \(advisory.detail)")

        // The same contacts with no posture on them are not evidence at all,
        // so there is nothing to recommend.
        let unstamped = try input(band: .m20, spots: [spot("W0HERE", kHz: 14_040)], inState: true)
        XCTAssertTrue(run(unstamped, at: [now, now.addingTimeInterval(200)]).advisories.isEmpty)
    }

    // MARK: 2b — the spot-free strand

    /// Sunset in EM13 on 2026-08-09 is 0120Z the following morning. Half an
    /// hour past it, a NON-ASSISTED entry — no spots at all — is still told
    /// something true about the sky.
    func testTheSolarTransitionFiresOnceAndOnlyOnce() throws {
        let justAfterSunset = Self.utc("2026-08-10 01:50:00")
        let dark = try input(band: .m20, grid: em13)

        let first = Advisor.evaluate(dark, state: .init(), now: justAfterSunset)
        let advisory = try XCTUnwrap(first.advisories.first { $0.kind == .moveCall })
        XCTAssertTrue(advisory.headline.hasPrefix("Sunset was 0120Z."),
                      "got \(advisory.headline)")
        XCTAssertTrue(advisory.headline.contains("usually take over from here"))
        XCTAssertTrue(advisory.headline.contains("80m") && advisory.headline.contains("40m"),
                      "the night bands are named: \(advisory.headline)")

        // A crossing is an event, not a state to be reminded of every tick.
        for offset in [30.0, 300.0, 900.0] {
            let again = Advisor.evaluate(
                dark, state: first.state,
                now: justAfterSunset.addingTimeInterval(offset))
            XCTAssertTrue(again.advisories.isEmpty, "fired again at +\(offset)s")
        }
    }

    /// The operator's own log is the only thing that can turn "usually" into
    /// "did".
    func testTheTransitionQuotesYourOwnRateOnTheBandTakingOver() throws {
        let justAfterSunset = Self.utc("2026-08-10 01:50:00")
        let stamped = (0..<6).map { index in
            Advisor.PostureSample(
                band: .m40, posture: .run,
                timestamp: justAfterSunset.addingTimeInterval(-2400 + Double(index) * 300))
        }
        let advisory = try XCTUnwrap(
            Advisor.evaluate(try input(band: .m20, recent: stamped, grid: em13),
                             state: .init(), now: justAfterSunset)
                .advisories.first { $0.kind == .moveCall }
        )
        XCTAssertTrue(advisory.headline.contains("Your 40m run earlier: 12/hr."),
                      "got \(advisory.headline)")
    }

    /// No grid, no terminator, nothing to say.
    func testWithoutAGridSquareTheSolarStrandIsSilent() throws {
        let justAfterSunset = Self.utc("2026-08-10 01:50:00")
        XCTAssertTrue(
            Advisor.evaluate(try input(band: .m20, grid: nil),
                             state: .init(), now: justAfterSunset).advisories.isEmpty
        )
    }

    /// Space weather only ever tips a case that was already close, and taking
    /// it away puts the answer back exactly where it was.
    func testTheSpaceWeatherModifierShiftsAMarginalCaseAndItsAbsenceRestoresIt() throws {
        // In-state, sun up. 40 m carries eight spots, 10 m six — close enough
        // that a 15% lift on the high bands changes the winner.
        let spots = filler(8, kHz: 7100) + filler(6, kHz: 28_100)
        let base = try input(band: .m20, spots: spots, grid: em13, inState: true)

        let withoutWeather = try XCTUnwrap(
            run(base, at: [now, now.addingTimeInterval(200)])
                .advisories.first { $0.kind == .moveCall })
        XCTAssertTrue(withoutWeather.headline.hasPrefix("S&P 40m:"),
                      "got \(withoutWeather.headline)")

        let active = SpaceWeather(sfi: 180, kp: 2.0,
                                  observedAt: now.addingTimeInterval(-3600))
        let lifted = try input(band: .m20, spots: spots, grid: em13,
                               spaceWeather: active, inState: true)
        let withWeather = try XCTUnwrap(
            run(lifted, at: [now, now.addingTimeInterval(200)])
                .advisories.first { $0.kind == .moveCall })
        XCTAssertTrue(withWeather.headline.hasPrefix("Run 10m:"),
                      "a high flux lifts the high bands: \(withWeather.headline)")
        XCTAssertTrue(withWeather.detail.contains("SFI 180"),
                      "and the reading is named with its observation time")

        // Stale is the same as absent.
        let stale = SpaceWeather(sfi: 180, kp: 2.0, observedAt: now.addingTimeInterval(-7 * 3600))
        let ignored = try XCTUnwrap(
            run(try input(band: .m20, spots: spots, grid: em13,
                          spaceWeather: stale, inState: true),
                at: [now, now.addingTimeInterval(200)])
                .advisories.first { $0.kind == .moveCall })
        XCTAssertTrue(ignored.headline.hasPrefix("S&P 40m:"), "got \(ignored.headline)")
    }

    // MARK: 3 — neededMultsSpotted

    func testAnUnworkedCountyOnTheAirRaisesAChipCarryingItsSpot() throws {
        let target = spot("W0BAR", kHz: 7040, county: "BAR")
        let result = Advisor.evaluate(try input(spots: [target]), state: .init(), now: now)
        let advisory = try XCTUnwrap(result.advisories.first { $0.kind == .neededMultsSpotted })

        XCTAssertEqual(advisory.headline, "1 needed county on the air.")
        XCTAssertEqual(advisory.chips.count, 1)
        XCTAssertEqual(advisory.chips[0].label, "BAR 7040")
        XCTAssertEqual(advisory.chips[0].spot, target,
                       "the chip carries the very spot it describes")
    }

    func testACountyAlreadyWorkedRaisesNothing() throws {
        let party = try self.party()
        var log = ContestLog(partyID: party.id)
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [QSO(timestampUTC: now, call: "W0BAR", band: .m40, modeClass: .cw,
                        rawMode: "CW", rstSent: "599", rstRcvd: "599",
                        myLoc: "TX", theirLoc: "BAR")]
        let score = ScoreEngine.score(log: log, party: party)

        let result = Advisor.evaluate(
            try input(spots: [spot("W0BAR", kHz: 7040, county: "BAR")],
                      score: score, party: party),
            state: .init(), now: now)
        XCTAssertFalse(kinds(result.advisories).contains(.neededMultsSpotted))
    }

    /// **The NON-ASSISTED pin.** A declared NON-ASSISTED entry never receives
    /// a spot (`SpottingPolicy` stops them reaching the store), so every
    /// spot-derived strand is silent for it with no advisor-side rule.
    func testAnEmptySpotStoreSilencesEverySpotDerivedStrand() throws {
        let result = run(try input(spots: [], grid: em13),
                         at: [now, now.addingTimeInterval(200), now.addingTimeInterval(400)])
        XCTAssertFalse(kinds(result.advisories).contains(.neededMultsSpotted))
        XCTAssertFalse(kinds(result.advisories).contains(.moveCall),
                       "no census means no move call — mid-afternoon there is no crossing either")
    }

    func testChipsAreCappedAtThreeWithAnHonestOverflowCount() throws {
        let spots = ["ALL", "BAR", "CHA", "DGL", "ELK"].enumerated().map { index, county in
            spot("W\(index)X", kHz: 7040 + Double(index), county: county)
        }
        let advisory = try XCTUnwrap(
            Advisor.evaluate(try input(spots: spots), state: .init(), now: now)
                .advisories.first { $0.kind == .neededMultsSpotted })

        XCTAssertEqual(advisory.headline,
                       "5 needed counties on the air — 3 shown, +2 more.")
        XCTAssertEqual(advisory.chips.count, 3)
        XCTAssertEqual(advisory.chips.map(\.label), ["ALL 7040", "BAR 7041", "CHA 7042"])
        XCTAssertEqual(advisory.detail.split(separator: "\n").count, 6,
                       "all five are named in the detail, plus the closing line")
    }

    /// A new county arriving speaks again even after the last set was waved
    /// off — the list prunes and grows itself, and its identity says so.
    func testANewCountyReRaisesAnAdvisoryThatWasDismissed() throws {
        let first = try input(spots: [spot("W0BAR", kHz: 7040, county: "BAR")])
        var (advisories, state) = Advisor.evaluate(first, state: .init(), now: now)
        state.dismiss(try XCTUnwrap(advisories.first))
        (advisories, state) = Advisor.evaluate(first, state: state, now: now)
        XCTAssertTrue(advisories.isEmpty)

        let joined = try input(spots: [spot("W0BAR", kHz: 7040, county: "BAR"),
                                       spot("W0CHA", kHz: 7050, county: "CHA")])
        (advisories, _) = Advisor.evaluate(joined, state: state, now: now)
        XCTAssertEqual(kinds(advisories), [.neededMultsSpotted])
    }

    // MARK: 4 — bonusStanding

    func testAOnceBonusIsNamedUntilItIsWorkedAndThenNeverAgain() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"KS0KS","points":500,"scope":"once"}]"#)

        let unworked = Advisor.evaluate(try input(party: party), state: .init(), now: now)
        XCTAssertEqual(
            try XCTUnwrap(unworked.advisories.first { $0.kind == .bonusStanding }).headline,
            "Bonus KS0KS not yet worked (+500)."
        )

        let worked = Advisor.evaluate(
            try input(bonusWorked: ["KS0KS": [.init(band: .m40, modeClass: .cw)]], party: party),
            state: .init(), now: now)
        XCTAssertFalse(kinds(worked.advisories).contains(.bonusStanding),
                       "a once bonus that has paid has nothing left to say")
    }

    /// The scope decides what "still open" means, and the copy names it.
    func testAPerModeBonusNamesTheModeThatIsStillOpen() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"W7DX","points":500,"scope":"perMode"}]"#)
        let advisory = try XCTUnwrap(
            Advisor.evaluate(
                try input(bonusWorked: ["W7DX": [.init(band: .m40, modeClass: .cw)]],
                          party: party),
                state: .init(), now: now
            ).advisories.first { $0.kind == .bonusStanding })
        XCTAssertEqual(advisory.headline, "W7DX worked on CW — Phone bonus open.")

        let bothModes: Set<Advisor.BonusSlot> = [.init(band: .m40, modeClass: .cw),
                                                 .init(band: .m20, modeClass: .phone)]
        XCTAssertFalse(kinds(
            Advisor.evaluate(try input(bonusWorked: ["W7DX": bothModes], party: party),
                             state: .init(), now: now).advisories
        ).contains(.bonusStanding))
    }

    /// If he is on the air right now, the frequency is the actionable half of
    /// the sentence.
    func testABonusStationOnTheBoardGainsATuneChip() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"KS0KS","points":500,"scope":"once"}]"#)
        let onAir = spot("KS0KS", kHz: 7185, county: "ELK")
        let advisory = try XCTUnwrap(
            Advisor.evaluate(try input(spots: [onAir], party: party), state: .init(), now: now)
                .advisories.first { $0.kind == .bonusStanding })

        XCTAssertEqual(advisory.chips.map(\.label), ["KS0KS 7185"])
        XCTAssertEqual(advisory.chips.first?.spot, onAir)
        XCTAssertTrue(advisory.detail.contains("Spotted at 7185"))
    }

    // MARK: 5 — scheduleEdge

    private func schedule(_ windows: [(String, String)]) -> String {
        "[" + windows.map { start, end in
            #"{"start":"\#(start)","end":"\#(end)"}"#
        }.joined(separator: ",") + "]"
    }

    func testTheFinalTwoHoursOfAWindowCountDown() throws {
        let party = try self.party(schedule: schedule([
            ("2026-08-09T14:00:00Z", "2026-08-09T20:00:00Z"),
        ]))
        // Four hours in, with two to run: nothing yet.
        XCTAssertFalse(kinds(
            Advisor.evaluate(try input(party: party), state: .init(),
                             now: Self.utc("2026-08-09 17:00:00")).advisories
        ).contains(.scheduleEdge))

        let closing = Advisor.evaluate(try input(party: party), state: .init(),
                                       now: Self.utc("2026-08-09 18:30:00"))
        XCTAssertEqual(
            try XCTUnwrap(closing.advisories.first { $0.kind == .scheduleEdge }).headline,
            "90 min left in this window."
        )
    }

    func testBetweenWindowsTheNextOpeningIsNamed() throws {
        let party = try self.party(schedule: schedule([
            ("2026-08-08T14:00:00Z", "2026-08-08T20:00:00Z"),
            ("2026-08-09T13:00:00Z", "2026-08-09T20:00:00Z"),
        ]))
        let advisory = try XCTUnwrap(
            Advisor.evaluate(try input(party: party), state: .init(),
                             now: Self.utc("2026-08-09 02:40:00"))
                .advisories.first { $0.kind == .scheduleEdge })
        XCTAssertEqual(advisory.headline, "Next window opens 1300Z (in 10 h 20 m).")
    }

    /// The between-windows line is about a two-day party's **overnight gap**,
    /// not about the calendar. Opening next month's party in August must not
    /// announce "in 487 h 15 m" — that is not advice, and the dashboard's
    /// upcoming list is where a season belongs.
    func testAPartyStillWeeksAwaySaysNothingAboutItsWindows() throws {
        let party = try self.party(schedule: schedule([
            ("2026-08-29T14:00:00Z", "2026-08-30T02:00:00Z"),
        ]))
        XCTAssertTrue(Advisor.evaluate(try input(party: party), state: .init(), now: now)
            .advisories.isEmpty)

        // A day out it starts speaking, so the bound is a horizon rather than
        // a silence.
        let advisory = try XCTUnwrap(
            Advisor.evaluate(try input(party: party), state: .init(),
                             now: Self.utc("2026-08-28 20:00:00"))
                .advisories.first { $0.kind == .scheduleEdge })
        XCTAssertEqual(advisory.headline, "Next window opens 1400Z (in 18 h).")
    }

    /// After the last window the advisor as a whole goes silent. Everything
    /// else it could say is about a contest that is over.
    func testAfterTheLastWindowEveryKindIsSilent() throws {
        let party = try self.party(schedule: schedule([
            ("2026-08-09T13:00:00Z", "2026-08-09T20:00:00Z"),
        ]))
        let loud = try input(
            mode: .run, band: .m20, lastTen: 18, lastHour: 46,
            spots: [spot("W0BAR", kHz: 7040, county: "BAR")] + filler(20, kHz: 7100),
            grid: em13, party: party
        )
        XCTAssertTrue(run(loud, at: [Self.utc("2026-08-09 20:00:01"),
                                     Self.utc("2026-08-09 20:05:00"),
                                     Self.utc("2026-08-09 21:00:00")]).advisories.isEmpty)
    }

    /// A party with no schedule in its file is never silenced by one.
    func testAPartyWithNoScheduleIsNeverSilenced() throws {
        let advisory = Advisor.evaluate(
            try input(spots: [spot("W0BAR", kHz: 7040, county: "BAR")]),
            state: .init(), now: now)
        XCTAssertEqual(kinds(advisory.advisories), [.neededMultsSpotted])
    }

    // MARK: 6 — priority, muting, dismissal

    func testAdvisoriesComeBackInPriorityOrder() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"KS0KS","points":500,"scope":"once"}]"#,
            schedule: schedule([("2026-08-09T13:00:00Z", "2026-08-09T19:00:00Z")]))
        let everything = try input(
            mode: .run, band: .m20, lastTen: 18, lastHour: 46,
            spots: [spot("W0BAR", kHz: 7040, county: "BAR")] + filler(20, kHz: 7100),
            grid: em13, party: party)

        // Three passes: the fade needs one window, and the move call — which
        // is suppressed until the fade is live — needs its own after that.
        let result = run(everything, at: [now, now.addingTimeInterval(200),
                                          now.addingTimeInterval(400)])
        XCTAssertEqual(kinds(result.advisories),
                       [.runFading, .moveCall, .neededMultsSpotted, .bonusStanding, .scheduleEdge])
    }

    func testMutedKindsNeverAppear() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"KS0KS","points":500,"scope":"once"}]"#)
        let muted = try input(
            spots: [spot("W0BAR", kHz: 7040, county: "BAR")],
            muted: [.neededMultsSpotted], party: party)
        XCTAssertEqual(kinds(Advisor.evaluate(muted, state: .init(), now: now).advisories),
                       [.bonusStanding])
    }

    /// Muting is not silence for everybody: a muted kind must not take its
    /// neighbours down with it, and it must not consume the sustain window of
    /// the kinds that are still speaking.
    func testMutingOneKindLeavesTheOthersUntouched() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"KS0KS","points":500,"scope":"once"}]"#)
        let spots = [spot("W0BAR", kHz: 7040, county: "BAR")] + filler(20, kHz: 7100)
        let plain = run(try input(spots: spots, party: party),
                        at: [now, now.addingTimeInterval(200)]).advisories
        let mutedBonus = run(try input(spots: spots, muted: [.bonusStanding], party: party),
                             at: [now, now.addingTimeInterval(200)]).advisories
        XCTAssertEqual(kinds(plain), [.moveCall, .neededMultsSpotted, .bonusStanding])
        XCTAssertEqual(kinds(mutedBonus), [.moveCall, .neededMultsSpotted])
    }

    /// A dismissal is per sitting, and it belongs to one condition rather than
    /// to a whole kind.
    func testDismissalSurvivesReEvaluationWithoutSilencingTheKind() throws {
        let party = try self.party(
            bonuses: """
            [{"type":"workStation","call":"KS0KS","points":500,"scope":"once"},
             {"type":"workStation","call":"W0BH","points":100,"scope":"once"}]
            """)
        var (advisories, state) = Advisor.evaluate(try input(party: party),
                                                   state: .init(), now: now)
        XCTAssertEqual(advisories.count, 2)
        state.dismiss(try XCTUnwrap(advisories.first { $0.headline.contains("KS0KS") }))

        (advisories, _) = Advisor.evaluate(try input(party: party), state: state,
                                           now: now.addingTimeInterval(600))
        XCTAssertEqual(advisories.count, 1)
        XCTAssertTrue(try XCTUnwrap(advisories.first).headline.contains("W0BH"))
    }

    /// Nothing at all is the commonest and most correct answer.
    func testAQuietContestProducesNothing() throws {
        XCTAssertTrue(
            Advisor.evaluate(try input(), state: .init(), now: now).advisories.isEmpty
        )
    }

    func testWithoutAPartyNothingIsEvaluatedAtAll() throws {
        var bare = try input()
        bare.party = nil
        XCTAssertTrue(Advisor.evaluate(bare, state: .init(), now: now).advisories.isEmpty)
    }

    // MARK: The factory

    func testTheFactoryTakesOnlyStampedRowsOfTheTrailingHour() {
        func row(_ minutesAgo: Double, posture: OperatingMode?) -> QSO {
            QSO(timestampUTC: now.addingTimeInterval(-minutesAgo * 60),
                call: "W0X", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "BAR",
                posture: posture)
        }
        let samples = Advisor.Input.postureSamples(
            [row(10, posture: .run), row(30, posture: .searchPounce),
             row(90, posture: .run), row(20, posture: nil)],
            now: now
        )
        XCTAssertEqual(samples.count, 2, "the 90-minute-old row and the unstamped one are out")
        XCTAssertEqual(Set(samples.map(\.posture)), [.run, .searchPounce])
    }

    func testTheFactoryIndexesOnlyTheBonusCalls() throws {
        let party = try self.party(
            bonuses: #"[{"type":"workStation","call":"KS0KS","points":500,"scope":"perMode"}]"#)
        func row(_ call: String, band: Band, mode: ModeClass) -> QSO {
            QSO(timestampUTC: now, call: call, band: band, modeClass: mode,
                rawMode: mode == .cw ? "CW" : "SSB", rstSent: "599", rstRcvd: "599",
                myLoc: "TX", theirLoc: "BAR")
        }
        let worked = Advisor.Input.bonusWorked(
            [row("ks0ks", band: .m40, mode: .cw), row("ks0ks", band: .m20, mode: .phone),
             row("W0BH", band: .m40, mode: .cw)],
            party: party
        )
        XCTAssertEqual(Set(worked.keys), ["KS0KS"], "no index of the whole log")
        XCTAssertEqual(worked["KS0KS"], [.init(band: .m40, modeClass: .cw),
                                         .init(band: .m20, modeClass: .phone)])
    }

    /// Dupes and wrong-mode rows are not contest QSOs, so they are not
    /// evidence about a band either — the exclusion `ScoreSidebar` already
    /// makes before handing timestamps to `RateMeter`.
    func testTheFactoryExcludesRowsTheScoreDoesNotCount() throws {
        let party = try self.party()
        var log = ContestLog(partyID: party.id)
        log.myLocation = .outOfState(location: "TX")
        log.operatingMode = .run
        log.station.gridLocator = em13
        log.qsos = (0..<4).map { index in
            // Every row is the same station on the same band and mode, so
            // three of the four are dupes.
            QSO(timestampUTC: now.addingTimeInterval(-Double(index) * 300),
                call: "W0BAR", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "BAR",
                posture: .run)
        }
        let score = ScoreEngine.score(log: log, party: party)
        XCTAssertEqual(score.dupeCount, 3, "precondition")

        let built = Advisor.Input.make(
            goal: .score, log: log, party: party, score: score,
            reading: RateMeter.Reading(), currentBand: .m40, currentModeClass: .cw,
            spotsOnBand: { _ in [] }, spaceWeather: nil, followsBandPlan: true,
            mutedKinds: [], now: now
        )
        XCTAssertEqual(built.recent.count, 1)
        XCTAssertEqual(built.gridLocator, em13)
        XCTAssertEqual(built.mode, .run)
    }

    /// The factory asks for each band's spots separately, so the list the
    /// advisor reads is the same one the band map draws — including that
    /// band's own worked-station filtering.
    func testTheFactoryAsksForEveryValidBandSeparately() throws {
        let party = try self.party()
        var asked: [Band] = []
        let built = Advisor.Input.make(
            goal: .score, log: ContestLog(partyID: party.id), party: party,
            score: .init(), reading: RateMeter.Reading(), currentBand: .m40,
            currentModeClass: .cw,
            spotsOnBand: { band in
                asked.append(band)
                return band == .m40 ? [self.spot("W0BAR", kHz: 7040, county: "BAR")] : []
            },
            spaceWeather: nil, followsBandPlan: true, mutedKinds: [], now: now
        )
        XCTAssertEqual(asked, party.validBands)
        XCTAssertEqual(built.spots.map(\.call), ["W0BAR"])
    }
}
