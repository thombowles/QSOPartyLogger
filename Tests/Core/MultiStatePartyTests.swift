import XCTest
@testable import QSOPartyLogger

/// The multi-state schema, added 2026-07-26 for the two regional parties where
/// **one log covers every member state** — the 7th Call Area's seven and New
/// England's six. Requirement set by KE5CW:
///
/// > "I should be able to log all states on the 7qp in a single log. Same for
/// > NEQP."
///
/// Three optional fields carry it: `County.state`, `PartyDefinition.homeStates`
/// and `inStateLabel`. All three default so that **every existing party is
/// unchanged**, which is what `testEveryBundledPartyIsUntouched` proves.
///
/// This file ships no party. The 7QP and NEQP definitions come next, each in
/// its own commit (Article 9).
final class MultiStatePartyTests: XCTestCase {

    // MARK: The Article 4 proof

    /// The parties that are deliberately multi-state. Everything else must still
    /// resolve exactly as it did before this schema existed, and a party joining
    /// this set is a decision, never an accident — which is why the list is
    /// asserted rather than derived.
    static let multiState: Set<String> = ["sevenqp"]

    func testOnlyTheIntendedPartiesAreMultiState() {
        let actual = Set(PartyCatalog.loadBundled()
            .filter { $0.homeStates.count > 1 }
            .map(\.id))
        XCTAssertEqual(actual, Self.multiState)
    }

    /// Every party that was correct before this change still resolves exactly as
    /// it did: one home state, no county carrying its own, and the same
    /// excluded-token list the old `[homeState]` default produced.
    func testEverySingleStatePartyIsUntouched() throws {
        let bundled = PartyCatalog.loadBundled().filter { !Self.multiState.contains($0.id) }
        XCTAssertGreaterThan(bundled.count, 30, "sanity — the catalog loaded")

        for party in bundled {
            XCTAssertEqual(party.homeStates, [party.homeState],
                           "\(party.id) should still have exactly one home state")
            XCTAssertEqual(party.inStateLabel, party.homeState,
                           "\(party.id)'s setup sheet should read as before")
            XCTAssertTrue(party.counties.allSatisfy { $0.state == nil },
                          "\(party.id) is single-state; no county should name one")
            for county in party.counties {
                XCTAssertEqual(party.state(forCounty: county.abbr), party.homeState,
                               "\(party.id)/\(county.abbr) must resolve to the party's state")
            }
        }
    }

    /// The excluded-token default moved from `[homeState]` to `homeStates`.
    /// For a single-state party those are the same list, and the two parties
    /// that override it must still override it.
    func testTheExcludedTokenDefaultDidNotMoveForAnyoneElse() throws {
        for party in PartyCatalog.loadBundled()
        where !["mdc", "njqp"].contains(party.id) && !Self.multiState.contains(party.id) {
            XCTAssertEqual(party.excludedStateTokens, [party.homeState], party.id)
        }
        let mdc = try XCTUnwrap(PartyCatalog.party(id: "mdc"))
        XCTAssertEqual(mdc.excludedStateTokens, ["MD", "DC"], "still overridden")
        let njqp = try XCTUnwrap(PartyCatalog.party(id: "njqp"))
        XCTAssertEqual(njqp.excludedStateTokens, ["NJ", "DC"])
    }

    /// A county decoded from a file with no `state` key keeps `nil` — the
    /// schema is additive, so every party JSON already on disk still decodes.
    func testACountyWithoutAStateKeyDecodesToNil() throws {
        let c = try JSONDecoder().decode(
            County.self, from: Data(#"{"abbr":"ADA","name":"Ada"}"#.utf8))
        XCTAssertNil(c.state)
        XCTAssertEqual(c.abbr, "ADA")
    }

    // MARK: The new shape, on a synthetic two-state party

    /// Two states, four counties, built through the decoder rather than a
    /// memberwise initialiser — which is the path a user-installed file takes.
    static func twoStateParty(
        homeState: String? = nil,
        homeStates: [String] = ["ID", "MT"],
        label: String = "the test region",
        counties: String = """
            [{"abbr":"ADA","name":"Ada","state":"ID"},
             {"abbr":"CAN","name":"Canyon","state":"ID"},
             {"abbr":"CAS","name":"Cascade","state":"MT"},
             {"abbr":"LEW","name":"Lewis and Clark","state":"MT"}]
            """
    ) throws -> PartyDefinition {
        let json = """
        {
          "schemaVersion": 1, "id": "testregion", "name": "Test Region QSO Party",
          "cabrilloContest": "TEST-QSO-PARTY",
          "homeState": "\(homeState ?? homeStates[0])",
          "homeStates": [\(homeStates.map { "\"\($0)\"" }.joined(separator: ", "))],
          "inStateLabel": "\(label)",
          "countyAbbrLength": 3,
          "validBands": ["20m", "40m"],
          "points": {"phone": 1, "cw": 2, "digital": 0},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState": {"classes": ["county", "state"],
                        "homeStateCountsViaCounty": true, "countScope": "once"},
            "outState": {"classes": ["county"],
                         "homeStateCountsViaCounty": false, "countScope": "once"}
          },
          "bonuses": [],
          "allowedModes": ["phone", "cw"],
          "counties": \(counties)
        }
        """
        let party = try JSONDecoder().decode(PartyDefinition.self, from: Data(json.utf8))
        try party.validate()
        return party
    }

    func testTheCountysOwnStateResolves() throws {
        let party = try Self.twoStateParty()
        XCTAssertEqual(party.homeStates, ["ID", "MT"])
        XCTAssertEqual(party.state(forCounty: "ADA"), "ID")
        XCTAssertEqual(party.state(forCounty: "LEW"), "MT")
        XCTAssertEqual(party.state(forCounty: "ada"), "ID", "case-insensitive")
        XCTAssertEqual(party.state(forCounty: "NOPE"), "ID",
                       "an unknown county falls back to the primary state")
    }

    /// **No member state is a loggable token.** A station in any of them sends a
    /// county, so `ID` and `MT` are both out — which the old `[homeState]`
    /// default could not express.
    func testEveryMemberStateIsExcludedFromTheTokenSet() throws {
        let party = try Self.twoStateParty()
        XCTAssertEqual(party.excludedStateTokens, ["ID", "MT"])
        for token in ["ID", "MT"] {
            XCTAssertFalse(party.validOutStateTokens.contains(token))
            guard case .failure = ExchangeParser.parse(token, party: party, role: .inState) else {
                return XCTFail("\(token) must be rejected — its stations send counties")
            }
        }
        XCTAssertTrue(party.validOutStateTokens.contains("TX"))
    }

    /// The state credited through a county is **the county's own**, so one log
    /// can earn Idaho and Montana as separate multipliers.
    func testStateCreditFollowsTheCountyNotTheParty() throws {
        let party = try Self.twoStateParty()
        var log = ContestLog(partyID: party.id)
        log.myLocation = .inState(counties: ["ADA"])
        log.qsos = [
            qso(call: "W7A", their: "ADA"),
            qso(call: "W7B", their: "CAN"),
            qso(call: "W7C", their: "LEW"),
        ]
        let s = ScoreEngine.score(log: log, party: party)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(Set(s.workedValues(.county)), ["ADA", "CAN", "LEW"])
        XCTAssertEqual(Set(s.workedValues(.state)), ["ID", "MT"],
                       "two Idaho counties give one ID; the Montana one gives MT")
        XCTAssertEqual(s.multiplierCount, 5)
    }

    /// ADIF writes each QSO's county against **its own** state, so a 7QP log
    /// does not claim every contact was in the primary one.
    func testADIFWritesTheCountysStateOnBothSides() throws {
        let party = try Self.twoStateParty()
        var log = ContestLog(partyID: party.id)
        log.station.callsign = "W7TEST"
        log.myLocation = .inState(counties: ["LEW"])
        log.qsos = [qso(call: "W7A", my: "LEW", their: "ADA")]

        let adif = AdifExporter.export(log: log, party: party)
        XCTAssertTrue(adif.contains("<cnty:6>ID,Ada"), "their county is in Idaho")
        XCTAssertTrue(adif.contains("<state:2>ID"))
        XCTAssertTrue(adif.contains("<my_cnty:18>MT,Lewis and Clark"), "mine is in Montana")
        XCTAssertTrue(adif.contains("<my_state:2>MT"))
    }

    /// A single-state party's ADIF is byte-for-byte what it was — the same
    /// export path, exercised through a party that names no county states.
    func testADIFIsUnchangedForASingleStateParty() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        var log = ContestLog(partyID: "alqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let county = try XCTUnwrap(alqp.counties.first)
        log.qsos = [qso(call: "W4A", my: "TX", their: county.abbr)]

        let adif = AdifExporter.export(log: log, party: alqp)
        XCTAssertTrue(adif.contains("<state:2>AL"))
        XCTAssertTrue(adif.contains("AL,\(county.name)"))
    }

    func testTheSetupSheetPhrase() throws {
        let party = try Self.twoStateParty(label: "the 7th call area")
        XCTAssertEqual(party.inStateLabel, "the 7th call area")
    }

    // MARK: Validation

    /// A county may not name a state the party does not cover, or the ADIF
    /// export and the state credit would both name a state nobody can work.
    func testACountyCannotNameAStateOutsideTheParty() {
        XCTAssertThrowsError(try Self.twoStateParty(counties: """
            [{"abbr":"ADA","name":"Ada","state":"ID"},
             {"abbr":"XXX","name":"Elsewhere","state":"CA"}]
            """)) { error in
            guard case PartyValidationError.badHomeState(let s) = error else {
                return XCTFail("expected badHomeState, got \(error)")
            }
            XCTAssertEqual(s, "CA")
        }
    }

    /// The primary state has to be one of the member states, or the Cabrillo
    /// `LOCATION:` header would name a state the party does not cover.
    func testHomeStateMustBeAmongTheHomeStates() {
        XCTAssertThrowsError(try Self.twoStateParty(
            homeState: "TX", homeStates: ["ID", "MT"], counties: """
            [{"abbr":"ADA","name":"Ada","state":"ID"}]
            """)) { error in
            guard case PartyValidationError.badHomeState(let s) = error else {
                return XCTFail("expected badHomeState, got \(error)")
            }
            XCTAssertEqual(s, "TX")
        }
        // …and the well-formed case does not throw, which the helper already
        // asserts by calling validate() on every party it builds.
        XCTAssertNoThrow(try Self.twoStateParty())
    }

    func testEveryHomeStateMustBeTwoCharacters() {
        XCTAssertThrowsError(try Self.twoStateParty(homeStates: ["ID", "MONT"], counties: """
            [{"abbr":"ADA","name":"Ada","state":"ID"}]
            """))
    }

    // MARK: Helper

    private var seq: TimeInterval = 0
    private func qso(
        call: String, band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_132_800 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .cw ? "CW" : "SSB",
            rstSent: "599", rstRcvd: "599", myLoc: my, theirLoc: their
        )
    }
}
