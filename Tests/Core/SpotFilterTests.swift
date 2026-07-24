import XCTest
@testable import QSOPartyLogger

/// Continent test on the *spotter's* callsign — a QSO party cares about who
/// can actually hear the run frequency, so EU/JA skimmer spots are noise.
final class SpotFilterTests: XCTestCase {

    private func assertNA(_ calls: [String], _ expected: Bool, line: UInt = #line) {
        for call in calls {
            XCTAssertEqual(
                SpotFilter.isNorthAmerican(spotter: call), expected,
                "\(call) should\(expected ? "" : " not") count as North America",
                line: line
            )
        }
    }

    func testUnitedStates() {
        assertNA(["W3LPL", "K9PPY", "N0AX", "AA5B", "AB1CD", "AL7X", "KL7RA", "W1AW"], true)
    }

    func testCanadaAndMexico() {
        assertNA(["VE3EN", "VA7ABC", "VO1AA", "VY2XX", "CY0XX", "XE2X", "XE1H", "XF1AA"], true)
    }

    func testCaribbeanCentralAmericaAndGreenland() {
        assertNA(
            ["KP4AA", "KP2XX", "C6AAA", "6Y5XX", "TI2XX", "HP1XX", "V31XX",
             "ZF2XX", "HI8UD", "VP9XX", "VP5XX", "FM5XX", "OX3XX", "CO8XX", "8P6XX"],
            true
        )
    }

    func testEuropeAsiaOceaniaAfricaRejected() {
        assertNA(
            ["DL9GTB", "G4ABC", "SQ7FZR", "SP8SN", "JA1XYZ", "VK3ABC", "UA3XX",
             "EA5XX", "F5HRY", "I2XX", "OK1XX", "OZ1XX", "OY1XX", "ZS6XX", "9M2XX", "JR4DHK"],
            false
        )
    }

    func testSouthAmericaRejected() {
        // Nearby but not NA — and the VP/PJ blocks straddle both continents.
        assertNA(["PY2XX", "LU1XX", "HK3XX", "YV5XX", "CE3XX", "VP8XX", "PJ2XX"], false)
    }

    func testStripsSkimmerAndPortableSuffixes() {
        assertNA(["W3LPL-#", "VE7CC-1", "K1TTT-2", "N0AX/M", "W1AW/4"], true)
        assertNA(["DL9GTB-#", "SP8SN-3"], false)
    }

    func testGarbageIsNotNorthAmerican() {
        assertNA(["", "   ", "?", "-"], false)
    }

    // MARK: Mode inference

    func testModeFromFrequencySegment() {
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14040, comment: ""), .cw)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14074, comment: ""), .digital)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14250, comment: ""), .phone)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 3550, comment: ""), .cw)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 3573, comment: ""), .digital)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 3800, comment: ""), .phone)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 7040, comment: ""), .cw, "app's own 40m CW default")
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 7074, comment: ""), .digital)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 7200, comment: ""), .phone)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 21030, comment: ""), .cw)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 28400, comment: ""), .phone)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 50313, comment: ""), .digital, "6m FT8")
    }

    func testCommentOverridesFrequency() {
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14040, comment: "FT8 -12 dB"), .digital)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14040, comment: "SSB net"), .phone)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14250, comment: "CW 25 WPM"), .cw)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14090, comment: "RTTY"), .digital)
    }

    /// A callsign that merely contains "CW" must not be read as a mode.
    func testCommentMatchingIsWholeWord() {
        XCTAssertEqual(
            SpotFilter.modeClass(freqKHz: 14250, comment: "tnx K5CW for the qso"), .phone,
            "K5CW is a callsign, not a mode hint"
        )
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14250, comment: "worked KE5CWX"), .phone)
    }

    // MARK: Spotted-station continent

    func testSpottedStationContinent() {
        // Same test, applied to the station being spotted rather than the
        // spotter — an EU spot is noise even when a US skimmer posted it.
        XCTAssertTrue(SpotFilter.isNorthAmerican(call: "K5ABC"))
        XCTAssertTrue(SpotFilter.isNorthAmerican(call: "VE3XYZ"))
        XCTAssertTrue(SpotFilter.isNorthAmerican(call: "W1AW/4"))
        XCTAssertFalse(SpotFilter.isNorthAmerican(call: "DL1ABC"))
        XCTAssertFalse(SpotFilter.isNorthAmerican(call: "F5HRY/P"))
        XCTAssertFalse(SpotFilter.isNorthAmerican(call: "JR4DHK"))
    }

    // MARK: Skimmer / RBN detection

    func testSkimmerSpotsIdentified() {
        XCTAssertTrue(SpotFilter.isSkimmer(spot("K5ABC", 14040, "W3LPL-#")))
        XCTAssertTrue(SpotFilter.isSkimmer(spot("K5ABC", 14040, "N4ZR", "CW 22 dB 25 WPM CQ")))
        XCTAssertTrue(SpotFilter.isSkimmer(spot("K5ABC", 14040, "VE7CC", "16 dB 30 WPM")))
    }

    func testHumanSpotsAreNotSkimmer() {
        XCTAssertFalse(SpotFilter.isSkimmer(spot("K5ABC", 14040, "W3LPL", "loud in VA")))
        XCTAssertFalse(SpotFilter.isSkimmer(spot("K5ABC", 14040, "VE7CC-1", "")))
        XCTAssertFalse(SpotFilter.isSkimmer(spot("K5ABC", 14040, "N0AX", "25th CACG ssb")))
    }

    // MARK: Combined filtering

    private func spot(_ call: String, _ kHz: Double, _ spotter: String, _ comment: String = "") -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: spotter, comment: comment, receivedAt: Date())
    }

    func testDefaultOptionsKeepEverything() {
        let spots = [spot("A1A", 14040, "W3LPL"), spot("B2B", 14250, "DL9GTB")]
        XCTAssertEqual(SpotFilter.filter(spots, options: SpotFilter.Options()).count, 2)
    }

    func testModeFilter() {
        let spots = [
            spot("CW1", 14040, "W3LPL"),
            spot("PH1", 14250, "W3LPL"),
            spot("DG1", 14074, "W3LPL"),
        ]
        var options = SpotFilter.Options()
        options.modes = [.cw]
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["CW1"])
        options.modes = [.cw, .phone]
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["CW1", "PH1"])
    }

    func testBandFilter() {
        let spots = [spot("A1A", 14040, "W3LPL"), spot("B2B", 7040, "W3LPL"), spot("C3C", 10120, "W3LPL")]
        var options = SpotFilter.Options()
        options.bands = [.m20]
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["A1A"])
        options.bands = [.m20, .m40]
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["A1A", "B2B"])
    }

    func testNorthAmericanStationsOnly() {
        let spots = [
            spot("K5ABC", 14040, "DL9GTB"),   // NA station, EU spotter
            spot("DL1ABC", 14040, "W3LPL"),   // EU station, NA spotter
        ]
        var options = SpotFilter.Options()
        options.northAmericanStationsOnly = true
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["K5ABC"])

        options = SpotFilter.Options()
        options.northAmericanSpottersOnly = true
        XCTAssertEqual(
            SpotFilter.filter(spots, options: options).map(\.call), ["DL1ABC"],
            "spotter and station filters are independent axes"
        )
    }

    func testHideWorkedStations() {
        let spots = [spot("K5ABC", 14040, "W3LPL"), spot("W0BH", 14045, "W3LPL")]
        var options = SpotFilter.Options()
        options.hideWorked = true
        options.workedCalls = ["K5ABC"]
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["W0BH"])

        options.hideWorked = false
        XCTAssertEqual(SpotFilter.filter(spots, options: options).count, 2, "off = show worked, grayed")
    }

    func testHideSkimmerSpots() {
        let spots = [
            spot("K5ABC", 14040, "W3LPL-#", "CW 22 dB 25 WPM CQ"),
            spot("W0BH", 14045, "N0AX", "up 2"),
        ]
        var options = SpotFilter.Options()
        options.hideSkimmer = true
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["W0BH"])
    }

    func testFiltersCombine() {
        let spots = [
            spot("KEEP", 14040, "W3LPL"),
            spot("EUCW", 14040, "DL9GTB"),
            spot("USPH", 14250, "W3LPL"),
            spot("US40", 7040, "W3LPL"),
            spot("DL9XX", 14041, "W3LPL"),
            spot("DUPE", 14042, "W3LPL"),
            spot("SKIM", 14043, "W3LPL-#", "CW 20 dB 28 WPM CQ"),
        ]
        var options = SpotFilter.Options()
        options.northAmericanSpottersOnly = true
        options.northAmericanStationsOnly = true
        options.hideWorked = true
        options.hideSkimmer = true
        options.workedCalls = ["DUPE"]
        options.modes = [.cw]
        options.bands = [.m20]
        XCTAssertEqual(SpotFilter.filter(spots, options: options).map(\.call), ["KEEP"])
    }

    func testFilteringASpotList() {
        let spots = [
            Spot(call: "K5ABC", freqKHz: 14025, spotter: "W3LPL", comment: "", receivedAt: Date()),
            Spot(call: "K5ABC", freqKHz: 14026, spotter: "DL9GTB", comment: "", receivedAt: Date()),
            Spot(call: "W0BH", freqKHz: 7040, spotter: "VE3EN", comment: "", receivedAt: Date()),
        ]
        XCTAssertEqual(SpotFilter.northAmericanOnly(spots).map(\.spotter), ["W3LPL", "VE3EN"])
        XCTAssertEqual(SpotFilter.northAmericanOnly(spots, enabled: false).count, 3)
    }
}
