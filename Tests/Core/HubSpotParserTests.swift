import XCTest
@testable import QSOPartyLogger

/// Parsing the qsopartyhub.com spot table.
///
/// Every fixture is a real page captured from the live site — the SDQP one
/// from the only populated capture in 551 Wayback snapshots, the ALQP pair
/// recorded during the running 2026 contest. Provenance:
/// `docs/research/qsopartyhub.md`.
final class HubSpotParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "html"),
                                "missing fixture \(name).html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: id))
    }

    private static func utc(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    // MARK: Real captures

    /// The live Alabama capture of 2026-07-25 22:56Z, in full.
    func testLiveAlabamaCaptureParsesEveryRow() throws {
        let alqp = try party("alqp")
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-late"),
                                         party: alqp)

        XCTAssertFalse(result.headerMismatch)
        XCTAssertEqual(result.spots.map(\.call),
                       ["W5LNX", "W4NBS", "N4NM", "KC4TEO", "KC4TE"])
        XCTAssertEqual(result.spots.map(\.county),
                       ["CHIL", "LAWR", "MDSN", "MDSN", "MDSN"])
        XCTAssertEqual(result.spots.map(\.spotter),
                       ["W6ECK", "N4EMP", "N4EMP", "N4EMP", "N4EMP"])
        XCTAssertTrue(result.spots.allSatisfy { $0.source == .hub })
    }

    /// Frequencies from that capture, including the trailing-zero form.
    func testLiveAlabamaFrequenciesAndTimes() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-late"),
                                         party: try party("alqp"))
        let byCall = Dictionary(uniqueKeysWithValues: result.spots.map { ($0.call, $0) })

        XCTAssertEqual(try XCTUnwrap(byCall["W5LNX"]).freqKHz, 14314, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(byCall["W4NBS"]).freqKHz, 7041.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(byCall["N4NM"]).freqKHz, 7043.4, accuracy: 0.001,
                       "7043.40 — a trailing zero is not a different frequency")
        XCTAssertEqual(try XCTUnwrap(byCall["W5LNX"]).receivedAt,
                       Self.utc("2026-07-25 22:55:48"))
    }

    /// The comment is carried verbatim. `59 CA` is an exchange being passed,
    /// not a mode hint or a county — it must not be mined for either.
    func testExchangeInCommentIsCarriedButNotMistakenForACounty() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-late"),
                                         party: try party("alqp"))
        let w5lnx = try XCTUnwrap(result.spots.first { $0.call == "W5LNX" })
        XCTAssertEqual(w5lnx.comment, "59 CA")
        XCTAssertEqual(w5lnx.county, "CHIL", "the QTH column wins; CA is not an ALQP county")
    }

    /// The 2024 South Dakota capture — seven rows, and the widest spread of
    /// operator-typed frequency formats anywhere in the corpus.
    func testSouthDakota2024CaptureParsesEveryRow() throws {
        let result = HubSpotParser.parse(html: try fixture("sdqp-table-2024-10-12"),
                                         party: try party("sdqp"))

        XCTAssertFalse(result.headerMismatch)
        XCTAssertEqual(result.spots.map(\.call),
                       ["KT0A", "W0JT", "N4LDB", "KE0Z", "KC0MVF", "KE0Z", "N4LDB"])
        XCTAssertEqual(try XCTUnwrap(result.spots.first).freqKHz, 14041, accuracy: 0.001,
                       "14.041 is MHz")
        XCTAssertEqual(try XCTUnwrap(result.spots.first).county, "FALL")
    }

    /// `N4LDB` put the county in the comment rather than the QTH column.
    /// `CHAR` is Charles Mix — a real multiplier that would otherwise be lost.
    func testCountyIsRecoveredFromTheCommentWhenQTHIsBlank() throws {
        let result = HubSpotParser.parse(html: try fixture("sdqp-table-2024-10-12"),
                                         party: try party("sdqp"))
        let recovered = result.spots.filter { $0.call == "N4LDB" && $0.county == "CHAR" }
        XCTAssertEqual(recovered.count, 1,
                       "the county in the comment column is still a county")
    }

    // MARK: The busy live capture

    /// A later, busier capture from the same contest, with six spotters
    /// instead of one — the hub is a general spotting board, not a
    /// self-spot-only one.
    func testBusyLiveCaptureUsesEverySpotter() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-busy"),
                                         party: try party("alqp"))
        XCTAssertEqual(Set(result.spots.map(\.spotter)),
                       ["NI8W", "KB9LGS", "W1SSN", "N9DEK", "W6ECK"])
    }

    /// `NI8W` typed `1042.3`, then re-posted `14042.3` twenty-five seconds
    /// later. The typo is not a frequency under any reading — 1042.3 kHz is
    /// below 160 m, 1.0423 GHz is nothing, 104.23 kHz is nothing — so it is
    /// refused and surfaced, while the corrected spot parses normally.
    func testSpottersTypoIsRejectedWhileTheCorrectionParses() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-busy"),
                                         party: try party("alqp"))
        let n4uc = result.spots.filter { $0.call == "N4UC" }
        XCTAssertEqual(n4uc.count, 1, "only the corrected spot survives")
        XCTAssertEqual(try XCTUnwrap(n4uc.first).freqKHz, 14042.3, accuracy: 0.001)
        XCTAssertTrue(result.rejected.contains { $0.contains("1042.3") },
                      "the unreadable row is surfaced, never silently dropped")
    }

    /// `W1SSN` posted `7.0745` — MHz to four decimals. It resolves, and is
    /// flagged reconstructed because it was not a frequency as written.
    func testMegahertzToFourDecimalsResolves() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-busy"),
                                         party: try party("alqp"))
        let spot = try XCTUnwrap(result.spots.first { $0.spotter == "W1SSN" })
        XCTAssertEqual(spot.freqKHz, 7074.5, accuracy: 0.001)
        XCTAssertEqual(spot.frequencyConfidence, .reconstructed)
    }

    /// A portable callsign keeps its suffix — `WA1FCN/4` is who to call.
    func testPortableCallsignSurvivesIntact() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-busy"),
                                         party: try party("alqp"))
        let portable = try XCTUnwrap(result.spots.first { $0.call.contains("/") })
        XCTAssertEqual(portable.call, "WA1FCN/4")
        XCTAssertEqual(portable.county, "WLKR")
    }

    /// Every county token in the busy capture is a real Alabama county, so the
    /// multiplier badge is working from the party's own list throughout.
    func testEveryCountyInTheBusyCaptureIsRealForThatParty() throws {
        let alqp = try party("alqp")
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-busy"),
                                         party: alqp)
        let abbrs = Set(alqp.counties.map(\.abbr))
        XCTAssertFalse(result.spots.isEmpty)
        for spot in result.spots {
            XCTAssertTrue(abbrs.contains(try XCTUnwrap(spot.county)),
                          "\(spot.call) reported \(spot.county ?? "nil")")
        }
    }

    // MARK: Frequency ladder

    /// Every operator-typed frequency in the corpus, and how it must resolve.
    /// `143095` is the load-bearing case: it is not a valid kHz reading, since
    /// 143.095 MHz falls in the gap below 2 m, so it can only be a dropped
    /// decimal point.
    func testFrequencyLadderAcrossEveryRealSample() {
        let cases: [(String, Double, HubFrequency.Confidence)] = [
            ("14.041", 14041, .reconstructed),
            ("14.0677", 14067.7, .reconstructed),
            ("143095", 14309.5, .reconstructed),
            ("14045.25", 14045.25, .reported),
            ("14226", 14226, .reported),
            ("21330", 21330, .reported),
            ("7041.4", 7041.4, .reported),
            ("7043.40", 7043.4, .reported),
            ("7047.0", 7047, .reported),
            ("14314", 14314, .reported),
        ]
        for (raw, expected, confidence) in cases {
            let resolved = HubFrequency.normalize(raw)
            XCTAssertEqual(resolved?.kHz ?? -1, expected, accuracy: 0.001, "raw \(raw)")
            XCTAssertEqual(resolved?.confidence, confidence, "raw \(raw)")
        }
    }

    /// Anything that lands on no amateur band at all is not a frequency.
    func testUnresolvableFrequenciesAreRejected() {
        for raw in ["", "abc", "0", "99999999", "-14040"] {
            XCTAssertNil(HubFrequency.normalize(raw), "raw \(raw)")
        }
    }

    /// A frequency outside the party's own band list is refused rather than
    /// tuned. ALQP runs 80–10 m, so a 2 m entry is not an ALQP spot.
    func testFrequencyOutsideThePartysBandsIsRejected() throws {
        let alqp = try party("alqp")
        XCTAssertFalse(alqp.validBands.contains(.m2), "precondition")

        let html = Self.table(rows: [
            "<tr class='age1bg'><td>2026-07-25 22:00:00</td><td>K4TEST</td>"
                + "<td>144200</td><td>MDSN</td><td></td><td>N4EMP</td></tr>"
        ])
        let result = HubSpotParser.parse(html: html, party: alqp)
        XCTAssertTrue(result.spots.isEmpty)
        XCTAssertEqual(result.rejected.count, 1)
    }

    // MARK: Contract gates

    /// Rows are read positionally, so the header is a hard gate. A hub-side
    /// column insertion would otherwise slide the county into the comment and
    /// the app would present wrong multiplier data with total confidence.
    func testAnUnexpectedHeaderParsesNothingAndSaysSo() throws {
        let html = """
        <table id=spots><tr><th>TIME (UTC)</th><th>SPOT</th><th>FREQ</th><th>MODE</th>\
        <th>QTH</th><th>COMMENT</th><th>POSTER</th></tr>\
        <tr class='age1bg'><td>2026-07-25 22:00:00</td><td>K4TEST</td><td>7040</td>\
        <td>CW</td><td>MDSN</td><td></td><td>N4EMP</td></tr></table>
        """
        let result = HubSpotParser.parse(html: html, party: try party("alqp"))
        XCTAssertTrue(result.headerMismatch)
        XCTAssertTrue(result.spots.isEmpty, "never guess at a changed layout")
    }

    /// An empty table is the normal off-contest state, not an error.
    func testEmptyTableYieldsNoSpotsAndNoComplaint() throws {
        let result = HubSpotParser.parse(html: try fixture("paqp-table-empty"),
                                         party: try party("paqp"))
        XCTAssertFalse(result.headerMismatch)
        XCTAssertTrue(result.spots.isEmpty)
        XCTAssertTrue(result.rejected.isEmpty)
    }

    /// The California stub returns a well-formed but permanently empty table.
    /// It must read as "nothing here", never as an error worth retrying.
    func testCaliforniaStubTableIsSimplyEmpty() throws {
        let result = HubSpotParser.parse(html: try fixture("caqp-table-stub"),
                                         party: try party("cqp"))
        XCTAssertFalse(result.headerMismatch)
        XCTAssertTrue(result.spots.isEmpty)
    }

    /// A 404 body, a truncated page, or plain nonsense must not crash or
    /// invent spots.
    func testGarbageInputYieldsNothing() throws {
        let alqp = try party("alqp")
        for html in ["", "404 Not Found", "<html><body>nope</body></html>",
                     "<table id=spots><tr><th>TIME (UTC)</th>"] {
            let result = HubSpotParser.parse(html: html, party: alqp)
            XCTAssertTrue(result.spots.isEmpty, "input: \(html.prefix(30))")
        }
    }

    // MARK: County aliasing

    /// Illinois: the hub's `PULS` is translated to the official `PULA`, or the
    /// spot would carry a multiplier the party does not have.
    func testIllinoisCountyAliasIsAppliedInbound() throws {
        let html = Self.table(rows: [
            "<tr class='age1bg'><td>2026-07-25 22:00:00</td><td>K9TEST</td>"
                + "<td>7040</td><td>PULS</td><td></td><td>K9TEST</td></tr>"
        ])
        let result = HubSpotParser.parse(html: html, party: try party("ilqp"))
        XCTAssertEqual(result.spots.first?.county, "PULA")
    }

    /// A QTH that is not a county in this party is dropped rather than passed
    /// through as a multiplier that cannot exist.
    func testUnknownCountyTokenIsNotCarried() throws {
        let html = Self.table(rows: [
            "<tr class='age1bg'><td>2026-07-25 22:00:00</td><td>K4TEST</td>"
                + "<td>7040</td><td>ZZZZ</td><td></td><td>N4EMP</td></tr>"
        ])
        let result = HubSpotParser.parse(html: html, party: try party("alqp"))
        XCTAssertEqual(result.spots.count, 1, "the spot is still real")
        XCTAssertNil(result.spots.first?.county)
    }

    // MARK: Superseded spots

    /// Live ALQP, four minutes apart on one frequency: `KC4TE` then `KC4TEO`
    /// with the comment `RIGHT CALL`. The hub keeps both. Shown naively the
    /// band map carries a phantom station beside the real one.
    func testBustedCallIsMarkedSupersededByItsCorrection() throws {
        let result = HubSpotParser.parse(html: try fixture("alqp-table-2026-07-25-late"),
                                         party: try party("alqp"))
        let busted = try XCTUnwrap(result.spots.first { $0.call == "KC4TE" })
        let correct = try XCTUnwrap(result.spots.first { $0.call == "KC4TEO" })

        XCTAssertTrue(busted.isSuperseded, "the older, one-edit-away call is the typo")
        XCTAssertFalse(correct.isSuperseded)
    }

    /// Two genuinely different stations on one frequency are not a correction.
    func testDistinctCallsOnOneFrequencyAreBothKept() throws {
        let html = Self.table(rows: [
            "<tr class='age1bg'><td>2026-07-25 22:05:00</td><td>W1AAA</td>"
                + "<td>7040</td><td>MDSN</td><td></td><td>N4EMP</td></tr>",
            "<tr class='age1bg'><td>2026-07-25 22:00:00</td><td>K9ZZZ</td>"
                + "<td>7040</td><td>MDSN</td><td></td><td>N4EMP</td></tr>",
        ])
        let result = HubSpotParser.parse(html: html, party: try party("alqp"))
        XCTAssertEqual(result.spots.count, 2)
        XCTAssertTrue(result.spots.allSatisfy { !$0.isSuperseded })
    }

    // MARK: Helpers

    /// A minimal page carrying the real header and the site's unclosed
    /// `agekey` table, which is what rules out a strict parser.
    private static func table(rows: [String]) -> String {
        """
        <div><table id=agekey><tr><td>less than 6 minutes</td></tr>\
        <table id=spots><tr><th>TIME (UTC)</th><th>SPOT</th><th>FREQ</th>\
        <th>QTH</th><th>COMMENT</th><th>POSTER</th></tr>\
        \(rows.joined())</table></div>
        """
    }
}
