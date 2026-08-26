import XCTest
@testable import QSOPartyLogger

/// The two services' XML, parsed per their banked contracts
/// (docs/research/callbook/SOURCES.md). Fixtures are shaped verbatim on the
/// documented and live-probed responses.
final class CallbookParserTests: XCTestCase {

    // MARK: QRZ

    private let qrzLogin = """
        <?xml version="1.0" encoding="utf-8" ?>
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key>\
        <Count>123</Count><SubExp>non-subscriber</SubExp>\
        <GMTime>Mon Aug 25 00:00:00 2026</GMTime></Session>
        </QRZDatabase>
        """

    private let qrzLookup = """
        <?xml version="1.0" encoding="utf-8" ?>
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Callsign><call>W1AW</call><fname>ARRL HQ</fname><name>OPERATORS CLUB</name>\
        <addr2>Newington</addr2><state>CT</state><county>Hartford</county>\
        <grid>FN31pr</grid><country>United States</country><land>United States</land>\
        <dxcc>291</dxcc></Callsign>
        <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key>\
        <Message>A subscription is required to obtain the complete data.</Message>\
        </Session>
        </QRZDatabase>
        """

    private let qrzTimeout = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Error>Session Timeout</Error></Session>
        </QRZDatabase>
        """

    private let qrzNotFound = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key>\
        <Error>Not found: XX9XXX</Error></Session>
        </QRZDatabase>
        """

    func testQRZLoginParsesKey() throws {
        let session = try QRZXML.session(from: Data(qrzLogin.utf8))
        XCTAssertEqual(session.key, "2331uf894c4bd29f3923f3bacf02c532d7bd9")
        XCTAssertNil(session.error)
    }

    func testQRZLookupParsesRecordAndKeepsTheMessage() throws {
        let result = try QRZXML.lookup(from: Data(qrzLookup.utf8))
        let record = try XCTUnwrap(result.record)
        XCTAssertEqual(record.call, "W1AW")
        XCTAssertEqual(record.name, "ARRL HQ OPERATORS CLUB")
        XCTAssertEqual(record.qth, "Newington")
        XCTAssertEqual(record.state, "CT")
        XCTAssertEqual(record.county, "Hartford")
        XCTAssertEqual(record.grid, "FN31pr")
        // land, never the QSL-address country — here they agree, and the
        // parser must be reading the right one regardless.
        XCTAssertEqual(record.country, "United States")
        XCTAssertEqual(record.dxccID, 291)
        XCTAssertEqual(record.source, .qrz)
        XCTAssertEqual(result.message,
                       "A subscription is required to obtain the complete data.")
    }

    func testQRZSessionTimeoutSurfacesAsRetriableError() throws {
        let result = try QRZXML.lookup(from: Data(qrzTimeout.utf8))
        XCTAssertNil(result.record)
        XCTAssertEqual(result.error, "Session Timeout")
        XCTAssertTrue(QRZXML.isSessionExpiry(result.error))
        XCTAssertFalse(QRZXML.isRefusal(result.error))
    }

    func testQRZNotFoundIsAMissNotAFailure() throws {
        let result = try QRZXML.lookup(from: Data(qrzNotFound.utf8))
        XCTAssertNil(result.record)
        XCTAssertEqual(result.error, "Not found: XX9XXX")
        XCTAssertFalse(QRZXML.isSessionExpiry(result.error))
        XCTAssertTrue(QRZXML.isNotFound(result.error))
    }

    func testQRZRefusalIsRecognised() {
        XCTAssertTrue(QRZXML.isRefusal("Connection refused"))
        XCTAssertFalse(QRZXML.isRefusal("Not found: W1AW"))
    }

    func testQRZURLsEncodeCredentials() {
        let login = QRZXML.loginURL(username: "ke5cw",
                                    password: "p&ss;word",
                                    agent: "QSOPartyLogger/1.5")
        let s = login.absoluteString
        XCTAssertTrue(s.hasPrefix("https://xmldata.qrz.com/xml/current/?"))
        XCTAssertFalse(s.contains("p&ss;word"), "reserved characters must be encoded")
        let lookup = QRZXML.lookupURL(sessionKey: "abc123", call: "W1AW/P")
        XCTAssertTrue(lookup.absoluteString.contains("s=abc123"))
        XCTAssertFalse(lookup.absoluteString.contains("W1AW/P"),
                       "the slash in a portable call must be encoded")
    }

    // MARK: HamQTH

    private let hamqthLogin = """
        <?xml version="1.0"?>
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><session_id>09b0ae90050be03c452ad235a1f2915ad684393c</session_id></session>
        </HamQTH>
        """

    private let hamqthLookup = """
        <?xml version="1.0"?>
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <search><callsign>ok2cqr</callsign><nick>Petr</nick>\
        <qth>Neratovice</qth><country>Czech Republic</country><adif>503</adif>\
        <grid>JO70GG</grid><us_state></us_state><us_county></us_county></search>
        </HamQTH>
        """

    private let hamqthExpired = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><error>Session does not exist or expired</error></session>
        </HamQTH>
        """

    private let hamqthNotFound = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><error>Callsign not found</error></session>
        </HamQTH>
        """

    func testHamQTHLoginParsesSessionID() throws {
        let session = try HamQTHXML.session(from: Data(hamqthLogin.utf8))
        XCTAssertEqual(session.id, "09b0ae90050be03c452ad235a1f2915ad684393c")
        XCTAssertNil(session.error)
    }

    func testHamQTHLookupParsesRecord() throws {
        let result = try HamQTHXML.lookup(from: Data(hamqthLookup.utf8))
        let record = try XCTUnwrap(result.record)
        XCTAssertEqual(record.call, "OK2CQR")
        XCTAssertEqual(record.name, "Petr")
        XCTAssertEqual(record.qth, "Neratovice")
        XCTAssertEqual(record.grid, "JO70GG")
        XCTAssertNil(record.state, "an empty us_state is absent, not \"\"")
        XCTAssertEqual(record.country, "Czech Republic")
        XCTAssertEqual(record.dxccID, 503)
        XCTAssertEqual(record.source, .hamqth)
    }

    func testHamQTHExpiryAndMissAreDistinguished() throws {
        let expired = try HamQTHXML.lookup(from: Data(hamqthExpired.utf8))
        XCTAssertTrue(HamQTHXML.isSessionExpiry(expired.error))
        let miss = try HamQTHXML.lookup(from: Data(hamqthNotFound.utf8))
        XCTAssertTrue(HamQTHXML.isNotFound(miss.error))
        XCTAssertFalse(HamQTHXML.isSessionExpiry(miss.error))
    }

    func testHamQTHURLsCarryPrgAndEncode() {
        let login = HamQTHXML.loginURL(username: "ke5cw", password: "a b&c")
        XCTAssertTrue(login.absoluteString.hasPrefix("https://www.hamqth.com/xml.php?"))
        XCTAssertFalse(login.absoluteString.contains("a b&c"))
        let lookup = HamQTHXML.lookupURL(sessionID: "s1", call: "W1AW",
                                         program: "QSOPartyLogger")
        XCTAssertTrue(lookup.absoluteString.contains("prg=QSOPartyLogger"))
        XCTAssertTrue(lookup.absoluteString.contains("callsign=W1AW"))
    }

    func testMalformedXMLThrowsRatherThanReturningAPhantomMiss() {
        XCTAssertThrowsError(try QRZXML.lookup(from: Data("not xml".utf8)))
        XCTAssertThrowsError(try HamQTHXML.session(from: Data("<broken".utf8)))
    }
}
