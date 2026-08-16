import XCTest
@testable import QSOPartyLogger

/// The band map's three colours — N1MM's "Blue: Will be a good QSO, not a
/// multiplier / Red: Single Multiplier / Gray: Dupe" (Bandmap window, fetched
/// 2026-08-15) — and where a cluster spot's location comes from: this log, the
/// archive, the call history file, in that order, so a red spot is exactly one
/// whose county lands in the exchange field on tuning to it.
///
/// ALQP counts multipliers per mode, which is what lets "worked on phone" leave
/// a CW spot red.
@MainActor
final class BandMapStatusTests: XCTestCase {

    private func model() throws -> BandMapModel {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = BandMapModel(
            radio: RadioController(),
            spotStore: SpotStore(),
            settings: AppSettings.shared
        )
        model.party = alqp
        var log = ContestLog(partyID: alqp.id)
        log.myLocation = .outOfState(location: "TX")
        model.log = log
        model.allowedModes = alqp.allowedModeClasses
        return model
    }

    /// 7030: unambiguously CW on 40 m.
    private func clusterSpot(_ call: String = "K4EES", kHz: Double = 7030) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "W3LPL", comment: "", receivedAt: Date())
    }

    private func hubSpot(_ call: String, county: String, kHz: Double = 7030) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "N4EMP", comment: "",
             receivedAt: Date(), county: county, source: .hub)
    }

    private func qso(_ call: String, _ county: String, band: Band = .m20,
                     modeClass: ModeClass = .cw) -> QSO {
        QSO(call: call, band: band, modeClass: modeClass,
            rawMode: modeClass == .phone ? "USB" : "CW",
            rstSent: modeClass.defaultRST, rstRcvd: modeClass.defaultRST,
            myLoc: "TX", theirLoc: county)
    }

    // MARK: Cluster spots — where the location comes from

    func testAClusterSpotNobodyKnowsIsBlueWithNoVerdict() throws {
        let model = try model()
        XCTAssertNil(model.verdict(for: clusterSpot()))
        XCTAssertEqual(model.status(for: clusterSpot()), .unworked)
    }

    func testThisLogColoursAClusterSpotRed() throws {
        let model = try model()
        var log = try XCTUnwrap(model.log)
        log.qsos = [qso("K4EES", "BALD", band: .m20, modeClass: .phone)]   // Baldwin counted on phone only
        model.log = log

        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertEqual(verdict.location, "BALD")
        XCTAssertEqual(verdict.source, .thisLog)
        XCTAssertTrue(verdict.needed, "ALQP counts per mode: Baldwin on CW is still open")
        XCTAssertEqual(model.status(for: clusterSpot()), .neededMultiplier)
    }

    func testACountyAlreadyCountedMakesItBlue() throws {
        let model = try model()
        var log = try XCTUnwrap(model.log)
        log.qsos = [qso("K4EES", "BALD", band: .m20, modeClass: .cw)]      // Baldwin counted on CW
        model.log = log

        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertFalse(verdict.needed)
        XCTAssertEqual(model.status(for: clusterSpot()), .unworked, "a good QSO, not a multiplier")
    }

    func testTheArchiveColoursAClusterSpotRed() throws {
        let model = try model()
        model.archiveIndex = StationMemory.Index(byCall: [
            "K4EES": [StationMemory.ArchiveEntry(
                call: "K4EES", theirLoc: "BALD", partyID: "alqp", year: 2025,
                timestampUTC: Date(timeIntervalSince1970: 1_750_000_000), isCountyOfItsParty: true
            )]
        ])
        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertEqual(verdict.location, "BALD")
        XCTAssertEqual(verdict.source, .archive)
        XCTAssertTrue(verdict.needed)
    }

    func testTheCallHistoryFileColoursAClusterSpotRed() throws {
        let model = try model()
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY AL
        K4EES,,BALD,
        """)
        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertEqual(verdict.location, "BALD")
        XCTAssertEqual(verdict.source, .callHistory)
        XCTAssertTrue(verdict.needed)
    }

    // MARK: Hub spots keep their own county

    func testAHubSpotUsesItsOwnCountyEvenWhenTheLogRemembersAnother() throws {
        let model = try model()
        var log = try XCTUnwrap(model.log)
        log.qsos = [qso("K4EES", "MDSN")]                                   // worked in Madison earlier
        model.log = log

        let verdict = try XCTUnwrap(model.verdict(for: hubSpot("K4EES", county: "BALD")))
        XCTAssertEqual(verdict.location, "BALD", "the spot is where he is now")
        XCTAssertEqual(verdict.source, .spot)
        XCTAssertTrue(verdict.needed)
        XCTAssertTrue(model.isNeededMultiplier(hubSpot("K4EES", county: "BALD")), "the old entry point agrees")
    }

    // MARK: Grey wins

    func testWorkedWinsOverNeeded() throws {
        let model = try model()
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K4EES,,BALD,
        """)
        model.workedCalls = ["K4EES"]
        XCTAssertEqual(model.status(for: clusterSpot()), .worked)
        var busted = clusterSpot("W4XYZ")
        busted.isSuperseded = true
        XCTAssertEqual(model.status(for: busted), .worked, "superseded draws grey too")
    }

    // MARK: Caches follow their inputs

    func testANewCallHistoryFileChangesTheAnswer() throws {
        let model = try model()
        XCTAssertNil(model.verdict(for: clusterSpot()))
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K4EES,,BALD,
        """)
        XCTAssertEqual(model.verdict(for: clusterSpot())?.location, "BALD", "the memo was dropped")
    }
}
