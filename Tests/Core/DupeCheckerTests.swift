import XCTest
@testable import QSOPartyLogger

final class DupeCheckerTests: XCTestCase {

    func qso(
        call: String = "W0BH",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "MRN",
        t: TimeInterval = 0
    ) -> QSO {
        QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + t),
            call: call,
            band: band,
            modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: "599",
            rstRcvd: "599",
            myLoc: my,
            theirLoc: their
        )
    }

    func testExactRepeatIsDupe() {
        let a = qso(t: 0), b = qso(t: 60)
        let firsts = DupeChecker.firstOccurrenceIDs([a, b])
        XCTAssertEqual(firsts, [a.id], "first kept, repeat is dupe")
    }

    func testDifferentBandNotDupe() {
        let a = qso(band: .m20), b = qso(band: .m40, t: 60)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs([a, b]).count, 2)
    }

    func testDifferentModeClassNotDupe() {
        let a = qso(mode: .cw), b = qso(mode: .phone, t: 60)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs([a, b]).count, 2)
    }

    func testCountyChangeNotDupe() {
        // KSQP rule 10: mobile changed counties — new station.
        let a = qso(their: "MRN"), b = qso(their: "CHS", t: 60)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs([a, b]).count, 2)
    }

    func testMyCountyLineRowsNotDupes() {
        // I'm on a county line: same contact logged from each of my counties.
        let a = qso(my: "GRY", their: "MO"), b = qso(my: "FIN", their: "MO", t: 0)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs([a, b]).count, 2)
    }

    func testCaseInsensitiveCall() {
        let a = qso(call: "w0bh"), b = qso(call: "W0BH", t: 60)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs([a, b]).count, 1)
    }

    func testChronologyDecidesFirst() {
        let later = qso(t: 120), earlier = qso(t: 0)
        // Inserted out of order; the earlier timestamp wins.
        let firsts = DupeChecker.firstOccurrenceIDs([later, earlier])
        XCTAssertEqual(firsts, [earlier.id])
    }

    func testLivePairCheck() {
        let log = [qso(my: "TX", their: "LIN")]
        let dupes = DupeChecker.existingDupePairs(
            call: "W0BH", band: .m20, modeClass: .cw,
            myLocs: ["TX"], theirLocs: ["LIN", "AND"], log: log
        )
        XCTAssertEqual(dupes.count, 1)
        XCTAssertEqual(dupes[0].theirLoc, "LIN")
    }

    // MARK: Prior contacts with a call

    func testNoPriorContactsForACallNeverWorked() {
        let log = [qso(call: "W0BH")]
        XCTAssertTrue(DupeChecker.workedContacts(call: "K5NA", log: log).isEmpty)
    }

    func testCallMatchIsCaseInsensitiveAndTrimmed() {
        let log = [qso(call: "K5NA")]
        XCTAssertEqual(DupeChecker.workedContacts(call: " k5na ", log: log).count, 1)
    }

    /// A county-line contact is one contact that produced several rows. It is
    /// one entry, and it names both counties the way the parser accepts them.
    func testCountyLineGroupCollapsesToOneEntry() {
        let group = UUID()
        var a = qso(call: "K5NA", their: "JO"); a.groupID = group
        var b = qso(call: "K5NA", their: "MI", t: 1); b.groupID = group
        let entries = DupeChecker.workedContacts(call: "K5NA", log: [a, b])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].theirLoc, "JO/MI")
    }

    func testEntriesAreMostRecentFirst() {
        let early = qso(call: "K5NA", band: .m80, t: 0)
        let late = qso(call: "K5NA", band: .m20, t: 3600)
        let entries = DupeChecker.workedContacts(call: "K5NA", log: [early, late])
        XCTAssertEqual(entries.map(\.band), [.m20, .m80])
    }

    func testEntryCarriesBandModeAndTime() {
        let q = qso(call: "K5NA", band: .m40, mode: .phone, their: "JO")
        let entries = DupeChecker.workedContacts(call: "K5NA", log: [q])
        XCTAssertEqual(entries.first?.band, .m40)
        XCTAssertEqual(entries.first?.modeClass, .phone)
        XCTAssertEqual(entries.first?.timestampUTC, q.timestampUTC)
        XCTAssertEqual(entries.first?.theirLoc, "JO")
    }
}
