import XCTest
@testable import QSOPartyLogger

/// What the app already knows a station sends, and where it learned it.
///
/// The rule that matters: a county means nothing outside the party that
/// defines it. Colorado and Kansas both abbreviate Jefferson County `JEF`, so a
/// Colorado exchange parses perfectly as a Kansas county — and is still wrong,
/// because he was in Colorado. Removing the county check makes
/// `testCountyFromAnotherPartyIsNeverOffered` offer exactly that.
final class StationMemoryTests: XCTestCase {

    var ksqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"), "bundled KSQP should load")
    }

    /// The snapshot is irrelevant here, but `ContestRecord` requires one.
    let emptySnapshot = ScoreSnapshot(
        validQSOs: 0, dupeCount: 0, invalidModeCount: 0, outOfScopeCount: 0,
        qsosByMode: [:], qsosByBand: [:], countiesWorked: 0,
        operatingMinutes: 0, figures: nil
    )

    func qso(
        call: String, their: String, band: Band = .m20, t: TimeInterval = 0
    ) -> QSO {
        QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + t),
            call: call, band: band, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: their
        )
    }

    func entry(
        call: String, loc: String, party: String, year: Int,
        county: Bool, t: TimeInterval = 0
    ) -> StationMemory.ArchiveEntry {
        StationMemory.ArchiveEntry(
            call: call, theirLoc: loc, partyID: party, year: year,
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + t),
            isCountyOfItsParty: county
        )
    }

    // MARK: Candidate order

    func testNothingKnownYieldsNoCandidate() {
        XCTAssertNil(
            StationMemory.candidate(
                call: "K5NA", log: [], index: .empty,
                party: ksqp, role: .outOfState
            )
        )
    }

    func testThisLogWins() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "MIA", party: "ksqp", year: 2025, county: true)]
        ])
        let candidate = StationMemory.candidate(
            call: "K5NA", log: [qso(call: "K5NA", their: "JOH")],
            index: index, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(candidate?.text, "JOH")
        XCTAssertEqual(candidate?.source, .thisLog)
    }

    func testMostRecentContactInThisLogWins() {
        let log = [
            qso(call: "K5NA", their: "JOH", t: 0),
            qso(call: "K5NA", their: "MIA", t: 3600),
        ]
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: log, index: .empty,
                party: ksqp, role: .outOfState
            )?.text,
            "MIA"
        )
    }

    /// Same sponsor, so a county from a previous year still means something.
    func testSamePartyCountyIsOffered() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "JOH", party: "ksqp", year: 2025, county: true)]
        ])
        let candidate = StationMemory.candidate(
            call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(candidate?.text, "JOH")
        XCTAssertEqual(candidate?.source, .archive(partyID: "ksqp", year: 2025))
    }

    /// The rule the whole archive fallback rests on — and this fixture is why
    /// the parse guard is not enough on its own. Colorado and Kansas both
    /// abbreviate Jefferson County `JEF`, so a Colorado exchange parses
    /// perfectly as a Kansas county. He was in Colorado.
    func testCountyFromAnotherPartyIsNeverOffered() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "JEF", party: "coqp", year: 2025, county: true)]
        ])
        XCTAssertNil(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
            )
        )
    }

    /// A state is stable across sponsors — he is in Texas whoever is running
    /// the contest. Read from a Kansas station's seat, because an out-of-state
    /// KSQP entrant works Kansas stations only and cannot receive a state at all.
    func testStateFromAnotherPartyIsOffered() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "TX", party: "alqp", year: 2025, county: false)]
        ])
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .inState
            )?.text,
            "TX"
        )
    }

    /// The guard behind everything else: whatever the source, the current
    /// party's own parser has the last word.
    func testCandidateThatDoesNotParseIsSkipped() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [
                entry(call: "K5NA", loc: "ZZZZ", party: "alqp", year: 2026, county: false, t: 100),
                entry(call: "K5NA", loc: "TX", party: "alqp", year: 2025, county: false, t: 0),
            ]
        ])
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .inState
            )?.text,
            "TX",
            "the unparseable newer entry is skipped, not fatal"
        )
    }

    func testNewerArchiveYearWins() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [
                entry(call: "K5NA", loc: "MIA", party: "ksqp", year: 2026, county: true, t: 100),
                entry(call: "K5NA", loc: "JOH", party: "ksqp", year: 2025, county: true, t: 0),
            ]
        ])
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
            )?.text,
            "MIA"
        )
    }

    // MARK: Index

    func testIndexKeysByUppercasedCallNewestFirst() {
        let record = ContestRecord(
            partyID: "ksqp", year: 2025, callsign: "KE5CW",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: [
                qso(call: "k5na", their: "JOH", t: 0),
                qso(call: "K5NA", their: "MIA", t: 3600),
            ],
            snapshot: emptySnapshot, updatedAt: Date(), sourceFileName: nil
        )
        let index = StationMemory.Index.build(
            ContestArchive(records: [record]),
            countiesByParty: ["ksqp": ["JOH", "MIA"]]
        )
        let entries = index.entries(for: "K5NA")
        XCTAssertEqual(entries.map(\.theirLoc), ["MIA", "JOH"])
        XCTAssertTrue(entries.allSatisfy(\.isCountyOfItsParty))
    }

    func testIndexMarksNonCountyLocations() {
        let record = ContestRecord(
            partyID: "ksqp", year: 2025, callsign: "KE5CW",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .inState(counties: ["JO"]),
            qsos: [qso(call: "W1ABC", their: "MA")],
            snapshot: emptySnapshot, updatedAt: Date(), sourceFileName: nil
        )
        let index = StationMemory.Index.build(
            ContestArchive(records: [record]),
            countiesByParty: ["ksqp": ["JOH", "MIA"]]
        )
        XCTAssertEqual(index.entries(for: "W1ABC").first?.isCountyOfItsParty, false)
    }
}
