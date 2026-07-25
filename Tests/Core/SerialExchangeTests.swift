import XCTest
@testable import QSOPartyLogger

/// Serial-number exchanges — parties that send a QSO number instead of (or as
/// well as) a signal report. CQP: "QSO number = contact serial number starting
/// with 1 for the first contact, progressing to 2 for the next contact."
/// See docs/superpowers/specs/2026-07-24-serial-number-exchanges-design.md.
final class SerialExchangeTests: XCTestCase {

    var seq: TimeInterval = 0
    func qso(
        call: String = "W6ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "SCLA",
        serialSent: Int? = nil,
        serialRcvd: Int? = nil
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: "", rstRcvd: "",
            serialSent: serialSent, serialRcvd: serialRcvd,
            myLoc: my, theirLoc: their
        )
    }

    // MARK: Defaults — nothing changes for the parties that send a report

    func testSerialsDefaultToNilOnTheModel() {
        let q = QSO(
            timestampUTC: Date(), call: "W1A", band: .m40, modeClass: .cw,
            rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "HIL", theirLoc: "TX"
        )
        XCTAssertNil(q.serialSent)
        XCTAssertNil(q.serialRcvd)
    }

    /// A log written before serial support must decode unchanged — the fields
    /// are optional precisely so an absent key is nil rather than an error.
    func testLogsWithoutSerialKeysStillDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","groupID":"\(UUID().uuidString)",
         "timestampUTC":770000000,"call":"W1ABC","band":"40m","modeClass":"cw",
         "rawMode":"CW","rstSent":"599","rstRcvd":"599","myLoc":"HIL","theirLoc":"TX"}
        """
        let decoded = try JSONDecoder().decode(QSO.self, from: Data(json.utf8))
        XCTAssertNil(decoded.serialSent)
        XCTAssertNil(decoded.serialRcvd)
        XCTAssertEqual(decoded.rstSent, "599")
    }

    /// The bundled parties that send a QSO number, named so a party cannot gain
    /// one incidentally.
    func testOnlyCQPAndPAQPExchangeASerial() throws {
        var withSerials: Set<String> = []
        for id in PartyCatalog.loadBundled().map(\.id) {
            if try XCTUnwrap(PartyCatalog.party(id: id)).exchangeIncludesSerial {
                withSerials.insert(id)
            }
        }
        XCTAssertEqual(withSerials, ["cqp", "paqp"],
                       "CQP sends 'QSO number and 4-letter county'; PAQP a "
                           + "'Sequential serial number plus PA county, ARRL section'")
    }

    func testFlagDecodesFromJSON() throws {
        func party(_ extra: String) throws -> PartyDefinition {
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
        XCTAssertFalse(try party("").exchangeIncludesSerial, "absent means no")
        XCTAssertTrue(try party(",\"exchangeIncludesSerial\":true").exchangeIncludesSerial)

        // RST and serial are independent — all four combinations are legal.
        let both = try party(",\"exchangeIncludesSerial\":true,\"exchangeIncludesRST\":true")
        XCTAssertTrue(both.exchangeIncludesSerial)
        XCTAssertTrue(both.exchangeIncludesRST)
        let neither = try party(",\"exchangeIncludesRST\":false")
        XCTAssertFalse(neither.exchangeIncludesSerial)
        XCTAssertFalse(neither.exchangeIncludesRST)
    }

    // MARK: The next number

    func testNextSerialStartsAtOneAndFollowsTheHighestSent() {
        var log = ContestLog(partyID: "cqp")
        XCTAssertEqual(log.nextSerial, 1, "first contact of the contest")

        log.qsos = [qso(serialSent: 1), qso(serialSent: 2)]
        XCTAssertEqual(log.nextSerial, 3)
    }

    /// Row count would be wrong: a county-line contact is several rows and one
    /// number, so counting rows would skip numbers the operator never sent.
    func testNextSerialCountsContactsNotRows() {
        var log = ContestLog(partyID: "cqp")
        log.qsos = CountyLineExpander.expand(
            entry: .init(
                call: "W6CL", rstSent: "", rstRcvd: "",
                serialSent: 1, serialRcvd: 42,
                band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date()
            ),
            myLocs: ["TX"],
            theirLocs: ["DELN", "SISK", "HUMB"]
        )
        XCTAssertEqual(log.qsos.count, 3, "three rows")
        XCTAssertEqual(log.nextSerial, 2, "but only one number was sent")
    }

    /// Deleting a QSO must not renumber the rest: those numbers went out on the
    /// air and the other station logged them.
    func testDeletingAQSODoesNotRenumber() {
        var log = ContestLog(partyID: "cqp")
        log.qsos = [qso(call: "A", serialSent: 1), qso(call: "B", serialSent: 2),
                    qso(call: "C", serialSent: 3)]
        log.qsos.removeAll { $0.call == "B" }
        XCTAssertEqual(log.qsos.compactMap(\.serialSent), [1, 3], "the gap is the honest record")
        XCTAssertEqual(log.nextSerial, 4, "and the sequence carries on from the highest")
    }

    // MARK: One contact, one number, across a county line

    func testCountyLineRowsShareOneNumberAndOneGroup() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W6CL", rstSent: "", rstRcvd: "",
                serialSent: 7, serialRcvd: 123,
                band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date()
            ),
            myLocs: ["TX"],
            theirLocs: ["DELN", "SISK", "HUMB"]
        )
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.serialSent)), [7], "the operator sent one number")
        XCTAssertEqual(Set(rows.map(\.serialRcvd)), [123], "and received one")
        XCTAssertEqual(Set(rows.map(\.groupID)).count, 1)
        XCTAssertEqual(rows.map(\.theirLoc), ["DELN", "SISK", "HUMB"])
    }

    /// My own county line multiplies rows too; the number still does not.
    func testBothSidesOfACountyLineShareTheNumber() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W6X", rstSent: "", rstRcvd: "",
                serialSent: 5, serialRcvd: 9,
                band: .m40, modeClass: .phone, rawMode: "SSB",
                freqKHz: nil, timestampUTC: Date()
            ),
            myLocs: ["ALAM", "CCOS"],
            theirLocs: ["SCLA", "SMAT"]
        )
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(Set(rows.map(\.serialSent)), [5])
        XCTAssertEqual(Set(rows.map(\.serialRcvd)), [9])
    }

    func testExpanderLeavesSerialsNilWhenThePartyHasNone() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W1A", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date()
            ),
            myLocs: ["TX"],
            theirLocs: ["HIL"]
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].serialSent)
        XCTAssertNil(rows[0].serialRcvd)
        XCTAssertEqual(rows[0].rstSent, "599", "the report still rides along")
    }

    // MARK: Cabrillo — the number goes where the report would

    func testCabrilloWritesTheNumberInTheExchangeSlot() {
        let line = CabrilloExporter.qsoLine(
            qso(call: "W6XYZ", their: "SCLA", serialSent: 12, serialRcvd: 345),
            myCall: "KE5CW"
        )
        // QSO: freq mode date time mycall <sent> myLoc call <rcvd> theirLoc
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(fields.first, "QSO:")
        XCTAssertTrue(fields.contains("12"), "sent number: \(line)")
        XCTAssertTrue(fields.contains("345"), "received number: \(line)")
        XCTAssertTrue(fields.contains("SCLA"))
        XCTAssertFalse(line.contains("599"), "there is no report in a CQP exchange")
    }

    func testCabrilloDoesNotZeroPadTheNumber() {
        let line = CabrilloExporter.qsoLine(qso(serialSent: 1, serialRcvd: 2), myCall: "KE5CW")
        XCTAssertFalse(line.contains("001"),
                       "CQP: 'It is unnecessary to send leading zeros in the QSO number'")
        XCTAssertEqual(CabrilloExporter.exchangeNumber(serial: 1, rst: ""), "1")
        XCTAssertEqual(CabrilloExporter.exchangeNumber(serial: 1234, rst: ""), "1234",
                       "four digits are not truncated by the column width")
    }

    /// The report is still what gets written wherever there is no number, which
    /// is what keeps every existing party's export byte-identical.
    func testCabrilloFallsBackToTheReport() {
        XCTAssertEqual(CabrilloExporter.exchangeNumber(serial: nil, rst: "599"), "599")
        let line = CabrilloExporter.qsoLine(
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_791_000_000),
                call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"
            ),
            myCall: "KE5CW"
        )
        XCTAssertTrue(line.contains("599"))
    }

    // MARK: ADIF — STX/SRX, distinct from the report fields

    func testAdifWritesSTXAndSRXOnlyWhenPresent() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var log = ContestLog(partyID: "cqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [qso(serialSent: 12, serialRcvd: 345)]
        let withSerials = AdifExporter.export(log: log, party: party)
        XCTAssertTrue(withSerials.lowercased().contains("<stx:2>12"), withSerials)
        XCTAssertTrue(withSerials.lowercased().contains("<srx:3>345"), withSerials)

        log.qsos = [qso()]
        let without = AdifExporter.export(log: log, party: party)
        XCTAssertFalse(without.lowercased().contains("<stx:"),
                       "no serial, no field — every other party's ADIF is unchanged")
        XCTAssertFalse(without.lowercased().contains("<srx:"))
    }

    // MARK: The CW macro

    func testSerialMacro() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{CALL} {SERIAL} {EXCH}",
                myCall: "KE5CW", call: "W6ABC", rst: "599", exchange: "SCLA", serial: "12"
            ),
            "W6ABC 12 SCLA"
        )
    }

    /// Message sets that never mention it expand exactly as before.
    func testSerialMacroDefaultsToEmptyAndLeavesRSTAlone() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{CALL} {RST} {EXCH}",
                myCall: "KE5CW", call: "W6ABC", rst: "599", exchange: "MRN"
            ),
            "W6ABC 599 MRN"
        )
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{SERIAL}", myCall: "K", call: "C", rst: "599", exchange: "X"
            ),
            "", "an unset number expands to nothing rather than to a wrong number"
        )
    }

    func testSerialMacroHonoursCutNumbers() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{SERIAL}",
                myCall: "KE5CW", call: "W6A", rst: "599", exchange: "SCLA",
                serial: "199", cutNumbers: true
            ),
            "1NN", "CW cut numbers apply to the QSO number as they do to the report"
        )
    }

    // MARK: Entry state

    func testEntryStateShowsTheNextNumberAndParsesWhatWasTyped() throws {
        let entry = EntryState()
        var next: Int? = 7
        entry.nextSerial = { next }
        XCTAssertEqual(entry.serialSent, "7")
        next = nil
        XCTAssertEqual(entry.serialSent, "", "parties without a number show no field")

        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        entry.serialSent = "7"
        entry.serialRcvd = " 345 "
        let serials = entry.serials(party: cqp)
        XCTAssertEqual(serials.sent, cqp.exchangeIncludesSerial ? 7 : nil)
        XCTAssertEqual(serials.rcvd, cqp.exchangeIncludesSerial ? 345 : nil)

        // Garbage yields nil rather than a wrong number.
        entry.serialRcvd = "abc"
        XCTAssertNil(entry.serials(party: cqp).rcvd)
    }

    /// Why ESM must expand before it logs: the number follows the log, and
    /// logging advances it. A message expanded after the append carries n+1
    /// while the logged row carries n — and the other station would log the
    /// number they heard, putting both of us out of the log.
    /// `EntryFlowTests` drives the real sequence; this pins the mechanism.
    func testTheNumberAdvancesTheMomentTheLogDoes() {
        let entry = EntryState()
        var next = 7
        entry.nextSerial = { next }
        XCTAssertEqual(entry.serialSent, "7")

        next = 8  // the append
        XCTAssertEqual(entry.serialSent, "8",
                       "so expanding {SERIAL} after logging keys the wrong number")
    }

    /// A number the operator typed belongs to the contact it was typed for.
    /// Carrying it into the next one would send the same number twice.
    func testClearForNextContactDropsTheOperatorsOwnNumber() {
        let entry = EntryState()
        entry.nextSerial = { 8 }
        entry.call = "W6ABC"
        entry.serialRcvd = "345"
        entry.serialSent = "17"
        XCTAssertTrue(entry.hasSerialOverride, "precondition")

        entry.clearForNextContact(modeClass: .cw)
        XCTAssertEqual(entry.call, "")
        XCTAssertFalse(entry.hasSerialOverride)
        XCTAssertEqual(entry.serialSent, "8", "back to following the log")
        XCTAssertEqual(entry.serialRcvd, "", "theirs is always typed fresh")
    }

    /// Where a party sends a number, Space from the call field lands on the one
    /// numeric field the operator has to type (Article 7 — keyboard-first).
    func testFocusOrderReachesTheReceivedNumber() {
        XCTAssertEqual(
            EntryBar.Field.call.next(includesRST: false, includesSerial: true), .serialRcvd
        )
        XCTAssertEqual(
            EntryBar.Field.serialRcvd.next(includesRST: false, includesSerial: true), .exchange
        )
        XCTAssertEqual(
            EntryBar.Field.serialSent.next(includesRST: false, includesSerial: true), .serialRcvd
        )
        // Unchanged where there is no number.
        XCTAssertEqual(EntryBar.Field.call.next(includesRST: true), .exchange)
        XCTAssertEqual(EntryBar.Field.rstSent.next(includesRST: true), .rstRcvd)
        XCTAssertEqual(EntryBar.Field.rstRcvd.next(includesRST: true), .exchange)
        XCTAssertEqual(EntryBar.Field.exchange.next(includesRST: true), .call)
    }

    // MARK: Scoring is untouched

    func testSerialsDoNotAffectScoring() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var withNumbers = ContestLog(partyID: "cqp")
        withNumbers.myLocation = .outOfState(location: "TX")
        withNumbers.qsos = [
            qso(call: "W6A", their: "SCLA", serialSent: 1, serialRcvd: 11),
            qso(call: "W6B", their: "ALAM", serialSent: 2, serialRcvd: 22),
        ]
        var without = withNumbers
        without.qsos = without.qsos.map { row in
            var r = row
            r.serialSent = nil
            r.serialRcvd = nil
            return r
        }
        XCTAssertEqual(
            ScoreEngine.score(log: withNumbers, party: party),
            ScoreEngine.score(log: without, party: party),
            "points and multipliers never depend on the QSO number"
        )
    }

    /// Two stations may legitimately send the same number, and a repeat of a
    /// number must not make a contact a dupe — only call/band/mode/county do.
    func testDupeCheckingIgnoresTheNumber() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var log = ContestLog(partyID: "cqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [
            qso(call: "W6A", their: "SCLA", serialSent: 1, serialRcvd: 5),
            qso(call: "W6B", their: "ALAM", serialSent: 2, serialRcvd: 5),
        ]
        let s = ScoreEngine.score(log: log, party: party)
        XCTAssertEqual(s.validQSOs, 2, "both stations sent 5; neither is a dupe")
        XCTAssertEqual(s.dupeCount, 0)
    }

    // MARK: Cut numbers (2026-07-25)

    /// 0→T and 9→N are near-universal in contest CW and are unconditional.
    func testStandardCutsAreAlwaysApplied() {
        XCTAssertEqual(AppSettings.applyCutNumbers("599"), "5NN")
        XCTAssertEqual(AppSettings.applyCutNumbers("40"), "4T")
        XCTAssertEqual(AppSettings.applyCutNumbers("100"), "1TT")
        XCTAssertEqual(AppSettings.applyCutNumbers("1780"), "178T")
    }

    /// 1→A has real currency but is not universal — a number cut in a way the
    /// receiving operator does not expect costs a repeat, so it is opt-in.
    func testCutOneIsOptIn() {
        XCTAssertEqual(AppSettings.applyCutNumbers("199", cutOne: false), "1NN")
        XCTAssertEqual(AppSettings.applyCutNumbers("199", cutOne: true), "ANN")
        XCTAssertEqual(AppSettings.applyCutNumbers("1780", cutOne: true), "A78T")
        XCTAssertEqual(AppSettings.applyCutNumbers("11", cutOne: true), "AA")
    }

    /// The digits nobody agreed to cut stay digits.
    func testOtherDigitsAreNeverCut() {
        XCTAssertEqual(AppSettings.applyCutNumbers("2345678", cutOne: true), "2345678")
    }

    func testCutNumbersReachBothTheReportAndTheNumber() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{RST} {SERIAL} {EXCH}",
                myCall: "KE5CW", call: "W6A", rst: "599", exchange: "SCLA",
                serial: "109", cutNumbers: true, cutOne: true
            ),
            "5NN ATN SCLA"
        )
    }

    /// Callsigns and county codes carry digits that are not numbers to be cut.
    /// The values here are chosen to contain 0, 1 and 9 — with `KE5CW` as the
    /// operator's own call, cutting `{MYCALL}` would pass unnoticed.
    func testCutNumbersNeverTouchCallsignsOrExchanges() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{CALL} {RST} {EXCH} DE {MYCALL}",
                myCall: "K9CT", call: "W0BH", rst: "599", exchange: "MRN90",
                cutNumbers: true, cutOne: true
            ),
            "W0BH 5NN MRN90 DE K9CT"
        )
    }

    /// Two independent Bools make `cutOne` without `cwCutNumbers` a
    /// representable state, and it must cut nothing at all — the sub-toggle
    /// never overrides the master.
    func testCutOneAloneCutsNothing() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{RST} {SERIAL}", myCall: "K", call: "C", rst: "599", exchange: "X",
                serial: "199", cutNumbers: false, cutOne: true
            ),
            "599 199", "the master toggle is off, so nothing is cut"
        )
    }
}
