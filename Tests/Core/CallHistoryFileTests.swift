import XCTest
@testable import QSOPartyLogger

/// The N1MM call history text format, tested against lines taken verbatim
/// from the files downloaded 2026-07-28 (see docs/research/n1mm_callhistory.md
/// — each fixture names its file). The format is documented at
/// n1mmwp.hamdocs.com/setup/call-history/; the variations are what the
/// hand-maintained files actually do.
final class CallHistoryFileTests: XCTestCase {

    // MARK: !!Order!! handling

    /// QSOP_AL-2026-002.txt: directive first, trailing comma.
    func testAlabamaShapeParses() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        #
        # 0-This is helping file, LOG what you copy.
        # QSOP_AL
        # QSOPARTY AL
        AA4GA,,,MOBILE
        AE4BL,,CHOU
        AI4AL,,ETOW,Etowah (ETOW)
        """)
        XCTAssertEqual(parsed.recordCount, 3)
        XCTAssertEqual(parsed.entry(for: "AI4AL")?.locations, ["ETOW"])
        XCTAssertEqual(parsed.entry(for: "AI4AL")?.userText, "Etowah (ETOW)")
        XCTAssertNil(parsed.entry(for: "AI4AL")?.name)
        XCTAssertEqual(parsed.entry(for: "AA4GA")?.locations, [],
                       "a mobile with no fixed county offers no location")
        XCTAssertEqual(parsed.entry(for: "AA4GA")?.userText, "MOBILE")
    }

    /// QSOP_WA-2025-002.txt: spaces around the field names.
    func testOrderDirectiveTokensAreTrimmed() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!, Call, Name, Exch1, UserText
        K7RAT,Tree,KLI
        """)
        let entry = parsed.entry(for: "K7RAT")
        XCTAssertEqual(entry?.name, "TREE")
        XCTAssertEqual(entry?.locations, ["KLI"])
    }

    /// QSOP_PA-2025-003.txt: five comment lines *before* the directive.
    func testOrderDirectiveAfterComments() {
        let parsed = CallHistoryFile.parse("""
        # Current contest: Pa QSO Party
        #
        # QSOPARTY PA
        # QSOP_PA
        !!Order!!,Call,Exch1,UserText
        AA1ON,EMA
        AC5AA,TRAV,,
        """)
        XCTAssertEqual(parsed.entry(for: "AA1ON")?.locations, ["EMA"],
                       "a section rides Exch1 exactly like a county")
        XCTAssertEqual(parsed.entry(for: "AC5AA")?.locations, ["TRAV"])
        XCTAssertNil(parsed.entry(for: "AC5AA")?.name,
                     "this order has no Name column — TRAV must not become one")
    }

    /// QSOP_NE-2026-002.txt opens with a blank line before the directive.
    func testLeadingBlankLinesTolerated() {
        let parsed = CallHistoryFile.parse("""

        !!Order!!,Call,Exch1,UserText,
        AA0W,DIXO,Dixon
        """)
        XCTAssertEqual(parsed.entry(for: "AA0W")?.locations, ["DIXO"])
    }

    /// NAQPCW-004.txt: the location lives in State, not Exch1.
    func testStateColumnIsALocationCandidate() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,State,UserText,
        # NAQPCW
        AA0AC,DAVE,MN,
        8P5A,TOM,8P,
        7L3PXO,MASA,,
        """)
        XCTAssertEqual(parsed.entry(for: "AA0AC")?.name, "DAVE")
        XCTAssertEqual(parsed.entry(for: "AA0AC")?.locations, ["MN"])
        XCTAssertEqual(parsed.entry(for: "8P5A")?.locations, ["8P"],
                       "a DX prefix is a candidate; the party's parser decides")
        XCTAssertEqual(parsed.entry(for: "7L3PXO")?.locations, [],
                       "name-only entries still surface the name")
        XCTAssertEqual(parsed.entry(for: "7L3PXO")?.name, "MASA")
    }

    /// Exch1 outranks Sect outranks State when several are present.
    func testLocationCandidateOrder() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,State,Sect,Exch1
        W1AW,CT,CT,HARTFORD
        """)
        XCTAssertEqual(parsed.entry(for: "W1AW")?.locations,
                       ["HARTFORD", "CT", "CT"],
                       "candidate order is Exch1, Sect, State — not file order")
    }

    /// No directive at all: the documented default order applies
    /// (Call, Name, Loc1, Loc2, Sect, State, CK, BirthDate, Exch1, …).
    func testDefaultOrderWhenNoDirective() {
        let parsed = CallHistoryFile.parse("""
        # a file with no order line
        N9RV,ROB,,,MT,MT,-1,1900-01-01,,,,
        """)
        let entry = parsed.entry(for: "N9RV")
        XCTAssertEqual(entry?.name, "ROB")
        XCTAssertEqual(entry?.locations, ["MT", "MT"], "Sect then State")
    }

    /// Unknown field names hold their position without being stored.
    func testUnknownFieldsAreSkippedPositionally() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,CK,Name
        W9XYZ,68,ART
        """)
        let entry = parsed.entry(for: "W9XYZ")
        XCTAssertEqual(entry?.name, "ART")
        XCTAssertEqual(entry?.locations, [])
    }

    /// Directives other than !!Order!! (import flags) are ignored.
    func testOtherDirectivesIgnored() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Exch1
        !!MapStateToSect!!
        K5CM,GRAN
        """)
        XCTAssertEqual(parsed.recordCount, 1)
        XCTAssertEqual(parsed.entry(for: "K5CM")?.locations, ["GRAN"])
    }

    // MARK: Delimiters, comments, encodings

    /// The documentation allows semicolons as well as commas.
    func testSemicolonDelimitedRecords() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!;Call;Name;Exch1
        K0K;Ron;REN
        """)
        let entry = parsed.entry(for: "K0K")
        XCTAssertEqual(entry?.name, "RON")
        XCTAssertEqual(entry?.locations, ["REN"])
    }

    /// QSOP_AC-2026-005.txt: `VE1AON,,NSHRM/NSCOL,` — a county-line pair
    /// passes through untouched for the party's parser to judge.
    func testCountyLineValuePassesThrough() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        VE1AON,,NSHRM/NSCOL,
        """)
        XCTAssertEqual(parsed.entry(for: "VE1AON")?.locations, ["NSHRM/NSCOL"])
    }

    /// The last declared field swallows any extra delimiters, so free text
    /// with a comma survives (QSOP_TX: "Mobile with Melody KI4HVY" is real;
    /// commas inside it must not shear off).
    func testFinalFieldAbsorbsExtraDelimiters() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Exch1,UserText
        AD4EB,,Mobile with Melody, KI4HVY
        """)
        XCTAssertEqual(parsed.entry(for: "AD4EB")?.userText,
                       "Mobile with Melody, KI4HVY")
    }

    func testCRLFAndBlankLines() {
        let parsed = CallHistoryFile.parse(
            "!!Order!!,Call,Exch1\r\n\r\nW0BH,BAR\r\nK0VBU,JOH\r\n")
        XCTAssertEqual(parsed.recordCount, 2)
        XCTAssertEqual(parsed.entry(for: "K0VBU")?.locations, ["JOH"])
    }

    /// Duplicate call: later rows win per field, but never blank an earlier
    /// field — the real Alabama file lists WA1FCN with his county in one
    /// section and his name in another, and both halves must survive.
    func testDuplicateCallMergesByField() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1
        K0K,Ron,REN
        K0K,Kent,MCP
        WA1FCN,,WLKR
        WA1FCN,BOB,
        """)
        XCTAssertEqual(parsed.entry(for: "K0K")?.name, "KENT")
        XCTAssertEqual(parsed.entry(for: "K0K")?.locations, ["MCP"])
        XCTAssertEqual(parsed.entry(for: "WA1FCN")?.name, "BOB")
        XCTAssertEqual(parsed.entry(for: "WA1FCN")?.locations, ["WLKR"],
                       "the nameless county row must not be erased by the "
                       + "locationless name row")
        XCTAssertEqual(parsed.recordCount, 4)
    }

    /// Comment lines become the normalized token set the source verifies
    /// against — including Ohio's spaced variant.
    func testCommentTokens() {
        let parsed = CallHistoryFile.parse("""
        # QSO PARTY OH
        # QSOP_OH
        !!Order!!,Call,Exch1
        K8BL,LAKE
        """)
        XCTAssertTrue(parsed.tokens.contains("QSOPARTYOH"))
        XCTAssertTrue(parsed.tokens.contains("QSOP_OH"))
        let ohio = CallHistorySource(filePrefix: "QSOP_OH", token: "QSOPARTY OH")
        XCTAssertTrue(ohio.isDeclared(inCommentTokens: parsed.tokens))
    }

    func testUTF8AndWindows1252Data() throws {
        let utf8 = "!!Order!!,Call,Name,Exch1\n# Monteregie\nVA2CF,Fred,MEE\n"
        let fromUTF8 = try XCTUnwrap(CallHistoryFile.parse(data: Data(utf8.utf8)))
        XCTAssertEqual(fromUTF8.entry(for: "VA2CF")?.name, "FRED")

        // "Montérégie" in Windows-1252: é is 0xE9, invalid as UTF-8.
        var bytes = Data("!!Order!!,Call,Name\n# Mont".utf8)
        bytes.append(0xE9)
        bytes.append(Data("r".utf8))
        bytes.append(0xE9)
        bytes.append(Data("gie\nVA2AU,JEAN\n".utf8))
        let fallback = try XCTUnwrap(CallHistoryFile.parse(data: bytes))
        XCTAssertEqual(fallback.entry(for: "VA2AU")?.name, "JEAN")
    }

    // MARK: Lookup

    func testLookupNormalizesTypedCall() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Exch1
        AI4AL,ETOW
        """)
        XCTAssertNotNil(parsed.entry(for: " ai4al "))
    }

    /// The file has the bare call; the operator typed a portable suffix.
    /// QSOP_CA really lists `AA2IL/6` and QSOP_TX lists both `AD4EB` and
    /// `AD4EB/M` — exact match first, then the stripped base.
    func testSuffixStrippedFallback() {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Exch1
        AA2IL,SDIE
        AD4EB,GRAY
        AD4EB/M,COOK
        """)
        XCTAssertEqual(parsed.entry(for: "AA2IL/6")?.locations, ["SDIE"])
        XCTAssertEqual(parsed.entry(for: "AD4EB/M")?.locations, ["COOK"],
                       "an exact match is never overridden by stripping")
        XCTAssertEqual(parsed.entry(for: "W4/G3ABC")?.locations, nil,
                       "no entry, no invention")
    }

    // MARK: Real files, whole

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "txt"),
            "\(name).txt missing from Tests/Fixtures/CallHistory")
        return try Data(contentsOf: url)
    }

    /// The complete Alabama file as downloaded 2026-07-28 — 3371 records.
    /// Out-of-state stations ride Exch1 with their *state* ("WY7KY,TOM,WY,"),
    /// which is exactly why candidates are parse-checked per role rather
    /// than assumed to be counties.
    func testRealAlabamaFileDigestsWhole() throws {
        let parsed = try XCTUnwrap(
            CallHistoryFile.parse(data: fixture("QSOP_AL-2026-002")))
        XCTAssertEqual(parsed.recordCount, 3371)
        XCTAssertEqual(parsed.entry(for: "WA1FCN")?.locations, ["WLKR"])
        XCTAssertEqual(parsed.entry(for: "WA1FCN")?.name, "BOB",
                       "merged from the file's out-of-state roster section")
        XCTAssertEqual(parsed.entry(for: "WA1FCN")?.userText, "WALKER  (2026)")
        XCTAssertEqual(parsed.entry(for: "K4ZGB")?.userText, "MOBILE")
        XCTAssertEqual(parsed.entry(for: "WY7KY")?.locations, ["WY"])
        let source = CallHistorySource(filePrefix: "QSOP_AL", token: "QSOPARTY AL")
        XCTAssertTrue(source.isDeclared(inCommentTokens: parsed.tokens))

        let alqp = try party("alqp")
        let inStateView = CallHistoryFile.candidate(
            for: "WA1FCN", in: parsed, party: alqp, role: .outOfState)
        XCTAssertEqual(inStateView?.exchange, "WLKR")
    }

    /// The complete NAQP CW file as downloaded 2026-07-28 — 4535 records,
    /// location in the State column, DX by country "county".
    func testRealNAQPFileDigestsWhole() throws {
        let parsed = try XCTUnwrap(
            CallHistoryFile.parse(data: fixture("NAQPCW-004")))
        XCTAssertEqual(parsed.recordCount, 4535)
        XCTAssertEqual(parsed.entry(for: "K5ZD")?.name, "RANDY")
        XCTAssertEqual(parsed.entry(for: "K5ZD")?.locations, ["OH"])
        XCTAssertEqual(parsed.entry(for: "ZF5T")?.locations, ["ZF"])
        let source = CallHistorySource(filePrefix: "NAQPCW", token: "NAQPCW")
        XCTAssertTrue(source.isDeclared(inCommentTokens: parsed.tokens))

        let naqp = try party("naqpcw")
        let dx = CallHistoryFile.candidate(
            for: "ZF5T", in: parsed, party: naqp, role: .outOfState)
        XCTAssertEqual(dx?.exchange, "ZF", "Cayman Is. is an NAQP 'county'")
        XCTAssertEqual(dx?.name, "STAN")
    }

    // MARK: Party-checked candidates

    private func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: id), id)
    }

    /// The whole point: a value is offered only after the party's own parser
    /// accepts it for the operator's role.
    func testCandidateParseCheckedAgainstParty() throws {
        let ksqp = try party("ksqp")
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K0VBU,Bill,JOH,Johnson
        W5XYZ,,TX
        N0BAD,,ZZZZ
        """)
        let bill = CallHistoryFile.candidate(
            for: "K0VBU", in: parsed, party: ksqp, role: .outOfState)
        XCTAssertEqual(bill?.exchange, "JOH")
        XCTAssertNil(bill?.name, "KSQP exchanges no name — never offer one")

        let texan = CallHistoryFile.candidate(
            for: "W5XYZ", in: parsed, party: ksqp, role: .inState)
        XCTAssertEqual(texan?.exchange, "TX",
                       "an in-state operator works the world")

        XCTAssertNil(CallHistoryFile.candidate(
            for: "N0BAD", in: parsed, party: ksqp, role: .inState),
            "a value the party cannot parse is withheld entirely")
    }

    /// KSQP rejects its own home-state token — the file offering "KS" to an
    /// in-state statation must be suppressed by the same rule the entry field
    /// applies to typing.
    func testCandidateRespectsExcludedTokens() throws {
        let ksqp = try party("ksqp")
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Exch1
        W0KS,KS
        """)
        XCTAssertNil(CallHistoryFile.candidate(
            for: "W0KS", in: parsed, party: ksqp, role: .inState))
    }

    /// NAQP: name + location, DX by prefix — all three record shapes of the
    /// real file resolve.
    func testNAQPCandidates() throws {
        let naqp = try party("naqpcw")
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,State,UserText,
        AA0AC,DAVE,MN,
        8P5A,TOM,8P,
        7L3PXO,MASA,,
        """)
        let dave = CallHistoryFile.candidate(
            for: "AA0AC", in: parsed, party: naqp, role: .outOfState)
        XCTAssertEqual(dave?.exchange, "MN")
        XCTAssertEqual(dave?.name, "DAVE")

        let dx = CallHistoryFile.candidate(
            for: "8P5A", in: parsed, party: naqp, role: .outOfState)
        XCTAssertEqual(dx?.exchange, "8P", "prefix style accepts the country prefix")
        XCTAssertEqual(dx?.name, "TOM")

        let nameOnly = CallHistoryFile.candidate(
            for: "7L3PXO", in: parsed, party: naqp, role: .outOfState)
        XCTAssertNil(nameOnly?.exchange)
        XCTAssertEqual(nameOnly?.name, "MASA",
                       "a name alone is still worth offering in a name party")
    }

    /// A county-line pair at the party's limit parses; the candidate carries
    /// the pair for the expander to fan out later.
    func testCandidateCountyLine() throws {
        let tnqp = try party("tnqp")
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Exch1
        K4TCG,DAVI/WILS
        """)
        let candidate = CallHistoryFile.candidate(
            for: "K4TCG", in: parsed, party: tnqp, role: .outOfState)
        XCTAssertEqual(candidate?.exchange, "DAVI/WILS")
    }

    /// Nothing known, nothing offered.
    func testCandidateNilForUnknownCallOrEmptyEntry() throws {
        let ksqp = try party("ksqp")
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText
        AA4GA,,,MOBILE
        """)
        XCTAssertNil(CallHistoryFile.candidate(
            for: "N0SUCH", in: parsed, party: ksqp, role: .inState))
        XCTAssertNil(CallHistoryFile.candidate(
            for: "AA4GA", in: parsed, party: ksqp, role: .inState),
            "MOBILE user text with no county and no name offers nothing")
    }
}
