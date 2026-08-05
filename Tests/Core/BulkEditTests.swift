import XCTest
@testable import QSOPartyLogger

/// One field changed across a selection — what it writes, what it refuses, and
/// the county-line rows it must leave alone.
final class BulkEditTests: XCTestCase {

    var ksqp: PartyDefinition!
    var skeeter: PartyDefinition!
    var naqpCW: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        skeeter = try XCTUnwrap(PartyCatalog.party(id: "skeeter"))
        naqpCW = try XCTUnwrap(PartyCatalog.party(id: "naqpcw"))
    }

    func qso(
        call: String = "W1AW",
        band: Band = .m40,
        rawMode: String = "CW",
        modeClass: ModeClass = .cw,
        myLoc: String = "JOH",
        theirLoc: String = "TX",
        groupID: UUID = UUID(),
        nameSent: String? = nil,
        memberSent: String? = nil
    ) -> QSO {
        QSO(
            groupID: groupID, call: call, band: band, modeClass: modeClass,
            rawMode: rawMode, rstSent: "599", rstRcvd: "599",
            nameSent: nameSent, memberSent: memberSent,
            myLoc: myLoc, theirLoc: theirLoc
        )
    }

    // MARK: Which fields a party offers

    func testEveryPartyOffersBandModeAndMyLocation() {
        XCTAssertEqual(BulkEdit.fields(for: ksqp), [.band, .mode, .myLoc])
    }

    /// The sent elements appear only where the exchange carries them, so a
    /// KSQP operator is never offered a "Name sent" the rules have no room for.
    func testNamePartyAlsoOffersTheSentName() {
        XCTAssertEqual(BulkEdit.fields(for: naqpCW), [.band, .mode, .myLoc, .nameSent])
    }

    func testMemberPartyAlsoOffersItsOwnElement() {
        XCTAssertEqual(BulkEdit.fields(for: skeeter), [.band, .mode, .myLoc, .memberSent])
        XCTAssertEqual(
            BulkEdit.label(.memberSent, party: skeeter),
            "\(skeeter.memberExchange!.shortTerm) sent"
        )
    }

    // MARK: What a change writes

    func testBandAppliesToEverySelectedRow() throws {
        let rows = [qso(band: .m40), qso(band: .m80), qso(band: .m40)]
        let updated = try apply(.band(.m20), field: .band, to: rows)
        XCTAssertEqual(updated.map(\.band), [.m20, .m20, .m20])
    }

    /// A mode change has to move `modeClass` with `rawMode` — the score is
    /// computed from the class, so a row left on the old one would keep paying
    /// CW points for a phone contact.
    func testModeChangeCarriesTheModeClass() throws {
        let rows = [qso(rawMode: "CW", modeClass: .cw), qso(rawMode: "CW", modeClass: .cw)]
        let updated = try apply(.mode("SSB"), field: .mode, to: rows)
        XCTAssertEqual(updated.map(\.rawMode), ["SSB", "SSB"])
        XCTAssertEqual(updated.map(\.modeClass), [.phone, .phone])
    }

    func testMyLocationAppliesUppercasedAndTrimmed() throws {
        let rows = [qso(myLoc: "JOH"), qso(myLoc: "JOH")]
        let updated = try apply(.text("  mia "), field: .myLoc, to: rows)
        XCTAssertEqual(updated.map(\.myLoc), ["MIA", "MIA"])
    }

    func testSentNameApplies() throws {
        let rows = [qso(nameSent: "TOM"), qso(nameSent: "TOM")]
        let updated = try apply(.text("tomas"), field: .nameSent, to: rows, party: naqpCW)
        XCTAssertEqual(updated.map(\.nameSent), ["TOMAS", "TOMAS"])
    }

    func testSentMemberElementApplies() throws {
        let rows = [qso(memberSent: "5W")]
        let updated = try apply(.text("13"), field: .memberSent, to: rows, party: skeeter)
        XCTAssertEqual(updated.map(\.memberSent), ["13"])
    }

    // MARK: What a change refuses — nothing written

    func testAnUnknownCountyIsRefused() {
        let result = BulkEdit.apply(
            .text("ZZZ"), field: .myLoc, to: [qso()], party: ksqp, isInState: true
        )
        XCTAssertThrowsFailure(result)
    }

    /// An in-state entrant transmits from a county, never from a state — and
    /// `ExchangeParser`'s in-state role accepts every state token in the
    /// party's table, which is why my own location is not validated with it.
    func testAnInStateLogRefusesAStateTokenAsMyLocation() {
        let result = BulkEdit.apply(
            .text("TX"), field: .myLoc, to: [qso()], party: ksqp, isInState: true
        )
        XCTAssertThrowsFailure(result)
    }

    func testAnOutOfStateLogAcceptsItsOwnEntrantToken() throws {
        let updated = try apply(
            .text("TX"), field: .myLoc, to: [qso(myLoc: "OK")], party: ksqp, isInState: false
        )
        XCTAssertEqual(updated.map(\.myLoc), ["TX"])
    }

    func testAnEmptyValueIsRefused() {
        XCTAssertThrowsFailure(
            BulkEdit.apply(.text("   "), field: .myLoc, to: [qso()], party: ksqp, isInState: true)
        )
        XCTAssertThrowsFailure(
            BulkEdit.apply(.text(""), field: .nameSent, to: [qso()], party: naqpCW, isInState: false)
        )
    }

    /// "Fifty watts" is not something the other station can copy. A member
    /// element must read as a number or a power.
    func testAnUnreadableMemberElementIsRefused() {
        XCTAssertThrowsFailure(
            BulkEdit.apply(
                .text("LOTS"), field: .memberSent, to: [qso()],
                party: skeeter, isInState: false
            )
        )
    }

    // MARK: The county-line guard

    /// Two rows of one contact, differing only in which of my counties they
    /// carry. Collapsing them onto one location would leave two identical rows
    /// for the dupe checker to flag — so the change skips them and says so.
    func testCountyLineRowsAreExcludedFromAMyLocationChange() {
        let group = UUID()
        let rows = [
            qso(myLoc: "JOH", theirLoc: "TX", groupID: group),
            qso(myLoc: "MIA", theirLoc: "TX", groupID: group),
        ]
        let partition = BulkEdit.partition(rows, field: .myLoc, allRows: rows)
        XCTAssertTrue(partition.changing.isEmpty)
        XCTAssertEqual(partition.excluded.count, 2)
    }

    /// The other county line: I am in one county, *they* straddle two. The rows
    /// stay distinct by what the other station sent, so there is nothing to
    /// protect and the whole selection changes.
    func testTheirCountyLineRowsAreNotExcluded() {
        let group = UUID()
        let rows = [
            qso(myLoc: "JOH", theirLoc: "AND", groupID: group),
            qso(myLoc: "JOH", theirLoc: "LIN", groupID: group),
        ]
        let partition = BulkEdit.partition(rows, field: .myLoc, allRows: rows)
        XCTAssertEqual(partition.changing.count, 2)
        XCTAssertTrue(partition.excluded.isEmpty)
    }

    /// Half a contact's rows selected: changing them would leave one on-air
    /// contact claiming two of my locations.
    func testAPartlySelectedGroupIsExcluded() {
        let group = UUID()
        let all = [
            qso(myLoc: "JOH", theirLoc: "AND", groupID: group),
            qso(myLoc: "JOH", theirLoc: "LIN", groupID: group),
        ]
        let partition = BulkEdit.partition([all[0]], field: .myLoc, allRows: all)
        XCTAssertTrue(partition.changing.isEmpty)
        XCTAssertEqual(partition.excluded.count, 1)
    }

    /// The guard is specific to my own location. A band or mode change is
    /// shared by every row of a contact, so it never excludes anything.
    func testBandAndModeChangesExcludeNothing() {
        let group = UUID()
        let rows = [
            qso(myLoc: "JOH", theirLoc: "TX", groupID: group),
            qso(myLoc: "MIA", theirLoc: "TX", groupID: group),
        ]
        for field in [BulkEdit.Field.band, .mode] {
            let partition = BulkEdit.partition(rows, field: field, allRows: rows)
            XCTAssertEqual(partition.changing.count, 2, "\(field)")
            XCTAssertTrue(partition.excluded.isEmpty, "\(field)")
        }
    }

    // MARK: Helpers

    func apply(
        _ value: BulkEdit.Value,
        field: BulkEdit.Field,
        to rows: [QSO],
        party: PartyDefinition? = nil,
        isInState: Bool = true
    ) throws -> [QSO] {
        switch BulkEdit.apply(
            value, field: field, to: rows, party: party ?? ksqp, isInState: isInState
        ) {
        case .success(let updated): return updated
        case .failure(let failure): throw failure
        }
    }

    func XCTAssertThrowsFailure(
        _ result: Result<[QSO], BulkEdit.Failure>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("expected the change to be refused", file: file, line: line)
        case .failure(let failure):
            XCTAssertFalse(failure.message.isEmpty, "a refusal must say why",
                           file: file, line: line)
        }
    }
}
