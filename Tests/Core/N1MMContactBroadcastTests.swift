import XCTest
@testable import QSOPartyLogger

/// N1MM's contact packets, field for field from N1MM's own page
/// (docs/research/n1mm-udp-contactinfo.md), built from a log row the way
/// the ADIF exporter builds a record. One packet is pinned byte for byte.
final class N1MMContactBroadcastTests: XCTestCase {

    let t = Date(timeIntervalSince1970: 1_788_013_920)  // 2026-08-29 14:32:00Z
    let station = N1MMContactBroadcast.Station(stationName: "SHACK-MAC")

    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", n))! }

    func ksqp() throws -> ContestDefinition { try XCTUnwrap(ContestCatalog.contest(id: "ksqp")) }

    func ksqpLog(_ rows: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = rows
        return log
    }

    func w0bh(freq: Int? = 14042, rawMode: String = "CW", mode: ModeClass = .cw) -> QSO {
        QSO(id: id(1), timestampUTC: t, call: "W0BH", band: .m20, modeClass: mode, rawMode: rawMode,
            freqKHz: freq, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")
    }

    // MARK: The packet, byte for byte

    /// `app` says N1MM: RUMlogNG 6.5.1 saves a contact only when it does —
    /// verified 2026-09-07 against the running app (the same packet with
    /// `QSOPartyLogger` was dropped; with `N1MM` it was saved, and N1MM's
    /// contactdelete removed it again). Recorded in
    /// docs/research/n1mm-udp-contactinfo.md.
    func testAKSQPRowIsN1MMsContactInfoPacket() throws {
        let row = w0bh()
        let packet = N1MMContactBroadcast.contactInfo(
            row: row, log: ksqpLog([row]), contest: try ksqp(), station: station,
            scoring: .init(points: 2, isNewMultiplier: true))
        XCTAssertEqual(packet.kind, .info)
        XCTAssertEqual(packet.call, "W0BH")
        XCTAssertEqual(packet.xml, """
            <?xml version="1.0" encoding="utf-8"?>
            <contactinfo>
            \t<app>N1MM</app>
            \t<contestname>KS-QSO-PARTY</contestname>
            \t<contestnr>1</contestnr>
            \t<timestamp>2026-08-29 14:32:00</timestamp>
            \t<mycall>KE5CW</mycall>
            \t<band>14</band>
            \t<rxfreq>1404200</rxfreq>
            \t<txfreq>1404200</txfreq>
            \t<operator>KE5CW</operator>
            \t<mode>CW</mode>
            \t<call>W0BH</call>
            \t<countryprefix>K</countryprefix>
            \t<wpxprefix>W0</wpxprefix>
            \t<stationprefix>KE5CW</stationprefix>
            \t<continent>NA</continent>
            \t<snt>599</snt>
            \t<sntnr>0</sntnr>
            \t<rcv>599</rcv>
            \t<rcvnr>0</rcvnr>
            \t<gridsquare></gridsquare>
            \t<exchange1>MRN</exchange1>
            \t<section></section>
            \t<comment></comment>
            \t<qth></qth>
            \t<name></name>
            \t<power></power>
            \t<misctext></misctext>
            \t<zone>0</zone>
            \t<prec></prec>
            \t<ck>0</ck>
            \t<ismultiplier1>1</ismultiplier1>
            \t<ismultiplier2>0</ismultiplier2>
            \t<ismultiplier3>0</ismultiplier3>
            \t<points>2</points>
            \t<radionr>1</radionr>
            \t<run1run2>1</run1run2>
            \t<RoverLocation></RoverLocation>
            \t<RadioInterfaced>1</RadioInterfaced>
            \t<NetworkedCompNr>0</NetworkedCompNr>
            \t<IsOriginal>True</IsOriginal>
            \t<NetBiosName></NetBiosName>
            \t<IsRunQSO>0</IsRunQSO>
            \t<StationName>SHACK-MAC</StationName>
            \t<ID>00000000000040008000000000000001</ID>
            \t<IsClaimedQso>1</IsClaimedQso>
            \t<oldtimestamp>2026-08-29 14:32:00</oldtimestamp>
            \t<oldcall>W0BH</oldcall>
            \t<SentExchange>TX</SentExchange>
            \t<dxcc>291</dxcc>
            \t<my_gridsquare></my_gridsquare>
            </contactinfo>
            """)
        XCTAssertEqual(packet.data, Data(packet.xml.utf8))
    }

    // MARK: Field rules

    func testBandTokensAreTheLowerEdgeInMegahertz() {
        let expected: [Band: String] = [
            .m160: "1.8", .m80: "3.5", .m60: "5.3", .m40: "7", .m30: "10", .m20: "14", .m17: "18",
            .m15: "21", .m12: "24", .m10: "28", .m6: "50", .m2: "144", .cm125: "222", .cm70: "420",
        ]
        for band in Band.allCases {
            XCTAssertEqual(N1MMContactBroadcast.bandToken(band), expected[band], band.rawValue)
        }
    }

    func testFrequencyIsInTensOfHertzAndARowWithoutCATTakesTheBandDefault() {
        XCTAssertEqual(N1MMContactBroadcast.frequencyTens(w0bh(freq: 14042)), 1_404_200)
        XCTAssertEqual(N1MMContactBroadcast.frequencyTens(w0bh(freq: 7040)), 704_000)
        XCTAssertEqual(N1MMContactBroadcast.frequencyTens(w0bh(freq: nil)), Band.m20.defaultFreqKHz * 100)
    }

    func testARowWithoutCATSaysTheRadioWasNotInterfaced() throws {
        let row = w0bh(freq: nil)
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<RadioInterfaced>0</RadioInterfaced>"))
        XCTAssertTrue(xml.contains("<rxfreq>1404000</rxfreq>"))
    }

    /// N1MM's vocabulary has USB and LSB but no SSB: the sideband follows
    /// the frequency, the rule the radio path uses (`BandPlan`).
    func testSSBResolvesToTheBandsSidebandAndOtherModesPassThrough() {
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(freq: 14250, rawMode: "SSB", mode: .phone)), "USB")
        var forty = w0bh(freq: 7180, rawMode: "SSB", mode: .phone)
        forty.band = .m40
        XCTAssertEqual(N1MMContactBroadcast.mode(forty), "LSB")
        var noCAT = w0bh(freq: nil, rawMode: "SSB", mode: .phone)
        noCAT.band = .m80
        XCTAssertEqual(N1MMContactBroadcast.mode(noCAT), "LSB")
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(rawMode: "usb", mode: .phone)), "USB")
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(rawMode: "RTTY", mode: .digital)), "RTTY")
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(rawMode: "FT8", mode: .digital)), "FT8")
    }

    func testTimestampIsN1MMsFormatInUTC() {
        XCTAssertEqual(N1MMContactBroadcast.timestamp(t), "2026-08-29 14:32:00")
        XCTAssertEqual(N1MMContactBroadcast.timestamp(Date(timeIntervalSince1970: 0)), "1970-01-01 00:00:00")
    }

    func testIDIsTheRowsUUIDAsThirtyTwoLowerCaseHexCharacters() {
        let uuid = UUID(uuidString: "F9FFAC4F-CD3E-479C-A86E-137DF1338531")!
        XCTAssertEqual(N1MMContactBroadcast.id(uuid), "f9ffac4fcd3e479ca86e137df1338531")
        XCTAssertEqual(N1MMContactBroadcast.id(uuid).count, 32)
    }

    func testTextIsXMLEscaped() throws {
        var row = w0bh()
        row.notes = "Tom & Jerry <QRP> \"long\" 'path'"
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<comment>Tom &amp; Jerry &lt;QRP&gt; &quot;long&quot; &apos;path&apos;</comment>"), xml)
    }

    func testRunPostureAndTheEnginesCreditAreCarried() throws {
        var row = w0bh()
        row.posture = .run
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station,
                                                   scoring: .init(points: 3, isNewMultiplier: false)).xml
        XCTAssertTrue(xml.contains("<IsRunQSO>1</IsRunQSO>"))
        XCTAssertTrue(xml.contains("<points>3</points>"))
        XCTAssertTrue(xml.contains("<ismultiplier1>0</ismultiplier1>"))
    }

    func testADXCallWithNoCTYMatchLeavesTheEntityElementsEmpty() throws {
        var row = w0bh()
        row.call = "QQ9ZZZ"
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<countryprefix></countryprefix>"))
        XCTAssertTrue(xml.contains("<continent></continent>"))
        XCTAssertTrue(xml.contains("<dxcc></dxcc>"))
    }

    // MARK: Exchange shapes

    func testSerialsAndTheReceivedTokenForCQP() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "cqp"))
        var log = ContestLog(partyID: "cqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let row = QSO(id: id(2), timestampUTC: t, call: "N6XYZ", band: .m20, modeClass: .cw, rawMode: "CW",
                      freqKHz: 14042, rstSent: "599", rstRcvd: "599", serialSent: 12, serialRcvd: 7,
                      myLoc: "TX", theirLoc: "SCLA")
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<sntnr>12</sntnr>"))
        XCTAssertTrue(xml.contains("<rcvnr>7</rcvnr>"))
        XCTAssertTrue(xml.contains("<exchange1>SCLA</exchange1>"))
        XCTAssertTrue(xml.contains("<SentExchange>TX</SentExchange>"))
    }

    func testTheNameGoesToNameAndTheSentExchangeCarriesNameAndState() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "naqpcw"))
        var log = ContestLog(partyID: "naqpcw", exchangeName: "TOM")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let row = QSO(id: id(3), timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                      freqKHz: 14042, rstSent: "599", rstRcvd: "599", nameSent: "TOM", nameRcvd: "BOB",
                      myLoc: "TX", theirLoc: "CA")
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<name>BOB</name>"))
        XCTAssertTrue(xml.contains("<exchange1>CA</exchange1>"))
        XCTAssertTrue(xml.contains("<SentExchange>TOM TX</SentExchange>"), xml)
    }

    /// The member-or-power element: a power goes to `power` ("received power
    /// exchange from the other station"); a member number is not a power.
    func testAReceivedPowerGoesToPowerAndAMemberNumberDoesNot() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "skeeter"))
        var log = ContestLog(partyID: "skeeter", exchangeMember: "13")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let qrp = QSO(id: id(4), timestampUTC: t, call: "K3WWP", band: .m20, modeClass: .cw, rawMode: "CW",
                      freqKHz: 14060, rstSent: "599", rstRcvd: "599", memberSent: "13", memberRcvd: "5W",
                      myLoc: "TX", theirLoc: "PA")
        let member = QSO(id: id(5), timestampUTC: t, call: "W2LJ", band: .m20, modeClass: .cw, rawMode: "CW",
                         freqKHz: 14060, rstSent: "599", rstRcvd: "599", memberSent: "13", memberRcvd: "1",
                         myLoc: "TX", theirLoc: "NJ")
        log.qsos = [qrp, member]
        let qrpXML = N1MMContactBroadcast.contactInfo(row: qrp, log: log, contest: contest, station: station).xml
        XCTAssertTrue(qrpXML.contains("<power>5W</power>"), qrpXML)
        let memberXML = N1MMContactBroadcast.contactInfo(row: member, log: log, contest: contest, station: station).xml
        XCTAssertTrue(memberXML.contains("<power></power>"), memberXML)
    }

    /// A general contest's elements by kind: section, precedence, check,
    /// zone, grid, class, power — built from the CQ WW CW fixture with the
    /// exchange swapped, so no bundle has to carry a Sweepstakes.
    func generalContest(exchange: [[String: Any]]) throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["exchange"] = exchange
        json["id"] = "general-test"
        // The schedule's ISO dates need the catalog's decoder; nothing here reads it.
        json["schedule"] = nil
        return try JSONDecoder().decode(ContestDefinition.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testAGeneralContestsElementsLandByKind() throws {
        let contest = try generalContest(exchange: [
            ["id": "rst", "kind": "rst", "sentBy": ["all": [:]]],
            ["id": "nr", "kind": "serial", "sentBy": ["all": [:]]],
            ["id": "prec", "kind": "precedence", "sentBy": ["all": [:]]],
            ["id": "ck", "kind": "check", "sentBy": ["all": [:]]],
            ["id": "section", "kind": "token", "sentBy": ["all": [:]]],
            ["id": "zone", "kind": "cqZone", "sentBy": ["all": [:]]],
            ["id": "grid", "kind": "grid", "sentBy": ["all": [:]]],
            ["id": "class", "kind": "classToken", "sentBy": ["all": [:]]],
            ["id": "pwr", "kind": "power", "sentBy": ["all": [:]]],
        ])
        var log = ContestLog(partyID: contest.id)
        log.station.callsign = "KE5CW"
        log.station.gridLocator = "DM95"
        let row = QSO(id: id(6), timestampUTC: t, call: "W1AW", band: .m40, modeClass: .cw, rawMode: "CW", freqKHz: 7040,
                      sent: ["rst": "599", "nr": "12", "prec": "A", "ck": "88", "section": "WTX", "zone": "4",
                             "grid": "DM95", "class": "1D", "pwr": "100"],
                      rcvd: ["rst": "579", "nr": "345", "prec": "B", "ck": "71", "section": "CT", "zone": "5",
                             "grid": "FN31", "class": "2A", "pwr": "5"])
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<snt>599</snt>"))
        XCTAssertTrue(xml.contains("<rcv>579</rcv>"))
        XCTAssertTrue(xml.contains("<sntnr>12</sntnr>"))
        XCTAssertTrue(xml.contains("<rcvnr>345</rcvnr>"))
        XCTAssertTrue(xml.contains("<prec>B</prec>"))
        XCTAssertTrue(xml.contains("<ck>71</ck>"))
        XCTAssertTrue(xml.contains("<section>CT</section>"))
        XCTAssertTrue(xml.contains("<zone>5</zone>"))
        XCTAssertTrue(xml.contains("<gridsquare>FN31</gridsquare>"))
        XCTAssertTrue(xml.contains("<exchange1>2A</exchange1>"), xml)
        XCTAssertTrue(xml.contains("<power>5</power>"))
        XCTAssertTrue(xml.contains("<SentExchange>A 88 WTX 4 DM95 1D 100</SentExchange>"), xml)
        XCTAssertTrue(xml.contains("<my_gridsquare>DM95</my_gridsquare>"))
        XCTAssertTrue(xml.contains("<contestname>CQ-WW-CW</contestname>"))
    }

    func testAnITUZoneStandsInWhenThereIsNoCQZone() throws {
        let contest = try generalContest(exchange: [
            ["id": "rst", "kind": "rst", "sentBy": ["all": [:]]],
            ["id": "itu", "kind": "ituZone", "sentBy": ["all": [:]]],
        ])
        var log = ContestLog(partyID: contest.id)
        log.station.callsign = "KE5CW"
        let row = QSO(id: id(7), timestampUTC: t, call: "W1AW", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                      sent: ["rst": "599", "itu": "7"], rcvd: ["rst": "599", "itu": "8"])
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<zone>8</zone>"))
    }

    /// The callbook stamp fills only what the exchange left empty — the
    /// precedence ADIF uses.
    func testTheCallbookStampFillsNameQTHAndGridWhenTheExchangeHasNone() throws {
        var row = w0bh()
        row.callbook = .init(name: "Bob", qth: "Marion, KS", state: "KS", grid: "EM18", source: "QRZ")
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<name>Bob</name>"))
        XCTAssertTrue(xml.contains("<qth>Marion, KS</qth>"))
        XCTAssertTrue(xml.contains("<gridsquare>EM18</gridsquare>"))
    }

    // MARK: Replace and delete

    func testAReplaceCarriesTheOldCallAndTimeUnderItsOwnTag() throws {
        let old = w0bh()
        var new = old
        new.call = "W0BHX"
        new.timestampUTC = t.addingTimeInterval(60)
        let packet = N1MMContactBroadcast.contactReplace(row: new, replacing: old, log: ksqpLog([new]), contest: try ksqp(), station: station)
        XCTAssertEqual(packet.kind, .replace)
        XCTAssertEqual(packet.call, "W0BHX")
        XCTAssertTrue(packet.xml.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<contactreplace>\n"))
        XCTAssertTrue(packet.xml.hasSuffix("</contactreplace>"))
        XCTAssertTrue(packet.xml.contains("<call>W0BHX</call>"))
        XCTAssertTrue(packet.xml.contains("<timestamp>2026-08-29 14:33:00</timestamp>"))
        XCTAssertTrue(packet.xml.contains("<oldcall>W0BH</oldcall>"))
        XCTAssertTrue(packet.xml.contains("<oldtimestamp>2026-08-29 14:32:00</oldtimestamp>"))
        XCTAssertTrue(packet.xml.contains("<ID>00000000000040008000000000000001</ID>"))
    }

    func testADeleteIsN1MMsEightElements() throws {
        let row = w0bh()
        let packet = N1MMContactBroadcast.contactDelete(row: row, log: ksqpLog([row]), station: station)
        XCTAssertEqual(packet.kind, .delete)
        XCTAssertEqual(packet.xml, """
            <?xml version="1.0" encoding="utf-8"?>
            <contactdelete>
            \t<app>N1MM</app>
            \t<timestamp>2026-08-29 14:32:00</timestamp>
            \t<mycall>KE5CW</mycall>
            \t<band>14</band>
            \t<call>W0BH</call>
            \t<contestnr>1</contestnr>
            \t<StationName>SHACK-MAC</StationName>
            \t<ID>00000000000040008000000000000001</ID>
            </contactdelete>
            """)
    }

    // MARK: A change → packets

    func testAChangeBecomesPacketsInN1MMsOrder() throws {
        let contest = try ksqp()
        let a = w0bh()
        var b = w0bh()
        b.id = id(2)
        b.call = "N0XYZ"
        var b2 = b
        b2.theirLoc = "BOU"
        let log = ksqpLog([a, b2])
        let scoring: (QSO) -> N1MMContactBroadcast.RowScoring = {
            $0.call == "N0XYZ" ? .init(points: 4, isNewMultiplier: true) : .none
        }

        let added = N1MMContactBroadcast.packets(for: .added([a, b]), log: log, contest: contest, station: station, scoring: scoring)
        XCTAssertEqual(added.map(\.kind), [.info, .info])
        XCTAssertEqual(added.map(\.call), ["W0BH", "N0XYZ"])
        XCTAssertTrue(added[1].xml.contains("<points>4</points>"))

        let removed = N1MMContactBroadcast.packets(for: .removed([a]), log: log, contest: contest, station: station, scoring: scoring)
        XCTAssertEqual(removed.map(\.kind), [.delete])

        let replaced = N1MMContactBroadcast.packets(for: .replaced([.init(old: b, new: b2)]), log: log, contest: contest,
                                                    station: station, scoring: scoring)
        XCTAssertEqual(replaced.map(\.kind), [.delete, .replace], "N1MM: a delete, then a replace")
        XCTAssertTrue(replaced[1].xml.contains("<exchange1>BOU</exchange1>"))
        XCTAssertTrue(replaced[1].xml.contains("<ismultiplier1>1</ismultiplier1>"))
    }

    func testTheWholeLogIsEveryRowOldestFirst() throws {
        let contest = try ksqp()
        let later = w0bh()
        var earlier = w0bh()
        earlier.id = id(2)
        earlier.call = "N0XYZ"
        earlier.timestampUTC = t.addingTimeInterval(-300)
        let packets = N1MMContactBroadcast.wholeLog(log: ksqpLog([later, earlier]), contest: contest, station: station,
                                                    scoring: { _ in .none })
        XCTAssertEqual(packets.map(\.call), ["N0XYZ", "W0BH"])
        XCTAssertEqual(packets.map(\.kind), [.info, .info])
    }
}
