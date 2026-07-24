import XCTest
@testable import QSOPartyLogger

final class ModelTests: XCTestCase {

    // MARK: Band

    func testBandFromFrequencyEdges() {
        XCTAssertEqual(Band.from(freqKHz: 3500), .m80)
        XCTAssertEqual(Band.from(freqKHz: 4000), .m80)
        XCTAssertEqual(Band.from(freqKHz: 7040), .m40)
        XCTAssertEqual(Band.from(freqKHz: 14042), .m20)
        XCTAssertEqual(Band.from(freqKHz: 21300), .m15)
        XCTAssertEqual(Band.from(freqKHz: 28450), .m10)
        XCTAssertEqual(Band.from(freqKHz: 50125), .m6)
        XCTAssertNil(Band.from(freqKHz: 7301))
        XCTAssertNil(Band.from(freqKHz: 2))
    }

    func testBandDefaultFrequenciesLandInBand() {
        for band in Band.allCases {
            XCTAssertEqual(Band.from(freqKHz: band.defaultFreqKHz), band, "default freq for \(band.rawValue)")
        }
    }

    // MARK: ModeClass

    func testModeClassification() {
        XCTAssertEqual(ModeClass.classify(rawMode: "CW"), .cw)
        XCTAssertEqual(ModeClass.classify(rawMode: "SSB"), .phone)
        XCTAssertEqual(ModeClass.classify(rawMode: "usb"), .phone)
        XCTAssertEqual(ModeClass.classify(rawMode: "FM"), .phone)
        XCTAssertEqual(ModeClass.classify(rawMode: "RTTY"), .digital)
        XCTAssertEqual(ModeClass.classify(rawMode: "FT8"), .digital)
    }

    func testDefaultRST() {
        XCTAssertEqual(ModeClass.phone.defaultRST, "59")
        XCTAssertEqual(ModeClass.cw.defaultRST, "599")
        XCTAssertEqual(ModeClass.digital.defaultRST, "599")
    }

    // MARK: MyLocation

    func testSentExchanges() {
        XCTAssertEqual(MyLocation.inState(counties: ["MRN", "CHS"]).sentExchanges, ["MRN", "CHS"])
        XCTAssertEqual(MyLocation.outOfState(location: "TX").sentExchanges, ["TX"])
        XCTAssertTrue(MyLocation.inState(counties: ["MRN"]).isInState)
        XCTAssertFalse(MyLocation.outOfState(location: "TX").isInState)
    }

    // MARK: ContestLog round-trip

    func testContestLogJSONRoundTrip() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos.append(
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_787_500_000),
                call: "W0BH",
                band: .m20,
                modeClass: .cw,
                rawMode: "CW",
                freqKHz: 14042,
                rstSent: "599",
                rstRcvd: "599",
                myLoc: "TX",
                theirLoc: "MRN"
            )
        )
        let data = try log.encoded()
        let decoded = try ContestLog.decode(from: data)
        XCTAssertEqual(decoded, log)
        XCTAssertEqual(decoded.qsos.count, 1)
        XCTAssertEqual(decoded.qsos[0].theirLoc, "MRN")
    }
}
