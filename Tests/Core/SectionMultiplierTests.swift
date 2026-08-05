import XCTest
@testable import QSOPartyLogger

/// ARRL/RAC section multipliers, and multipliers a party grants outright.
///
/// PAQP: "Sequential serial number plus PA county, ARRL section, Canadian
/// section, or 'DX'" — so a section party's non-county tokens are its 85
/// sections, and the state/province tables do not apply at all. See
/// docs/research/paqp_rules.md §6 and §14.
final class SectionMultiplierTests: XCTestCase {

    /// A stand-in section party, so the capability is tested before any bundled
    /// party uses it. Deliberately small: three US sections, two Canadian.
    func sectionParty(
        classes: [MultClass] = [.county, .section, .dx],
        countScope: String = "once",
        dxMultCap: String = "",
        granted: String = "",
        outClasses: [MultClass] = [.county]
    ) throws -> PartyDefinition {
        func list(_ cs: [MultClass]) -> String {
            "[" + cs.map { "\"\($0.rawValue)\"" }.joined(separator: ",") + "]"
        }
        let json = """
        {"schemaVersion":1,"id":"sect","name":"Section Party","cabrilloContest":"SECT",
        "homeState":"PA","countyAbbrLength":3,"validBands":["40m"],
        "points":{"phone":1,"cw":2,"digital":2},"dupeScope":"bandMode",
        "multipliers":{
          "inState":{"classes":\(list(classes)),"homeStateCountsViaCounty":false,
                     "countScope":"\(countScope)"\(dxMultCap)\(granted)},
          "outState":{"classes":\(list(outClasses)),"homeStateCountsViaCounty":false,
                      "countScope":"once"}},
        "bonuses":[],"exchangeIncludesRST":false,"exchangeIncludesSerial":true,
        "sections":["EMA","NTX","SCV","ONE","TER"],
        "counties":[{"abbr":"ADA","name":"Adams"},{"abbr":"BUX","name":"Bucks"},
                    {"abbr":"LEH","name":"Lehigh"}]}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W3ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "NTX",
        their: String = "ADA"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_600_000 + seq),
            call: call, band: band, modeClass: mode, rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: "", rstRcvd: "", serialSent: 1, serialRcvd: 1,
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ party: PartyDefinition, _ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: party.id)
        log.myLocation = .outOfState(location: "NTX")
        log.qsos = qsos
        return log
    }

    func inLog(_ party: PartyDefinition, _ qsos: [QSO], from county: String = "ADA") -> ContestLog {
        var log = ContestLog(partyID: party.id)
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Sections supplant states and provinces

    func testSectionsAreTheOnlyNonCountyTokens() throws {
        let party = try sectionParty()
        XCTAssertTrue(party.usesSections)
        XCTAssertEqual(party.sections, ["EMA", "NTX", "SCV", "ONE", "TER"])

        for token in ["EMA", "NTX", "SCV", "ONE", "TER"] {
            XCTAssertTrue(party.validOutStateTokens.contains(token), token)
        }
        // The states and provinces a non-section party would accept are gone.
        for token in ["TX", "MA", "CA", "NY", "ON", "NL", "NT", "DC"] {
            XCTAssertFalse(party.validOutStateTokens.contains(token),
                           "'\(token)' must not be valid in a section party")
        }
        XCTAssertTrue(party.validOutStateTokens.contains("DX"), "token-style DX still applies")
    }

    func testExchangeParserAcceptsSectionsAndRejectsStates() throws {
        let party = try sectionParty()
        XCTAssertEqual(try ExchangeParser.parse("ntx", party: party, role: .inState).get().locations, ["NTX"])
        XCTAssertEqual(try ExchangeParser.parse("EMA", party: party, role: .inState).get().locations, ["EMA"])
        XCTAssertEqual(try ExchangeParser.parse("TER", party: party, role: .inState).get().locations, ["TER"])
        XCTAssertEqual(try ExchangeParser.parse("ADA", party: party, role: .inState).get().locations, ["ADA"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: party, role: .inState).get().locations, ["DX"])
        for bad in ["TX", "MA", "ON", "PA"] {
            guard case .failure = ExchangeParser.parse(bad, party: party, role: .inState) else {
                return XCTFail("'\(bad)' is a state/province code, not a section")
            }
        }
    }

    func testSectionsScoreAsTheirOwnClass() throws {
        let party = try sectionParty()
        let s = ScoreEngine.score(log: inLog(party, [
            qso(call: "W1A", my: "ADA", their: "EMA"),
            qso(call: "W6B", my: "ADA", their: "SCV"),
            qso(call: "VE3C", my: "ADA", their: "ONE"),
        ]), party: party)
        XCTAssertEqual(s.workedValues(.section), ["EMA", "SCV", "ONE"])
        XCTAssertEqual(s.workedValues(.state), [], "no state class in a section party")
        XCTAssertEqual(s.workedValues(.province), [])
        XCTAssertEqual(s.classCounts[.section], 3)
        XCTAssertEqual(s.multiplierCount, 3)
    }

    /// A token that is neither a county nor a listed section earns nothing, even
    /// though it would be a perfectly good state code elsewhere.
    func testUnlistedTokensEarnNothing() throws {
        let party = try sectionParty()
        var row = qso(call: "K5X", their: "TX")
        row.theirLoc = "TX"
        let s = ScoreEngine.score(log: inLog(party, [row]), party: party)
        XCTAssertEqual(s.multiplierCount, 0)
    }

    /// Under prefix-style DX a section token must not be mistaken for a prefix.
    func testSectionTokensAreNotDXPrefixes() throws {
        let json = """
        {"schemaVersion":1,"id":"sp","name":"S","cabrilloContest":"S","homeState":"PA",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":2,"digital":2},
        "dupeScope":"bandMode","dxStyle":"prefix",
        "multipliers":{"inState":{"classes":["section","dx"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"sections":["EMA","NTX","SCV"],
        "counties":[{"abbr":"ADA","name":"Adams"}]}
        """
        let party = try PartyCatalog.decode(Data(json.utf8))
        XCTAssertFalse(party.isDXPrefix("EMA"), "EMA is a section, not Germany")
        XCTAssertFalse(party.isDXPrefix("NTX"))
        XCTAssertTrue(party.isDXPrefix("DL"))
        // And the ARRL list is what decides, so a section-shaped token that is
        // not in it fails for that reason rather than by luck of its length.
        XCTAssertFalse(party.isDXPrefix("SCV"))
        XCTAssertFalse(party.isDXPrefix("ZZZ"))
    }

    // MARK: Multipliers granted outright

    /// PAQP 12.d: "EPA and WPA multipliers are automatically added during the
    /// rescore process – there is no need to enter them."
    func testGrantedMultipliersCountWithoutBeingWorked() throws {
        let granted = """
        ,"grantedMultipliers":[{"multClass":"section","value":"EPA"},
                               {"multClass":"section","value":"WPA"}]
        """
        let party = try sectionParty(granted: granted)
        XCTAssertEqual(
            party.multipliers.inState.granted,
            [.init(multClass: .section, value: "EPA"), .init(multClass: .section, value: "WPA")]
        )

        // An empty log already has them.
        let empty = ScoreEngine.score(log: inLog(party, []), party: party)
        XCTAssertEqual(empty.workedValues(.section), ["EPA", "WPA"])
        XCTAssertEqual(empty.multiplierCount, 2)
        XCTAssertEqual(empty.total, 0, "no QSO points yet, so no score")

        // And they add to, rather than replace, what is worked.
        let worked = ScoreEngine.score(log: inLog(party, [
            qso(call: "W1A", my: "ADA", their: "EMA"),
        ]), party: party)
        XCTAssertEqual(worked.workedValues(.section), ["EPA", "WPA", "EMA"])
        XCTAssertEqual(worked.multiplierCount, 3)
        XCTAssertEqual(worked.total, 2 * 3, "2 CW points × 3 multipliers")
    }

    /// The grant is per side: an out-of-state entrant whose classes exclude
    /// sections must not receive them.
    func testGrantedMultipliersOnlyApplyToTheSideThatCountsThatClass() throws {
        let granted = """
        ,"grantedMultipliers":[{"multClass":"section","value":"EPA"},
                               {"multClass":"section","value":"WPA"}]
        """
        let party = try sectionParty(granted: granted)
        let out = ScoreEngine.score(log: outLog(party, [qso(their: "ADA")]), party: party)
        XCTAssertEqual(out.workedValues(.section), [],
                       "out-of-state counts counties only — no free sections")
        XCTAssertEqual(out.multiplierCount, 1)
    }

    func testGrantedMultipliersAreCountedOnceNotPerBandOrMode() throws {
        let granted = """
        ,"grantedMultipliers":[{"multClass":"section","value":"EPA"}]
        """
        let party = try sectionParty(countScope: "perMode", granted: granted)
        let s = ScoreEngine.score(log: inLog(party, [
            qso(call: "W1A", mode: .cw, my: "ADA", their: "EMA"),
            qso(call: "W1A", mode: .phone, my: "ADA", their: "EMA"),
        ]), party: party)
        XCTAssertEqual(s.workedValues(.section), ["EPA", "EMA"])
        XCTAssertEqual(
            s.multiplierCount, 3,
            "EMA once per mode = 2, plus EPA granted once — the grant is not per mode"
        )
    }

    func testNoGrantedMultipliersByDefault() throws {
        let party = try sectionParty()
        XCTAssertTrue(party.multipliers.inState.granted.isEmpty)
        XCTAssertEqual(ScoreEngine.score(log: inLog(party, []), party: party).multiplierCount, 0)
    }

    /// "+ 1 DX" — the tightest DX cap in the repo, and the token-style exchange
    /// collapses every DX station to one multiplier anyway.
    func testSingleDXCapWithSections() throws {
        let party = try sectionParty(dxMultCap: ",\"dxMultCap\":1")
        XCTAssertEqual(party.multipliers.inState.dxMultCap, 1)
        let s = ScoreEngine.score(log: inLog(party, [
            qso(call: "DL1A", my: "ADA", their: "DX"),
            qso(call: "JA1B", my: "ADA", their: "DX"),
        ]), party: party)
        XCTAssertEqual(s.validQSOs, 2, "both are valid QSOs worth points")
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Every existing party is untouched

    /// Exactly one bundled party counts sections; every other must opt in
    /// deliberately, not incidentally.
    func testOnlyPAQPUsesSections() throws {
        var sectionParties: Set<String> = []
        var grantParties: Set<String> = []
        for id in PartyCatalog.loadBundled().map(\.id) {
            let party = try XCTUnwrap(PartyCatalog.party(id: id))
            if party.usesSections { sectionParties.insert(id) }
            if !party.multipliers.inState.granted.isEmpty
                || !party.multipliers.outState.granted.isEmpty { grantParties.insert(id) }
            XCTAssertTrue(party.multipliers.outState.granted.isEmpty,
                          "\(id): nothing is granted to an out-of-state entrant")
        }
        XCTAssertEqual(sectionParties, ["paqp"])
        XCTAssertEqual(grantParties, ["paqp"])
    }

    /// A non-section party's tokens keep resolving exactly as before — the new
    /// branch must be unreachable for them.
    func testNonSectionPartiesResolveStatesAsBefore() throws {
        let nhqp = try XCTUnwrap(PartyCatalog.party(id: "nhqp"))
        XCTAssertEqual(try ExchangeParser.parse("TX", party: nhqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("ON", party: nhqp, role: .inState).get().locations, ["ON"])
        guard case .failure = ExchangeParser.parse("NTX", party: nhqp, role: .inState) else {
            return XCTFail("NTX is a section and means nothing in NHQP")
        }
    }

    func testSectionIsACaseOfMultClassAndRoundTrips() throws {
        XCTAssertTrue(MultClass.allCases.contains(.section))
        let data = try JSONEncoder().encode(MultClass.section)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"section\"")
        XCTAssertEqual(try JSONDecoder().decode(MultClass.self, from: data), .section)
    }
}
