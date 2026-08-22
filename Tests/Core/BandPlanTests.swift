import XCTest
@testable import QSOPartyLogger

/// CW→phone crossovers. Every boundary here traces to 47 CFR §97.305(c),
/// §97.301(a) for the 80/75 m split, or the ARRL band plan for 160 m — see
/// `docs/research/band_plan_sources.md`.
final class BandPlanTests: XCTestCase {

    // MARK: Crossovers

    func testCrossoverOnEveryBandWithASplit() {
        let cases: [(band: String, phoneStart: Double)] = [
            ("160m", 1843),
            ("80m", 3600),
            ("40m", 7125),
            ("20m", 14150),
            ("17m", 18110),
            ("15m", 21200),
            ("12m", 24930),
            ("10m", 28300),
            ("6m", 50100),
            ("2m", 144100),
        ]
        for (band, phoneStart) in cases {
            XCTAssertEqual(
                BandPlan.radioMode(atKHz: phoneStart - 1), .cw,
                "\(band): just below \(phoneStart) is CW"
            )
            XCTAssertEqual(
                BandPlan.radioMode(atKHz: phoneStart), .phone,
                "\(band): the crossover itself is phone"
            )
            XCTAssertEqual(
                BandPlan.radioMode(atKHz: phoneStart + 1), .phone,
                "\(band): above \(phoneStart) is phone"
            )
        }
    }

    func testTypicalContestFrequencies() {
        XCTAssertEqual(BandPlan.radioMode(atKHz: 14040), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 14250), .phone)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 7040), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 7220), .phone)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 3550), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 3850), .phone)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 21350), .phone)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 28040), .cw)
    }

    /// The band map plots the whole band, so both edges must answer.
    func testBandEdges() {
        XCTAssertEqual(BandPlan.radioMode(atKHz: 14000), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 14350), .phone)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 1800), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 2000), .phone)
    }

    /// 47 CFR §97.305(c) gives 30 m an RTTY/data row and no phone row.
    func test30MetersIsNeverPhone() {
        XCTAssertEqual(BandPlan.radioMode(atKHz: 10100), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 10140), .cw)
        XCTAssertEqual(BandPlan.radioMode(atKHz: 10150), .cw)
    }

    /// The band plan never claims to know a mode it cannot defend.
    func testBandsWithNoDefensibleSplit() {
        XCTAssertNil(BandPlan.radioMode(atKHz: 5332), "60 m is channelized")
        XCTAssertNil(BandPlan.radioMode(atKHz: 5405), "60 m is channelized")
        XCTAssertNil(BandPlan.radioMode(atKHz: 222100), "1.25 m is all-mode")
        XCTAssertNil(BandPlan.radioMode(atKHz: 432100), "70 cm is all-mode")
    }

    func testOutsideEveryBandHasNoOpinion() {
        XCTAssertNil(BandPlan.radioMode(atKHz: 5000), "WWV, not an amateur band")
        XCTAssertNil(BandPlan.radioMode(atKHz: 27185), "CB, not an amateur band")
        XCTAssertNil(BandPlan.radioMode(atKHz: 0))
    }

    // MARK: Mode changes

    func testChangesModeWhenTheSegmentDisagrees() {
        XCTAssertEqual(BandPlan.modeChange(toKHz: 14250, currentMode: .cw), .phone)
        XCTAssertEqual(BandPlan.modeChange(toKHz: 14040, currentMode: .phone), .cw)
        XCTAssertEqual(BandPlan.modeChange(toKHz: 7220, currentMode: .cw), .phone)
    }

    /// Nothing to do means nothing sent — a QSY can never thrash the radio.
    func testNoChangeWhenTheModeIsAlreadyRight() {
        XCTAssertNil(BandPlan.modeChange(toKHz: 14040, currentMode: .cw))
        XCTAssertNil(BandPlan.modeChange(toKHz: 14250, currentMode: .phone))
    }

    func testNoChangeWhereThePlanHasNoOpinion() {
        XCTAssertNil(BandPlan.modeChange(toKHz: 5332, currentMode: .cw))
        XCTAssertNil(BandPlan.modeChange(toKHz: 5332, currentMode: .phone))
        XCTAssertNil(BandPlan.modeChange(toKHz: 27185, currentMode: .cw))
    }

    /// A RTTY operator moving around the CW/data portion of a band stays in
    /// RTTY — that mode belongs there. Moving into the phone segment does
    /// switch them, because RTTY does not belong there.
    func testDigitalOperatorIsLeftAloneInTheDataPortion() {
        XCTAssertNil(BandPlan.modeChange(toKHz: 14080, currentMode: .digital))
        XCTAssertNil(BandPlan.modeChange(toKHz: 7040, currentMode: .digital))
        XCTAssertNil(BandPlan.modeChange(toKHz: 10140, currentMode: .digital), "30 m is all data")
        XCTAssertEqual(BandPlan.modeChange(toKHz: 14250, currentMode: .digital), .phone)
    }

    /// The band plan only ever selects CW or SSB, so a digital mode can never
    /// come out of it.
    func testNeverSelectsADigitalMode() {
        for kHz in stride(from: 1800.0, through: 148_000.0, by: 137) {
            XCTAssertNotEqual(BandPlan.radioMode(atKHz: kHz), .digital, "\(kHz) kHz")
            for current in ModeClass.allCases {
                XCTAssertNotEqual(
                    BandPlan.modeChange(toKHz: kHz, currentMode: current), .digital,
                    "\(kHz) kHz from \(current)"
                )
            }
        }
    }

    // MARK: Raw mode strings

    /// "SSB" not "USB"/"LSB": the driver picks the sideband from the frequency.
    func testRawModeStrings() {
        XCTAssertEqual(BandPlan.rawMode(for: .cw), "CW")
        XCTAssertEqual(BandPlan.rawMode(for: .phone), "SSB")
        XCTAssertNil(BandPlan.rawMode(for: .digital))
    }

    /// Every raw mode the plan emits has to survive the round trip back
    /// through the classifier the log and the entry bar use.
    func testRawModesRoundTripThroughModeClass() throws {
        for mode in [ModeClass.cw, .phone] {
            let raw = try XCTUnwrap(BandPlan.rawMode(for: mode))
            XCTAssertEqual(ModeClass.classify(rawMode: raw), mode)
        }
    }

    /// The K3 resolves "SSB" to the conventional sideband, so the string the
    /// band plan emits has to be one the driver accepts.
    func testDriversAcceptTheBandPlansRawModes() {
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "CW", frequencyHz: 14_040_000), "MD3;")
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "SSB", frequencyHz: 14_250_000), "MD2;")
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "SSB", frequencyHz: 3_850_000), "MD1;")
    }
}
