import XCTest
@testable import QSOPartyLogger

/// Typed commands in the callsign field: frequency, band, or mode — the
/// hands-on-keyboard alternative to reaching for radio controls.
final class EntryCommandTests: XCTestCase {

    func testParseFrequencyKHz() {
        XCTAssertEqual(EntryCommand.parse("14025"), .frequency(kHz: 14025))
        XCTAssertEqual(EntryCommand.parse("14025.5"), .frequency(kHz: 14025.5))
        XCTAssertEqual(EntryCommand.parse("7040"), .frequency(kHz: 7040))
        XCTAssertEqual(EntryCommand.parse("1815"), .frequency(kHz: 1815))
    }

    func testParseFrequencyMHzStyle() {
        XCTAssertEqual(EntryCommand.parse("14.025"), .frequency(kHz: 14025))
        XCTAssertEqual(EntryCommand.parse("3.550"), .frequency(kHz: 3550))
        XCTAssertEqual(EntryCommand.parse("50.095"), .frequency(kHz: 50095))
    }

    func testRejectsFrequencyOutsideEveryBand() {
        XCTAssertNil(EntryCommand.parse("599"), "an RST is not a QSY")
        XCTAssertNil(EntryCommand.parse("12345"))
        XCTAssertNil(EntryCommand.parse("14"), "bare small number is ambiguous")
        XCTAssertNil(EntryCommand.parse("6.000"), "6 MHz is out of band")
    }

    func testParseBand() {
        XCTAssertEqual(EntryCommand.parse("40M"), .band(.m40))
        XCTAssertEqual(EntryCommand.parse("20m"), .band(.m20))
        XCTAssertEqual(EntryCommand.parse("160M"), .band(.m160))
        XCTAssertEqual(EntryCommand.parse("70CM"), .band(.cm70))
        XCTAssertEqual(EntryCommand.parse("1.25M"), .band(.cm125))
    }

    /// "222" is what an operator types for 1.25 m — the only band whose spoken
    /// name is not its ADIF string. It has to beat the numeric branch, which
    /// would otherwise read it as 222 kHz and reject it.
    func testParse222AliasFor125Meters() {
        XCTAssertEqual(EntryCommand.parse("222"), .band(.cm125))
        XCTAssertEqual(EntryCommand.parse(" 222 "), .band(.cm125))
        XCTAssertEqual(EntryCommand.parse("223500"), .frequency(kHz: 223500))
        XCTAssertNil(EntryCommand.parse("160"), "bare band numbers stay unparsed for every other band")
    }

    func testParseMode() {
        XCTAssertEqual(EntryCommand.parse("CW"), .mode("CW"))
        XCTAssertEqual(EntryCommand.parse("ssb"), .mode("SSB"))
        XCTAssertEqual(EntryCommand.parse("USB"), .mode("USB"))
        XCTAssertEqual(EntryCommand.parse("lsb"), .mode("LSB"))
        XCTAssertEqual(EntryCommand.parse("rtty"), .mode("RTTY"))
        XCTAssertEqual(EntryCommand.parse("AM"), .mode("AM"))
        XCTAssertEqual(EntryCommand.parse("FM"), .mode("FM"))
    }

    func testCallsignsAreNotCommands() {
        XCTAssertNil(EntryCommand.parse("K5ABC"))
        XCTAssertNil(EntryCommand.parse("W1AW"))
        XCTAssertNil(EntryCommand.parse("KE5CW"))
        XCTAssertNil(EntryCommand.parse("N0AX/M"))
        XCTAssertNil(EntryCommand.parse(""))
        XCTAssertNil(EntryCommand.parse("   "))
    }

    func testWhitespaceTolerated() {
        XCTAssertEqual(EntryCommand.parse("  14025 "), .frequency(kHz: 14025))
        XCTAssertEqual(EntryCommand.parse(" cw "), .mode("CW"))
    }
}
