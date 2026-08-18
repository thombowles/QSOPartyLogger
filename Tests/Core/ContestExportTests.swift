import XCTest
@testable import QSOPartyLogger

/// The exporters on `ContestDefinition`: the QSO line derived from the
/// exchange spec, `LOCATION:` from `CabrilloSpec`, the new header lines and
/// ADIF fields for a general contest, and `OFFTIME:` from the operating-time
/// rule. Party bytes are pinned by `ExportByteIdentityTests`.
final class ContestExportTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_795_824_120)   // 2026-11-28 00:02:00Z

    func cqww() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    func cqwwLog(_ c: ContestDefinition) -> ContestLog {
        var log = ContestLog(partyID: c.id)
        log.station.callsign = "KE5CW"; log.station.name = "Tom Bowles"; log.station.exchangeDefaults = ["state": "TX"]
        log.station.categoryOverlay = "CLASSIC"; log.station.categoryBand = "20M"
        log.sideID = "all"; log.sentExchange = ["rst": ["599"], "zone": ["4"]]
        log.qsos = [QSO(timestampUTC: t, call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                        sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14"])]
        return log
    }

    func testCQWWQSOLineHeaderAndLocation() throws {
        let c = try cqww(), log = cqwwLog(c)
        XCTAssertEqual(CabrilloExporter.qsoLine(log.qsos[0], myCall: "KE5CW", contest: c, side: "all"),
                       "QSO: 14042 CW 2026-11-28 0002 KE5CW         599 4      DL1AA         599 14     0")
        let text = CabrilloExporter.export(log: log, contest: c, score: ScoreEngine.score(log: log, contest: c))
        let lines = text.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("CONTEST: CQ-WW-CW"))
        XCTAssertTrue(lines.contains("LOCATION: TX"), "no location element: exchangeDefaults.state")
        XCTAssertTrue(lines.contains("CATEGORY-BAND: 20M"))
        XCTAssertTrue(lines.contains("CATEGORY-OVERLAY: CLASSIC"))
        XCTAssertFalse(text.contains("CATEGORY-TIME:"))
        XCTAssertTrue(lines.contains("CLAIMED-SCORE: 6"), "3 points × (zone + country)")
        var dx = log; dx.station.exchangeDefaults = [:]
        XCTAssertEqual(CabrilloExporter.location(log: dx, contest: c), "DX")
    }

    func testCallEchoAndSectionLocation() throws {
        // A Sweepstakes-shaped spec: nr prec call ck sect, no report column.
        let sections = try XCTUnwrap(TokenSet.sections())
        let ss = ContestDefinition(
            id: "ss", name: "SS", family: .domestic, bands: [.m20], modeClasses: [.cw],
            sides: [Side(id: "all", label: "Everyone", predicate: .always, workedPredicate: .always)],
            exchange: [ExchangeElement(id: "serial", kind: .serial, sentBy: ["all": .init()], cabrilloWidth: 4),
                       ExchangeElement(id: "precedence", kind: .precedence, sentBy: ["all": .init()], letters: ["Q", "A", "B", "U", "M", "S"]),
                       ExchangeElement(id: "call", kind: .callEcho, sentBy: ["all": .init()]),
                       ExchangeElement(id: "check", kind: .check, sentBy: ["all": .init()]),
                       ExchangeElement(id: "section", kind: .token, sentBy: ["all": .init(sets: ["sections"])], fixed: true, cabrilloWidth: 3)],
            multipliers: [MultiplierClass(id: "section", term: "section", resolvers: [Resolver(kind: .receivedToken, element: "section", set: "sections")],
                                          counting: ["all": .once], roster: "sections")],
            points: [PointRule(points: 2)], dupe: DupeRule(scope: .contest),
            cabrillo: CabrilloSpec(contest: "ARRL-SS-CW", location: .section))
        try ss.validate()
        _ = sections
        var log = ContestLog(partyID: ss.id)
        log.station.callsign = "KE5CW"; log.sideID = "all"; log.sentExchange = ["precedence": ["A"], "check": ["65"], "section": ["NTX"]]
        let q = QSO(timestampUTC: t, call: "K1ABC", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                    sent: ["serial": "1", "precedence": "A", "check": "65", "section": "NTX"],
                    rcvd: ["serial": "17", "precedence": "B", "check": "72", "section": "EMA"])
        log.qsos = [q]
        XCTAssertEqual(CabrilloExporter.qsoLine(q, myCall: "KE5CW", contest: ss, side: "all"),
                       "QSO: 14042 CW 2026-11-28 0002 KE5CW         1    A KE5CW         65 NTX K1ABC         17   B K1ABC         72 EMA")
        XCTAssertEqual(CabrilloExporter.location(log: log, contest: ss), "NTX")
    }

    func testReportColumnWritesTheRowsReportOrTheModeDefault() throws {
        let md = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "mdc")))
        XCTAssertTrue(md.cabrillo.reportColumn)
        let c0 = try XCTUnwrap(PartyCatalog.party(id: "mdc")).counties[0].abbr
        let withReport = QSO(timestampUTC: t, call: "W3XYZ", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                             rstSent: "599", rstRcvd: "579", myLoc: c0, theirLoc: "PA")
        let without = QSO(timestampUTC: t, call: "W3XYZ", band: .m20, modeClass: .phone, rawMode: "SSB", freqKHz: 14250,
                          sent: ["location": c0], rcvd: ["location": "PA"])
        XCTAssertEqual(CabrilloExporter.qsoLine(withReport, myCall: "KE5CW", contest: md, side: "inside"),
                       "QSO: 14042 CW 2026-11-28 0002 KE5CW         599 \(c0.padded(to: 6)) W3XYZ         579 PA    ")
        XCTAssertEqual(CabrilloExporter.qsoLine(without, myCall: "KE5CW", contest: md, side: "inside"),
                       "QSO: 14250 PH 2026-11-28 0002 KE5CW         59  \(c0.padded(to: 6)) W3XYZ         59  PA    ")
    }

    func testOffTimeLinesFollowTheOperatingRule() throws {
        let c = try cqww()
        var log = cqwwLog(c)
        let day = Date(timeIntervalSince1970: 1_795_824_000)
        func at(_ hhmm: Int) -> Date { day.addingTimeInterval(TimeInterval((hhmm / 100) * 3600 + (hhmm % 100) * 60)) }
        log.qsos = [QSO(timestampUTC: at(0114), call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW", sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14"]),
                    QSO(timestampUTC: at(0230), call: "F5ABC", band: .m20, modeClass: .cw, rawMode: "CW", sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14"])]
        let text = CabrilloExporter.export(log: log, contest: c, score: ScoreEngine.score(log: log, contest: c))
        XCTAssertTrue(text.components(separatedBy: "\n").contains("OFFTIME: 2026-11-28 0115 2026-11-28 0229"), text)
        var rookie = log; rookie.station.categoryOverlay = "ROOKIE"
        XCTAssertFalse(CabrilloExporter.export(log: rookie, contest: c, score: .init()).contains("OFFTIME:"))
    }

    func testAdifCarriesZonesEntityAndContinentForAGeneralContest() throws {
        let c = try cqww(), log = cqwwLog(c)
        let adif = AdifExporter.export(log: log, contest: c)
        XCTAssertTrue(adif.hasPrefix("Generated by QSO Party Logger — CQ World Wide DX Contest, CW\n"))
        for field in ["<cqz:2>14", "<my_cq_zone:1>4", "<dxcc:3>230", "<cont:2>EU", "<contest_id:8>CQ-WW-CW", "<rst_sent:3>599", "<rst_rcvd:3>599"] {
            XCTAssertTrue(adif.contains(field), field)
        }
        XCTAssertFalse(adif.contains("stx_string"), "no location element")
        XCTAssertFalse(adif.contains("<state:"))
    }

    func testAdifSectionCheckPrecedenceClassGridPower() throws {
        let sides = [Side(id: "all", label: "Everyone", predicate: .always, workedPredicate: .always)]
        let c = ContestDefinition(
            id: "x", name: "X", family: .domestic, bands: [.m20], modeClasses: [.cw], sides: sides,
            exchange: [ExchangeElement(id: "precedence", kind: .precedence, sentBy: ["all": .init()], letters: ["A", "B"]),
                       ExchangeElement(id: "check", kind: .check, sentBy: ["all": .init()]),
                       ExchangeElement(id: "section", kind: .token, sentBy: ["all": .init(sets: ["sections"])]),
                       ExchangeElement(id: "class", kind: .classToken, sentBy: ["all": .init()], letters: ["A", "B"], minNumber: 1),
                       ExchangeElement(id: "grid", kind: .grid, sentBy: ["all": .init()]),
                       ExchangeElement(id: "power", kind: .power, sentBy: ["all": .init()])],
            multipliers: [], points: [PointRule(points: 1)], dupe: DupeRule(scope: .band),
            cabrillo: CabrilloSpec(contest: "X", location: .section))
        try c.validate()
        var log = ContestLog(partyID: c.id); log.station.callsign = "KE5CW"; log.sideID = "all"
        log.qsos = [QSO(timestampUTC: t, call: "K1ABC", band: .m20, modeClass: .cw, rawMode: "CW",
                        sent: ["precedence": "A", "check": "65", "section": "NTX", "class": "1B", "grid": "EM13", "power": "100"],
                        rcvd: ["precedence": "B", "check": "72", "section": "EMA", "class": "3A", "grid": "FN42AB", "power": "KW"])]
        let adif = AdifExporter.export(log: log, contest: c)
        for field in ["<precedence:1>B", "<check:2>72", "<arrl_sect:3>EMA", "<my_arrl_sect:3>NTX", "<class:2>3A",
                      "<gridsquare:6>FN42AB", "<my_gridsquare:4>EM13", "<tx_pwr:3>100"] {
            XCTAssertTrue(adif.contains(field), field)
        }
        XCTAssertFalse(adif.contains("rx_pwr"), "KW is not a number; ADIF RX_PWR is")
    }
}
