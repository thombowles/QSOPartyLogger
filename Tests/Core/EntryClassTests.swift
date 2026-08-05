import XCTest
@testable import QSOPartyLogger

/// Party-declared entry classes with exact score factors — the Skeeter
/// Hunt's X1–X4, whose 1/2/3/4 is not a product of the Cabrillo power and
/// station axes (portable homebrew would pay 6, the sponsor prints 4), so
/// the class is an irreducible self-declared choice stored on the log.
/// See docs/superpowers/specs/2026-08-04-skeeter-hunt-design.md.
///
/// **Party-free by design** (constitution Article 4): every party here is
/// synthetic.
final class EntryClassTests: XCTestCase {

    static let classesBlock = """
    ,"entryClasses":[
    {"id":"X1","label":"Home station, commercial equipment","factor":1},
    {"id":"X2","label":"Home station, home brewed or kit built","factor":2},
    {"id":"X3","label":"Portable station, commercial equipment","factor":3},
    {"id":"X4","label":"Portable station, home brewed or kit built","factor":4}]
    """

    func party(_ extra: String = "") throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"c","name":"C","cabrilloContest":"C","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}]\(extra)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(call: String, their: String) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: call, band: .m40, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: their
        )
    }

    func log(_ qsos: [QSO], classID: String = "") -> ContestLog {
        ContestLog(
            partyID: "c",
            station: StationProfile(),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            entryClassID: classID
        )
    }

    // MARK: Decode and resolution

    func testClassesDecodeWithExactFactors() throws {
        XCTAssertTrue(try party().entryClasses.isEmpty, "absent means none")
        let classes = try party(Self.classesBlock).entryClasses
        XCTAssertEqual(classes.map(\.id), ["X1", "X2", "X3", "X4"])
        XCTAssertEqual(classes.map(\.factor), [1, 2, 3, 4].map { ScoreFactor($0) })
    }

    /// An empty or stale id resolves to the **first** class — parties list
    /// them lowest-factor first, so a log that never chose cannot claim a
    /// multiplier the operator did not.
    func testResolutionFallsBackToTheFirstClass() throws {
        let party = try party(Self.classesBlock)
        XCTAssertEqual(party.resolvedEntryClass(id: "X3")?.id, "X3")
        XCTAssertEqual(party.resolvedEntryClass(id: "")?.id, "X1")
        XCTAssertEqual(party.resolvedEntryClass(id: "Q9")?.id, "X1")
        XCTAssertNil(try self.party().resolvedEntryClass(id: "X3"),
                     "a party with no classes resolves nothing")
    }

    func testEntryClassIDDefaultsEmptyAndRoundTrips() throws {
        let old = try ContestLog.decode(from: ContestLog(partyID: "ksqp").encoded())
        XCTAssertEqual(old.entryClassID, "")

        var log = ContestLog(partyID: "ksqp")
        log.entryClassID = "X4"
        let reopened = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(reopened.entryClassID, "X4")
    }

    /// The bundled parties declaring classes, named so a party cannot gain
    /// them incidentally — each gain is its own commit (Article 9). The
    /// Skeeter Hunt's X1–X4 is the first.
    func testWhichPartiesDeclareEntryClasses() {
        let withClasses = PartyCatalog.loadBundled()
            .filter { !$0.entryClasses.isEmpty }.map(\.id)
        XCTAssertEqual(withClasses, ["skeeter"])
    }

    // MARK: Scoring

    func testTheChosenClassMultipliesTheScore() throws {
        let party = try party(Self.classesBlock)
        let rows = [qso(call: "W1AW", their: "CT"), qso(call: "W2LJ", their: "NJ")]
        // 2 points × 2 state mults = 4, then the class factor.
        let x3 = ScoreEngine.score(log: log(rows, classID: "X3"), party: party)
        XCTAssertEqual(x3.categoryFactor, ScoreFactor(3))
        XCTAssertEqual(x3.total, 12)

        let unchosen = ScoreEngine.score(log: log(rows), party: party)
        XCTAssertEqual(unchosen.categoryFactor, ScoreFactor(1),
                       "an unchosen class is the lowest, never a guess upward")
        XCTAssertEqual(unchosen.total, 4)
    }

    /// A class factor composes with `scoreMultipliers` by multiplication —
    /// the same rule the power × station pair already follows.
    func testClassFactorComposesWithScoreMultipliers() throws {
        let party = try party(
            Self.classesBlock + #","scoreMultipliers":{"power":{"QRP":2}}"#)
        var station = StationProfile()
        station.categoryPower = .qrp
        var log = ContestLog(
            partyID: "c", station: station,
            myLocation: .outOfState(location: "TX"),
            qsos: [qso(call: "W1AW", their: "CT")]
        )
        log.entryClassID = "X4"
        let score = ScoreEngine.score(log: log, party: party)
        XCTAssertEqual(score.categoryFactor, ScoreFactor(8), "QRP ×2 × class ×4")
    }

    /// A party with no classes scores exactly as before (Article 4) — the
    /// stored id is inert.
    func testPartiesWithoutClassesIgnoreTheStoredID() throws {
        let party = try party()
        let score = ScoreEngine.score(
            log: log([qso(call: "W1AW", their: "CT")], classID: "X4"), party: party)
        XCTAssertEqual(score.categoryFactor, .one)
    }

    // MARK: The archive path

    /// The class factor rides the same `categoryFactor` the archive already
    /// persists — no schema change, exact round trip.
    func testSnapshotCarriesTheClassFactor() throws {
        let party = try party(Self.classesBlock)
        let contestLog = log([qso(call: "W1AW", their: "CT")], classID: "X2")
        let snapshot = ScoreSnapshot.make(log: contestLog, party: party)
        XCTAssertEqual(snapshot.figures?.categoryFactor, ScoreFactor(2))

        let data = try JSONEncoder().encode(snapshot)
        let reopened = try JSONDecoder().decode(ScoreSnapshot.self, from: data)
        XCTAssertEqual(reopened.figures?.categoryFactor, ScoreFactor(2))
    }
}
