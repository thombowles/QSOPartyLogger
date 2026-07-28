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

    /// 1.25 m is 222.000–225.000 per ADIF 3.1.4 and 47 CFR §97.301(a). The
    /// 219–220 MHz digital allocation is deliberately not part of the band.
    func testBand125MetersEdges() {
        XCTAssertEqual(Band.from(freqKHz: 222000), .cm125)
        XCTAssertEqual(Band.from(freqKHz: 223500), .cm125)
        XCTAssertEqual(Band.from(freqKHz: 225000), .cm125)
        XCTAssertNil(Band.from(freqKHz: 221999))
        XCTAssertNil(Band.from(freqKHz: 225001))
        XCTAssertNil(Band.from(freqKHz: 219500), "219–220 MHz is not part of 1.25 m")
    }

    /// The raw value doubles as the ADIF band string, so it must match the
    /// ADIF 3.1.4 Band Enumeration exactly — "1.25m", not "222" or "1.25M".
    func testBand125MetersADIFString() {
        XCTAssertEqual(Band.cm125.adif, "1.25m")
        XCTAssertEqual(Band.cm125.rawValue, "1.25m")
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

    // MARK: Operating mode (2026-07-25)

    /// The in-state station is the multiplier everyone is chasing, so it runs.
    /// The out-of-state station is doing the chasing, so it searches.
    func testOperatingModeDefaultsFromLocation() {
        var inState = ContestLog(partyID: "ksqp")
        inState.myLocation = .inState(counties: ["SED"])
        XCTAssertEqual(inState.derivedOperatingMode, .run)

        var outOfState = ContestLog(partyID: "ksqp")
        outOfState.myLocation = .outOfState(location: "TX")
        XCTAssertEqual(outOfState.derivedOperatingMode, .searchPounce)
    }

    /// A log written before the mode was persisted derives one rather than
    /// falling back to Run for an operator who will never call CQ.
    ///
    /// The fixture is built by encoding a real log and deleting the key, not
    /// hand-typed: `StationProfile` has sixteen fields and a hand-written
    /// stand-in would drift from the model the first time one is added.
    func testLogWithoutAStoredModeDerivesItFromLocation() throws {
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .outOfState(location: "TX")
        log.operatingMode = .run
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        XCTAssertNotNil(
            object.removeValue(forKey: "operatingMode"),
            "the key must exist before removing it, or this proves nothing"
        )
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertEqual(decoded.operatingMode, .searchPounce,
                       "out of state, so S&P — not the old unconditional Run")
    }

    /// A station profile stored before a field existed decodes to that
    /// field's default instead of failing the whole document — the same
    /// tolerance `ContestLog` itself already has. Proven by stripping a key
    /// that exists today, so the fixture is real, not hypothetical.
    func testStationProfileDecodesWhenAStoredKeyIsMissing() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.station.operators = "KE5CW N0XYZ"
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        var station = try XCTUnwrap(object["station"] as? [String: Any])
        XCTAssertNotNil(
            station.removeValue(forKey: "operators"),
            "the key must exist before removing it, or this proves nothing"
        )
        object["station"] = station
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertEqual(decoded.station.operators, "", "missing key → the default")
        XCTAssertEqual(decoded.station.callsign, "KE5CW", "neighbouring values intact")
    }

    /// The entry-classification fields — NAQP rule 5's SO/SOA distinction
    /// and the grid square the reference N1MM log carries — survive a
    /// document round trip.
    func testStationProfileRoundTripsTheEntryFields() throws {
        var log = ContestLog(partyID: "naqpcw")
        log.station.categoryAssisted = .assisted
        log.station.gridLocator = "EM13le"
        let decoded = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(decoded.station.categoryAssisted, .assisted)
        XCTAssertEqual(decoded.station.gridLocator, "EM13le",
                       "stored as typed; the exporter owns uppercasing")
    }

    /// A profile saved before the entry fields existed decodes to their
    /// defaults: unassisted, no grid. Fixture built by encoding and deleting
    /// the keys, so it is the real pre-field shape.
    func testStationProfileWithoutTheEntryFieldsDecodesToDefaults() throws {
        var log = ContestLog(partyID: "naqpcw")
        log.station.callsign = "KE5CW"
        log.station.categoryAssisted = .assisted
        log.station.gridLocator = "EM13LE"
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        var station = try XCTUnwrap(object["station"] as? [String: Any])
        XCTAssertNotNil(station.removeValue(forKey: "categoryAssisted"),
                        "the key must exist before removing it")
        XCTAssertNotNil(station.removeValue(forKey: "gridLocator"),
                        "the key must exist before removing it")
        object["station"] = station
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertEqual(decoded.station.categoryAssisted, .nonAssisted,
                       "absent means unassisted — the claim is opt-in")
        XCTAssertEqual(decoded.station.gridLocator, "")
        XCTAssertEqual(decoded.station.callsign, "KE5CW")
    }

    /// A stored mode wins, so reopening a log mid-contest restores the mode
    /// the operator was actually in.
    func testStoredModeSurvivesARoundTrip() throws {
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .outOfState(location: "TX")
        log.operatingMode = .run
        let reloaded = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(reloaded.operatingMode, .run,
                       "an out-of-state op who moved to Run stays in Run")
    }

    func testNewLogTakesTheDerivedModeAtInit() {
        XCTAssertEqual(
            ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["SED"])).operatingMode,
            .run
        )
        XCTAssertEqual(
            ContestLog(partyID: "ksqp", myLocation: .outOfState(location: "TX")).operatingMode,
            .searchPounce
        )
    }

    // MARK: The spot-use fact and the assisted claim (2026-07-28)

    /// A document saved before the fact existed still opens, and reads as
    /// having used nothing — proven by stripping a key that exists today, so
    /// the fixture is real, not hypothetical.
    func testLogWithoutUsedSpotsDecodesToFalse() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        XCTAssertNotNil(
            object.removeValue(forKey: "usedSpots"),
            "the key must exist before removing it, or this proves nothing"
        )
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertFalse(decoded.usedSpots, "absent means no spotting assistance")
        XCTAssertEqual(decoded.station.callsign, "KE5CW", "neighbouring values survive")
    }

    func testUsedSpotsSurvivesARoundTrip() throws {
        var log = ContestLog(partyID: "ksqp")
        log.usedSpots = true
        XCTAssertTrue(try ContestLog.decode(from: log.encoded()).usedSpots,
                      "a restart mid-contest must not launder the assistance")
    }

    /// The one predicate the warning hangs off: the conjunction of the
    /// recorded fact and the profile's claim. The fact is recorded even for
    /// an ASSISTED profile — flipping the claim afterwards is what the
    /// truth table's third line is about.
    func testSpotsContradictNonAssistedClaimTruthTable() {
        var log = ContestLog(partyID: "ksqp")
        XCTAssertEqual(log.station.categoryAssisted, .nonAssisted, "precondition: the default claim")
        XCTAssertFalse(log.spotsContradictNonAssistedClaim, "no spots — nothing to contradict")

        log.usedSpots = true
        XCTAssertTrue(log.spotsContradictNonAssistedClaim,
                      "spots received against a NON-ASSISTED claim")

        log.station.categoryAssisted = .assisted
        XCTAssertFalse(log.spotsContradictNonAssistedClaim, "ASSISTED owns its spots")

        log.usedSpots = false
        XCTAssertFalse(log.spotsContradictNonAssistedClaim)
    }
}
