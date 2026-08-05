import XCTest
@testable import QSOPartyLogger

/// The sidebar's multiplier tracker exists to answer "what am I still
/// missing", which it cannot do while it draws only the tokens already
/// worked. `MultiplierRoster` supplies the full list per class, and the two
/// cross-party tests at the bottom are the accuracy guard: every token a
/// roster draws must be one `ScoreEngine` credits to that class, and every
/// token the engine credits must appear in a roster.
///
/// Layout follows N1MM Logger+'s Multipliers window — all multipliers shown
/// worked or not, one block per band, "blue for a band where the mult has
/// already been worked". Manual fetched 2026-07-31,
/// https://n1mmwp.hamdocs.com/manual-windows/multipliers-window/
@MainActor
final class MultiplierRosterTests: XCTestCase {

    func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: id), "bundled \(id) should load")
    }

    func roster(
        _ party: PartyDefinition, _ multClass: MultClass, inState: Bool = true
    ) -> MultiplierRoster.ClassRoster? {
        let rule = inState ? party.multipliers.inState : party.multipliers.outState
        return MultiplierRoster.classes(party: party, rule: rule)
            .first { $0.multClass == multClass }
    }

    func tokens(
        _ party: PartyDefinition, _ multClass: MultClass, inState: Bool = true
    ) -> [String] {
        roster(party, multClass, inState: inState)?.entries.map(\.token) ?? []
    }

    // MARK: Roster contents

    /// NAQP counts everything and excludes nothing — the 50 states, DC as its
    /// own multiplier (rule 11), the 13 provinces, and the sponsor's 46-entry
    /// country checklist. Nothing is the "home" anything.
    func testNAQPListsEveryStateProvinceAndCountry() throws {
        let naqp = try party("naqpcw")
        XCTAssertEqual(tokens(naqp, .state).count, 51, "50 states + DC")
        XCTAssertTrue(tokens(naqp, .state).contains("DC"))
        XCTAssertTrue(tokens(naqp, .state).contains("TX"), "no home state is excluded")
        XCTAssertEqual(tokens(naqp, .province).count, 13)
        XCTAssertEqual(tokens(naqp, .county).count, 46)
    }

    /// CQP aliases DC to MD — a received DC credits the Maryland multiplier,
    /// so DC is a loggable token but never a roster entry of its own. Drawing
    /// it would promise a multiplier that cannot be earned.
    func testAnAliasedTokenIsNeverItsOwnRosterEntry() throws {
        let cqp = try party("cqp")
        let states = tokens(cqp, .state)
        XCTAssertFalse(states.contains("DC"), "DC credits MD here, so it is not an entry")
        XCTAssertTrue(states.contains("MD"))
        XCTAssertEqual(states.count, 50, "51 accepted, less DC, CA still reachable by county")
    }

    /// KSQP's in-state side counts states but not counties, and
    /// `homeStateCountsViaCounty` makes the first Kansas county logged satisfy
    /// the Kansas multiplier. KS is therefore reachable and must be drawn,
    /// even though it is an excluded *token*.
    func testAHomeStateReachedThroughACountyIsStillListed() throws {
        let ksqp = try party("ksqp")
        XCTAssertTrue(tokens(ksqp, .state).contains("KS"))
        XCTAssertEqual(tokens(ksqp, .state).count, 51)
    }

    /// 7QP is one log over eight states, each reachable through its counties —
    /// all eight belong in the roster, not just the primary `homeState`.
    func testEveryMemberStateOfAMultiStatePartyIsListed() throws {
        let sevenqp = try party("sevenqp")
        let states = tokens(sevenqp, .state)
        for member in sevenqp.homeStates {
            XCTAssertTrue(states.contains(member), "\(member) is reachable by county")
        }
        XCTAssertEqual(states.count, 51)
    }

    /// OhQP counts 11 provinces, not the default 13 — the roster reads the
    /// party's own list rather than the class default.
    func testAPartyWithItsOwnProvinceListDrawsThatList() throws {
        XCTAssertEqual(try tokens(party("ohqp"), .province).count, 11)
        XCTAssertEqual(try tokens(party("qcqp"), .province).count, 14)
    }

    /// PAQP grants EPA and WPA outright — "there is no need to enter them" —
    /// because a Pennsylvania station sends a county and never the section.
    /// They are drawn already credited, not as something to chase.
    func testGrantedMultipliersAreListedAndMarkedGranted() throws {
        let paqp = try party("paqp")
        let sections = try XCTUnwrap(roster(paqp, .section))
        XCTAssertTrue(sections.entries.contains { $0.token == "EPA" && $0.granted })
        XCTAssertTrue(sections.entries.contains { $0.token == "WPA" && $0.granted })
        XCTAssertFalse(
            sections.entries.contains { $0.token == "NTX" && $0.granted },
            "an ordinary section is chased, not granted"
        )
    }

    /// DX under prefix style is any plausible prefix — an unbounded set, so
    /// there is no roster to draw and the sidebar keeps its worked-only list.
    func testDXHasNoRoster() throws {
        let ohqp = try party("ohqp")
        XCTAssertTrue(ohqp.multipliers.inState.classes.contains(.dx))
        XCTAssertNil(roster(ohqp, .dx), "unbounded class, no checklist possible")
    }

    /// The county grid already drew every county for award tracking even where
    /// counties do not score (KSQP in-state, Worked All Kansas). That survives,
    /// flagged so the header can still say so.
    func testCountiesAreListedForAwardTrackingWhenTheyDoNotScore() throws {
        let ksqp = try party("ksqp")
        let counties = try XCTUnwrap(roster(ksqp, .county))
        XCTAssertFalse(counties.isMultClass)
        XCTAssertEqual(counties.entries.count, ksqp.counties.count)
        XCTAssertEqual(counties.slots.count, 1, "an award is worked-or-not, never per band")
    }

    // MARK: Slots

    /// The block strip is the set of scope values a multiplier can be counted
    /// under — the same component `ScoreEngine` stamps into a `MultKey`.
    func testSlotsFollowTheCountScope() throws {
        let naqp = try party("naqpcw")
        XCTAssertEqual(naqp.multipliers.inState.countScope, .perBand)
        XCTAssertEqual(
            MultiplierRoster.slots(party: naqp, rule: naqp.multipliers.inState).map(\.scope),
            ["160m", "80m", "40m", "20m", "15m", "10m"]
        )

        let cqp = try party("cqp")
        XCTAssertEqual(cqp.multipliers.inState.countScope, .once)
        let onceSlots = MultiplierRoster.slots(party: cqp, rule: cqp.multipliers.inState)
        XCTAssertEqual(onceSlots.map(\.scope), [""], "one unscoped slot, drawn as a plain chip")

        let ohqp = try party("ohqp")
        XCTAssertEqual(ohqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(
            MultiplierRoster.slots(party: ohqp, rule: ohqp.multipliers.inState).map(\.scope),
            ["phone", "cw"]
        )

        let scqp = try party("scqp")
        XCTAssertEqual(scqp.multipliers.inState.countScope, .perBandMode)
        let slots = MultiplierRoster.slots(party: scqp, rule: scqp.multipliers.inState)
        XCTAssertEqual(slots.count, scqp.validBands.count * scqp.allowedModeClasses.count)
        XCTAssertEqual(slots.first?.scope, "160m/phone")
    }

    /// Bands own the display column wherever a band is in scope. SCQP counts
    /// per band *and* per mode over 8 bands and 3 modes — drawn as 24 blocks
    /// per multiplier that is unreadable in a 270pt sidebar, so it becomes 8
    /// columns of 3 and the block fills by how many modes are done.
    func testBandsOwnTheColumnWhereverABandIsInScope() throws {
        let scqp = try party("scqp")
        let counties = try XCTUnwrap(roster(scqp, .county))
        XCTAssertEqual(counties.slots.count, 24)
        XCTAssertEqual(counties.columns.count, 8, "one column per band, not per band/mode")
        XCTAssertEqual(counties.columns[0].label, "160m")
        XCTAssertEqual(counties.columns[0].slots.count, 3, "phone, cw, digital")

        let ohqp = try party("ohqp")
        XCTAssertEqual(try XCTUnwrap(roster(ohqp, .state)).columns.map(\.label), ["PH", "CW"])

        let cqp = try party("cqp")
        XCTAssertEqual(try XCTUnwrap(roster(cqp, .state)).columns.count, 1, "a plain chip")
    }

    /// A slot's scope string has to be the engine's, or a filled block would
    /// claim a multiplier the score does not hold.
    func testASlotScopeMatchesTheKeyTheEngineStamps() throws {
        let naqp = try party("naqpcw")
        var log = ContestLog(partyID: "naqpcw")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_785_607_260),
                call: "N2CU", band: .m15, modeClass: .cw, rawMode: "CW",
                rstSent: "", rstRcvd: "", nameSent: "TOM", nameRcvd: "BILL",
                myLoc: "TX", theirLoc: "NY"
            )
        ]
        let score = ScoreEngine.score(log: log, party: naqp)
        let slots = MultiplierRoster.slots(party: naqp, rule: naqp.multipliers.outState)
        let fifteen = try XCTUnwrap(slots.first { $0.scope == "15m" })
        XCTAssertTrue(score.multiplierKeys.contains(
            ScoreEngine.MultKey(multClass: .state, value: "NY", scope: fifteen.scope)
        ))
        let twenty = try XCTUnwrap(slots.first { $0.scope == "20m" })
        XCTAssertFalse(score.multiplierKeys.contains(
            ScoreEngine.MultKey(multClass: .state, value: "NY", scope: twenty.scope)
        ), "NY is still needed on 20m — that block stays empty")
    }

    // MARK: Cross-party accuracy guards

    /// Drive every roster token of every bundled party through the scorer.
    /// A token drawn but not credited is a promise the score will not keep.
    func testEveryRosterTokenIsCreditedByTheScorer() throws {
        for party in PartyCatalog.allParties() {
            for inState in [true, false] where sideIsReachable(party, inState: inState) {
                let rule = inState ? party.multipliers.inState : party.multipliers.outState
                for classRoster in MultiplierRoster.classes(party: party, rule: rule)
                where classRoster.isMultClass {
                    let entries = classRoster.entries.filter { !$0.granted }
                    let probes = entries.map {
                        exchangeEarning($0.token, classRoster.multClass, party, rule)
                    }
                    let score = ScoreEngine.score(
                        log: probeLog(party, inState: inState, theirLocs: probes),
                        party: party
                    )
                    let credited = score.workedValues(classRoster.multClass)
                    for entry in entries {
                        XCTAssertTrue(
                            credited.contains(entry.token),
                            """
                            \(party.id) \(inState ? "in-state" : "out-of-state"): roster \
                            lists \(classRoster.multClass) "\(entry.token)" but the scorer \
                            credits it nothing
                            """
                        )
                    }
                }
            }
        }
    }

    /// The reverse: drive every token a party will accept through the scorer,
    /// and require whatever it credits to be drawn somewhere. A multiplier the
    /// score holds but the roster omits is one the operator can never see
    /// coming — the DC-aliases-to-MD case is exactly this shape.
    func testEveryCreditedTokenAppearsInARoster() throws {
        for party in PartyCatalog.allParties() {
            for inState in [true, false] where sideIsReachable(party, inState: inState) {
                let rule = inState ? party.multipliers.inState : party.multipliers.outState
                let rosters = MultiplierRoster.classes(party: party, rule: rule)
                let probes = party.validOutStateTokens.union(party.counties.map(\.abbr)).sorted()
                let score = ScoreEngine.score(
                    log: probeLog(party, inState: inState, theirLocs: probes),
                    party: party
                )
                for key in score.multiplierKeys where key.multClass != .dx {
                    let drawn = rosters
                        .first { $0.multClass == key.multClass }?
                        .entries.contains { $0.token == key.value } ?? false
                    XCTAssertTrue(
                        drawn,
                        """
                        \(party.id) \(inState ? "in-state" : "out-of-state"): scorer credits \
                        \(key.multClass) "\(key.value)" but no roster draws it
                        """
                    )
                }
            }
        }
    }

    /// The exchange that earns `token` — normally the token itself, but a home
    /// state under `homeStateCountsViaCounty` is never *sent*: it is excluded
    /// as a token and credited only when a county inside it is worked. Probing
    /// it with the bare state token would test an exchange no station makes.
    func exchangeEarning(
        _ token: String,
        _ multClass: MultClass,
        _ party: PartyDefinition,
        _ rule: PartyDefinition.MultRule
    ) -> String {
        guard multClass == .state,
              rule.homeStateCountsViaCounty,
              party.excludedStateTokens.contains(token),
              let county = party.counties.first(where: { party.state(forCounty: $0.abbr) == token })
        else { return token }
        return county.abbr
    }

    /// A party with no home region is never logged as an in-state entrant, and
    /// a party whose counties are empty has no in-state location to claim.
    func sideIsReachable(_ party: PartyDefinition, inState: Bool) -> Bool {
        guard inState else { return true }
        return party.hasHomeRegion && !party.counties.isEmpty
    }

    /// One QSO per probed location, each with a distinct call so nothing is
    /// discarded as a dupe, on the party's first legal band and mode.
    func probeLog(
        _ party: PartyDefinition, inState: Bool, theirLocs: [String]
    ) -> ContestLog {
        var log = ContestLog(partyID: party.id)
        log.myLocation = inState
            ? .inState(counties: [party.counties[0].abbr])
            : .outOfState(location: entrantToken(party))
        log.station.callsign = "KE5CW"
        log.exchangeName = "TOM"
        let band = party.validBands[0]
        let mode = party.allowedModeClasses[0]
        log.qsos = theirLocs.enumerated().map { index, loc in
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_785_607_200 + Double(index) * 60),
                call: "K\(index % 10)PROBE\(index)",
                band: band, modeClass: mode,
                rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
                rstSent: "59", rstRcvd: "59",
                nameSent: "TOM", nameRcvd: "BILL",
                myLoc: inState ? party.counties[0].abbr : entrantToken(party),
                theirLoc: loc
            )
        }
        return log
    }

    /// Any location this party lets an entrant claim, DX aside.
    func entrantToken(_ party: PartyDefinition) -> String {
        party.validEntrantTokens
            .subtracting([MultClass.dxToken])
            .sorted()
            .first ?? "TX"
    }
}
