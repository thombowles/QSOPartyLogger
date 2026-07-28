import XCTest
@testable import QSOPartyLogger

/// Name exchanges — parties whose exchange is an operator name plus a
/// location, with no signal report at all. NAQP rule 10: "Operator name and
/// station location (state, province, or country) for North American
/// stations"; MNQP: "MN Stations: First name & county (three letter
/// designator)." See docs/superpowers/specs/2026-07-27-name-exchanges-design.md.
final class NameExchangeTests: XCTestCase {

    var seq: TimeInterval = 0
    func qso(
        call: String = "N2CU",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "NY",
        nameSent: String? = nil,
        nameRcvd: String? = nil
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: "", rstRcvd: "",
            nameSent: nameSent, nameRcvd: nameRcvd,
            myLoc: my, theirLoc: their
        )
    }

    /// A minimal party, optionally with the name flag — decoded rather than
    /// registered, because the capability ships before any bundled party
    /// carries it.
    func party(_ extra: String = "") throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"n","name":"N","cabrilloContest":"N","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}]\(extra)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    // MARK: Defaults — nothing changes for the parties that send a report

    func testNamesDefaultToNilOnTheModel() {
        let q = QSO(
            timestampUTC: Date(), call: "W1A", band: .m40, modeClass: .cw,
            rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "HIL", theirLoc: "TX"
        )
        XCTAssertNil(q.nameSent)
        XCTAssertNil(q.nameRcvd)
    }

    /// A log written before name support must decode unchanged.
    func testLogsWithoutNameKeysStillDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","groupID":"\(UUID().uuidString)",
         "timestampUTC":770000000,"call":"W1ABC","band":"40m","modeClass":"cw",
         "rawMode":"CW","rstSent":"599","rstRcvd":"599","myLoc":"HIL","theirLoc":"TX"}
        """
        let decoded = try JSONDecoder().decode(QSO.self, from: Data(json.utf8))
        XCTAssertNil(decoded.nameSent)
        XCTAssertNil(decoded.nameRcvd)
    }

    /// Documents written before the setting existed open with an empty
    /// exchange name; the value round-trips once set.
    func testExchangeNameDefaultsEmptyAndRoundTrips() throws {
        let old = try ContestLog.decode(from: ContestLog(partyID: "ksqp").encoded())
        XCTAssertEqual(old.exchangeName, "")

        var log = ContestLog(partyID: "ksqp")
        log.exchangeName = "TOM"
        let reopened = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(reopened.exchangeName, "TOM")
    }

    func testFlagDecodesFromJSON() throws {
        XCTAssertFalse(try party().exchangeIncludesName, "absent means no")
        XCTAssertTrue(try party(",\"exchangeIncludesName\":true").exchangeIncludesName)

        // The NAQP/MNQP shape: a name, a location, and no report at all.
        let nameNoRST = try party(",\"exchangeIncludesName\":true,\"exchangeIncludesRST\":false")
        XCTAssertTrue(nameNoRST.exchangeIncludesName)
        XCTAssertFalse(nameNoRST.exchangeIncludesRST)
        XCTAssertFalse(nameNoRST.exchangeIncludesSerial)
    }

    /// The capability ships first and no bundled party uses it — each flag
    /// flip is its own commit (NAQP CW, NAQP SSB, then the MNQP fix).
    func testNoBundledPartyExchangesANameYet() {
        let withNames = PartyCatalog.loadBundled().filter(\.exchangeIncludesName).map(\.id)
        XCTAssertEqual(withNames, [])
    }

    // MARK: One contact, one name

    func testOneNamePerContactAcrossACountyLine() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W0GXQ", rstSent: "", rstRcvd: "",
                nameSent: "TOM", nameRcvd: "JON",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date()
            ),
            myLocs: ["TX"],
            theirLocs: ["KNB", "MIL"]
        )
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row.nameSent, "TOM")
            XCTAssertEqual(row.nameRcvd, "JON")
        }
        XCTAssertEqual(Set(rows.map(\.groupID)).count, 1)
    }

    // MARK: Cabrillo

    /// Name → serial → report, driven by the row's own data.
    func testExchangeElementPrefersNameThenSerialThenReport() {
        XCTAssertEqual(CabrilloExporter.exchangeElement(name: "TOM", serial: 5, rst: "599"), "TOM")
        XCTAssertEqual(CabrilloExporter.exchangeElement(name: nil, serial: 5, rst: "599"), "5")
        XCTAssertEqual(CabrilloExporter.exchangeElement(name: nil, serial: nil, rst: "599"), "599")
        XCTAssertEqual(CabrilloExporter.exchangeElement(name: "tom", serial: nil, rst: ""), "TOM",
                       "names export uppercased, like calls and locations")
    }

    /// The sponsors' own template: `AC0W BILL MOW N2CU TOM NY` — the name
    /// sits in the ex1 slot ahead of each side's location.
    func testCabrilloLineForANamePartyCarriesNameThenLocation() {
        let line = CabrilloExporter.qsoLine(
            qso(my: "TX", their: "NY", nameSent: "Tom", nameRcvd: "Bill"),
            myCall: "KE5CW"
        )
        let fields = line.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(6)), ["KE5CW", "TOM", "TX", "N2CU", "BILL", "NY"])
    }

    /// A row with no names renders exactly as it always has (Article 4).
    func testCabrilloLineWithoutNamesIsUnchanged() {
        let plain = QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000),
            call: "W1AW", band: .m20, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "579", myLoc: "HIL", theirLoc: "CT"
        )
        let fields = CabrilloExporter.qsoLine(plain, myCall: "KE5CW")
            .split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(6)), ["KE5CW", "599", "HIL", "W1AW", "579", "CT"])
    }

    // MARK: ADIF

    func testAdifCarriesNamesOnlyWhenPresent() throws {
        let named = AdifExporter.record(
            qso(nameSent: "TOM", nameRcvd: "BILL"),
            myCall: "KE5CW", party: try party(), countyNames: [:], myState: "TX"
        )
        XCTAssertTrue(named.contains("<name:4>BILL"), named)
        XCTAssertTrue(named.contains("<my_name:3>TOM"), named)

        let plain = AdifExporter.record(
            qso(), myCall: "KE5CW", party: try party(), countyNames: [:], myState: "TX"
        )
        XCTAssertFalse(plain.contains("<name:"), plain)
        XCTAssertFalse(plain.contains("<my_name:"), plain)
    }

    // MARK: The {NAME} macro

    func testNameMacroExpandsToTheSentName() {
        let text = AppSettings.expandMacros(
            "{CALL} {NAME} {EXCH}",
            myCall: "KE5CW", call: "N2CU", rst: "599",
            exchange: "TX", name: "TOM"
        )
        XCTAssertEqual(text, "N2CU TOM TX")
    }

    func testNameMacroExpandsEmptyWhenNoNameIsSet() {
        let text = AppSettings.expandMacros(
            "{NAME} {EXCH}", myCall: "KE5CW", call: "", rst: "599", exchange: "TX"
        )
        XCTAssertEqual(text, "TX", "an unset name vanishes, like an unset serial")
    }

    // MARK: Default messages

    /// The default exchange message follows the party's exchange shape — the
    /// mechanism that gives CQP `{SERIAL}` gives a name party `{NAME}`, ahead
    /// of the location because that is the order it is sent in ("TOM TX").
    func testDefaultMessagesForANamePartySendNameThenLocation() throws {
        let nameParty = try party(",\"exchangeIncludesName\":true,\"exchangeIncludesRST\":false")
        let sets = MessageSets.defaults(for: nameParty)
        XCTAssertTrue(sets.searchPounce.contains("{NAME} {EXCH}"), "\(sets.searchPounce)")
        XCTAssertFalse(sets.searchPounce.contains { $0.contains("{RST}") },
                       "a name party sends no report")

        let plain = MessageSets.defaults(for: try party())
        XCTAssertFalse(plain.run.contains { $0.contains("{NAME}") },
                       "report parties are untouched")
    }

    // MARK: The entry row

    /// A name party will not log a contact without a received name — rule 12
    /// counts only "a complete, correctly copied and logged two-way
    /// exchange", and a nameless row is the blank-ex1 export this design
    /// exists to end.
    func testMissingNameGateForNameParties() throws {
        let entry = EntryState()
        let nameParty = try party(",\"exchangeIncludesName\":true")

        XCTAssertTrue(entry.missingName(party: nameParty))
        entry.nameRcvd = "  "
        XCTAssertTrue(entry.missingName(party: nameParty), "whitespace is not a name")
        entry.nameRcvd = "BILL"
        XCTAssertFalse(entry.missingName(party: nameParty))

        entry.nameRcvd = ""
        XCTAssertFalse(entry.missingName(party: try party()),
                       "parties without a name exchange never gate on one")
        XCTAssertFalse(entry.missingName(party: nil))
    }

    /// Hunting a station costs nothing: what was copied for a call that was
    /// never logged stashes with the exchange and comes back with it.
    func testPendingStashCarriesTheName() {
        let entry = EntryState()
        let pending = EntryState.Pending(exchange: "NY", serialRcvd: "", nameRcvd: "BILL")
        XCTAssertFalse(pending.isEmpty)
        entry.restorePending(pending)
        XCTAssertEqual(entry.nameRcvd, "BILL")
        XCTAssertEqual(entry.exchange, "NY")

        let nameOnly = EntryState.Pending(exchange: "", serialRcvd: "", nameRcvd: "BILL")
        XCTAssertFalse(nameOnly.isEmpty, "a copied name alone is worth keeping")
    }

    func testClearForNextContactResetsTheName() {
        let entry = EntryState()
        entry.nameRcvd = "BILL"
        entry.clearForNextContact(modeClass: .cw)
        XCTAssertEqual(entry.nameRcvd, "")
    }
}
