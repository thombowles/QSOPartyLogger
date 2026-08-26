import XCTest
@testable import QSOPartyLogger

/// The entry row's shape as a value (spec 2026-08-25 §entry row). For a
/// party it must reproduce the row's old flag branches exactly — asserted
/// across every bundled party; for the POTA contest it derives from the
/// exchange spec.
final class EntryLayoutTests: XCTestCase {

    func testEveryPartyMatchesItsOldFlags() {
        let parties = PartyCatalog.loadBundled(bundle: .main)
        XCTAssertGreaterThanOrEqual(parties.count, 49)
        for party in parties {
            for activation in [false, true] {
                let layout = EntryLayout(party: party, contest: nil,
                                         isActivation: activation)
                XCTAssertEqual(layout.showsRST, party.exchangeIncludesRST, party.id)
                XCTAssertEqual(layout.showsSerial, party.exchangeIncludesSerial, party.id)
                XCTAssertEqual(layout.showsName, party.exchangeIncludesName, party.id)
                XCTAssertEqual(layout.member != nil, party.memberExchange != nil, party.id)
                XCTAssertTrue(layout.showsLocation, party.id)
                XCTAssertEqual(layout.showsTheirPark, activation, party.id)
                XCTAssertFalse(layout.theirParkInSpaceCycle, party.id)
            }
        }
    }

    func testNilPartyNilContestIsTodaysDefaultRow() {
        let layout = EntryLayout(party: nil, contest: nil, isActivation: false)
        XCTAssertTrue(layout.showsRST)
        XCTAssertFalse(layout.showsSerial)
        XCTAssertFalse(layout.showsName)
        XCTAssertNil(layout.member)
        XCTAssertTrue(layout.showsLocation)
        XCTAssertEqual(layout.locationLabel, "Exchange")
        XCTAssertFalse(layout.showsTheirPark)
    }

    func testPotaLayout() throws {
        let pota = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        for activation in [false, true] {
            let layout = EntryLayout(party: nil, contest: pota,
                                     isActivation: activation)
            XCTAssertTrue(layout.showsRST)
            XCTAssertFalse(layout.showsSerial)
            XCTAssertFalse(layout.showsName)
            XCTAssertNil(layout.member)
            XCTAssertFalse(layout.showsLocation,
                           "no location element, no exchange field")
            XCTAssertTrue(layout.showsTheirPark,
                          "a hunter with no own park still logs their park")
            XCTAssertTrue(layout.theirParkInSpaceCycle)
            XCTAssertTrue(layout.showsTheirState, "operator report 1, 2026-08-25")
            XCTAssertTrue(layout.showsNotes)
        }
    }

    func testPartiesShowNeitherStateNorNotes() {
        for party in PartyCatalog.loadBundled(bundle: .main) {
            let layout = EntryLayout(party: party, contest: nil, isActivation: true)
            XCTAssertFalse(layout.showsTheirState, party.id)
            XCTAssertFalse(layout.showsNotes, party.id)
        }
        let bare = EntryLayout(party: nil, contest: nil, isActivation: false)
        XCTAssertFalse(bare.showsTheirState)
        XCTAssertFalse(bare.showsNotes)
    }

    func testSpaceCycleMatchesTheOldRoutingForEveryParty() {
        // The old router. Kept verbatim in the test so the equivalence claim
        // is against the shipped behavior, not against a re-derivation.
        func old(_ f: EntryBar.Field, rst: Bool, serial: Bool,
                 name: Bool, member: Bool) -> EntryBar.Field {
            switch f {
            case .call: serial ? .serialRcvd : (name ? .nameRcvd : .exchange)
            case .rstSent: rst ? .rstRcvd : .exchange
            case .rstRcvd: serial ? .serialRcvd : (name ? .nameRcvd : .exchange)
            case .serialSent: .serialRcvd
            case .serialRcvd: name ? .nameRcvd : .exchange
            case .nameRcvd: .exchange
            case .exchange: member ? .memberRcvd : .call
            case .memberRcvd: .call
            case .theirPark: .call
            // Fields the old router never had (2026-08-25); outside the
            // equivalence loop's field list, mapped trivially to satisfy
            // the exhaustive switch.
            case .theirState, .notes: .call
            }
        }
        let fields: [EntryBar.Field] = [.call, .rstSent, .rstRcvd, .serialSent,
                                        .serialRcvd, .nameRcvd, .exchange,
                                        .memberRcvd, .theirPark]
        for party in PartyCatalog.loadBundled(bundle: .main) {
            let layout = EntryLayout(party: party, contest: nil, isActivation: true)
            for f in fields {
                XCTAssertEqual(
                    f.next(layout: layout),
                    old(f, rst: party.exchangeIncludesRST,
                        serial: party.exchangeIncludesSerial,
                        name: party.exchangeIncludesName,
                        member: party.memberExchange != nil),
                    "\(party.id) \(f)")
            }
        }
    }

    func testPotaSpaceCycle() throws {
        let pota = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        let layout = EntryLayout(party: nil, contest: pota, isActivation: true)
        // Call → park → state → call ("59 Missouri" is the usual POTA
        // exchange, so state sits in the cycle); notes are Tab-only — prose
        // typed mid-run is the exception, not the path. Tab still walks the
        // RSTs, whose Space hop chains to the park too.
        XCTAssertEqual(EntryBar.Field.call.next(layout: layout), .theirPark)
        XCTAssertEqual(EntryBar.Field.rstSent.next(layout: layout), .rstRcvd)
        XCTAssertEqual(EntryBar.Field.rstRcvd.next(layout: layout), .theirPark)
        XCTAssertEqual(EntryBar.Field.theirPark.next(layout: layout), .theirState)
        XCTAssertEqual(EntryBar.Field.theirState.next(layout: layout), .call)
        XCTAssertEqual(EntryBar.Field.notes.next(layout: layout), .call)
        // A party's park field still closes straight back to the call.
        let partyLayout = EntryLayout(party: PartyCatalog.loadBundled(bundle: .main).first,
                                      contest: nil, isActivation: true)
        XCTAssertEqual(EntryBar.Field.theirPark.next(layout: partyLayout), .call)
    }
}
