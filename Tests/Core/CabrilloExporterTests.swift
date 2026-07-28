import XCTest
@testable import QSOPartyLogger

final class CabrilloExporterTests: XCTestCase {

    var ksqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
    }

    // 2026-08-29 14:32:00 UTC
    let t = Date(timeIntervalSince1970: 1_788_013_920)

    func makeLog() -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.station.name = "Tom Bowles"
        log.station.city = "Amarillo"
        log.station.stateProvince = "TX"
        log.station.categoryPower = .low
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [
            QSO(
                timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"
            )
        ]
        return log
    }

    func testGoldenQSOLine() {
        let q = makeLog().qsos[0]
        XCTAssertEqual(
            CabrilloExporter.qsoLine(q, myCall: "KE5CW"),
            "QSO: 14042 CW 2026-08-29 1432 KE5CW         599 TX     W0BH          599 MRN   "
        )
    }

    func testHeaderFields() {
        let log = makeLog()
        let score = ScoreEngine.score(log: log, party: ksqp)
        let text = CabrilloExporter.export(log: log, party: ksqp, score: score)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "START-OF-LOG: 3.0")
        XCTAssertTrue(text.hasSuffix("END-OF-LOG:\n"))
        XCTAssertTrue(lines.contains("CONTEST: KS-QSO-PARTY"))
        XCTAssertTrue(lines.contains("CALLSIGN: KE5CW"))
        XCTAssertTrue(lines.contains("LOCATION: TX"))
        XCTAssertTrue(lines.contains("CATEGORY-OPERATOR: SINGLE-OP"))
        XCTAssertTrue(lines.contains("CATEGORY-ASSISTED: NON-ASSISTED"),
                      "the default claim, stated rather than implied")
        XCTAssertTrue(lines.contains("CATEGORY-MODE: CW"))
        XCTAssertTrue(lines.contains("CATEGORY-POWER: LOW"))
        XCTAssertTrue(lines.contains("CATEGORY-TRANSMITTER: ONE"))
        XCTAssertTrue(lines.contains("CLAIMED-SCORE: 3"), "3 pts × 1 mult")
        XCTAssertTrue(lines.contains("OPERATORS: KE5CW"))
        XCTAssertTrue(lines.contains("NAME: Tom Bowles"))
        XCTAssertFalse(text.contains("GRID-LOCATOR:"), "no grid entered, no header")
    }

    /// The reference for content and placement is KE5CW's January 2026 NAQP
    /// CW log as N1MM wrote it: ASSISTED directly under the operator class,
    /// the grid between the address block and the email.
    func testEntryHeadersForAnAssistedMultiTwoEntry() throws {
        var log = makeLog()
        log.station.categoryOperator = .multiOp
        log.station.categoryAssisted = .assisted
        log.station.categoryTransmitter = .two
        log.station.operators = "ke5cw n0xyz @k5hog"
        log.station.gridLocator = "em13le"
        log.station.email = "op@example.com"
        let text = CabrilloExporter.export(log: log, party: ksqp, score: .init())
        let lines = text.components(separatedBy: "\n")

        let op = try XCTUnwrap(lines.firstIndex(of: "CATEGORY-OPERATOR: MULTI-OP"))
        XCTAssertEqual(lines[op + 1], "CATEGORY-ASSISTED: ASSISTED")
        XCTAssertTrue(lines.contains("CATEGORY-TRANSMITTER: TWO"))
        XCTAssertTrue(lines.contains("OPERATORS: KE5CW N0XYZ @K5HOG"),
                      "uppercased, spec's @host convention intact")

        let grid = try XCTUnwrap(lines.firstIndex(of: "GRID-LOCATOR: EM13LE"),
                                 "grid uppercased on the way out")
        let country = try XCTUnwrap(lines.firstIndex(of: "ADDRESS-COUNTRY: USA"))
        let email = try XCTUnwrap(lines.firstIndex(of: "EMAIL: op@example.com"))
        XCTAssertTrue(country < grid && grid < email, "the reference log's placement")
    }

    func testInStateLocationUsesHomeState() {
        var log = makeLog()
        log.myLocation = .inState(counties: ["MRN"])
        let text = CabrilloExporter.export(log: log, party: ksqp, score: .init())
        XCTAssertTrue(text.components(separatedBy: "\n").contains("LOCATION: KS"))
    }

    func testCountyLineGroupEmitsFourLines() {
        var log = makeLog()
        log.myLocation = .inState(counties: ["MRN", "CHS"])
        log.qsos = CountyLineExpander.expand(
            entry: .init(
                call: "N0XYZ", rstSent: "599", rstRcvd: "599", band: .m40,
                modeClass: .cw, rawMode: "CW", freqKHz: 7040, timestampUTC: t
            ),
            myLocs: ["MRN", "CHS"],
            theirLocs: ["LIN", "AND"]
        )
        let text = CabrilloExporter.export(log: log, party: ksqp, score: .init())
        let qsoLines = text.components(separatedBy: "\n").filter { $0.hasPrefix("QSO: ") }
        XCTAssertEqual(qsoLines.count, 4)
        let sentRcvd = qsoLines.map { line -> (String, String) in
            let cols = line.split(separator: " ").map(String.init)
            // QSO: freq mode date time mycall rstS sent call rstR rcvd
            return (cols[7], cols[10])
        }
        XCTAssertEqual(sentRcvd.map(\.0), ["MRN", "MRN", "CHS", "CHS"])
        XCTAssertEqual(sentRcvd.map(\.1), ["LIN", "AND", "LIN", "AND"])
    }

    func testFrequencyFallbackUsesBandDefault() {
        var log = makeLog()
        log.qsos[0].freqKHz = nil
        let text = CabrilloExporter.export(log: log, party: ksqp, score: .init())
        XCTAssertTrue(text.contains("QSO: 14040 CW"), "20m default 14040")
    }

    func testModeMapping() {
        XCTAssertEqual(CabrilloExporter.cabrilloMode("CW"), "CW")
        XCTAssertEqual(CabrilloExporter.cabrilloMode("SSB"), "PH")
        XCTAssertEqual(CabrilloExporter.cabrilloMode("USB"), "PH")
        XCTAssertEqual(CabrilloExporter.cabrilloMode("FM"), "FM")
        XCTAssertEqual(CabrilloExporter.cabrilloMode("RTTY"), "RY")
        XCTAssertEqual(CabrilloExporter.cabrilloMode("FT8"), "DG")
    }

    func testCategoryModeMixed() {
        var log = makeLog()
        log.qsos.append(
            QSO(
                timestampUTC: t.addingTimeInterval(60), call: "K0AA", band: .m20,
                modeClass: .phone, rawMode: "SSB", rstSent: "59", rstRcvd: "59",
                myLoc: "TX", theirLoc: "SHA"
            )
        )
        let text = CabrilloExporter.export(log: log, party: ksqp, score: .init())
        XCTAssertTrue(text.components(separatedBy: "\n").contains("CATEGORY-MODE: MIXED"))
    }
}
