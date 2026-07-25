import XCTest
@testable import QSOPartyLogger

/// Default F1–F8 macros follow the party's exchange shape. Three bundled
/// parties send no signal report: CQP and PAQP send a QSO number instead
/// ("QSO number and 4-letter county abbreviation"), and MDC sends call and
/// location only ("You give your Call Sign and Location to each contacted
/// station"). A fixed {RST} default keys a report their sponsors do not want.
/// See docs/superpowers/specs/2026-07-25-serial-macros-cut-numbers-mode-default-design.md
final class MessageDefaultsTests: XCTestCase {

    /// The sixteen parties whose exchange carries a report and no number,
    /// named so a party cannot change shape unnoticed.
    static let rstPartyIDs = [
        "alqp", "azqp", "coqp", "hqp", "iaqp", "ilqp", "ksqp", "meqp",
        "nhqp", "njqp", "nyqp", "ohqp", "sdqp", "tnqp", "tqp", "warun",
    ]

    /// A synthetic party, so the both-flags shape can be pinned without
    /// waiting for a sponsor to publish one.
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

    // MARK: The table

    /// The Article 4 proof: every party that was correct before this change
    /// resolves to the exact macros it shipped with.
    func testTheSixteenReportPartiesKeepTheShippedDefaults() throws {
        XCTAssertEqual(Self.rstPartyIDs.count, 16)
        for id in Self.rstPartyIDs {
            let p = try XCTUnwrap(PartyCatalog.party(id: id), id)
            XCTAssertEqual(MessageSets.defaults(for: p), MessageSets.standard,
                           "\(id) must keep the macros it shipped with")
        }
    }

    func testSerialPartiesSendTheNumberInsteadOfAReport() throws {
        for id in ["cqp", "paqp"] {
            let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: id)))
            XCTAssertEqual(sets.run[1], "{CALL} {SERIAL} {EXCH}", id)
            XCTAssertEqual(sets.searchPounce[1], "{SERIAL} {EXCH}", id)
            XCTAssertEqual(sets.searchPounce[6], "R {SERIAL} {EXCH}", id)
            XCTAssertFalse(sets.mentions("{RST}"), "\(id) exchanges no report")
        }
    }

    func testMDCSendsCallAndLocationOnly() throws {
        let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "mdc")))
        XCTAssertEqual(sets.run[1], "{CALL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[1], "{EXCH}")
        XCTAssertEqual(sets.searchPounce[6], "R {EXCH}")
        XCTAssertFalse(sets.mentions("{RST}"), "MDC's exchange is call + location")
        XCTAssertFalse(sets.mentions("{SERIAL}"), "and carries no number either")
    }

    /// No bundled party sends both. The order is pinned here so a future one
    /// cannot silently pick a different one.
    func testBothShapeSendsTheReportBeforeTheNumber() throws {
        let both = try party(",\"exchangeIncludesRST\":true,\"exchangeIncludesSerial\":true")
        let sets = MessageSets.defaults(for: both)
        XCTAssertEqual(sets.run[1], "{CALL} {RST} {SERIAL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[1], "{RST} {SERIAL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[6], "R {RST} {SERIAL} {EXCH}")
    }

    /// An unrecognised partyID must not hand the operator empty function keys.
    func testNilPartyTakesTheReportForm() {
        XCTAssertEqual(MessageSets.defaults(for: nil), MessageSets.standard)
    }

    /// Only the exchange-bearing slots vary; CQ, TU, AGN and 73 never do.
    func testTheNonExchangeSlotsAreIdenticalInEveryShape() throws {
        let shapes = [
            MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "ksqp"))),
            MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "cqp"))),
            MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "mdc"))),
        ]
        for slot in [0, 2, 3, 4, 5, 6, 7] {
            XCTAssertEqual(Set(shapes.map { $0.run[slot] }).count, 1,
                           "run F\(slot + 1) must not vary by exchange shape")
        }
        for slot in [0, 2, 3, 4, 5, 7] {
            XCTAssertEqual(Set(shapes.map { $0.searchPounce[slot] }).count, 1,
                           "S&P F\(slot + 1) must not vary by exchange shape")
        }
        XCTAssertEqual(shapes[0].run[0], "CQ TEST {MYCALL}")
        XCTAssertEqual(shapes[0].run[7], "73 TU {MYCALL}")
    }

    func testEveryShapeFillsAllEightKeys() throws {
        for id in ["ksqp", "cqp", "mdc"] {
            let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: id)))
            XCTAssertEqual(sets.run.count, 8, id)
            XCTAssertEqual(sets.searchPounce.count, 8, id)
            XCTAssertFalse(sets.run.contains(""), id)
            XCTAssertFalse(sets.searchPounce.contains(""), id)
        }
    }

    // MARK: standard is a frozen sentinel

    /// `standard` is a persistence sentinel: Task 2 compares a loaded log's
    /// macros against it to decide whether the operator ever edited them, so
    /// its value is frozen independently of whatever `defaults(for:)` would
    /// generate today. A third copy of the literals is the point — this test
    /// is the only construct that still fails if someone collapses the
    /// constant into `defaults(for: nil)` and then edits the generator.
    func testStandardIsTheFrozenPreChangeLiteral() {
        XCTAssertEqual(MessageSets.standard.run, [
            "CQ TEST {MYCALL}", "{CALL} {RST} {EXCH}", "TU {MYCALL}", "{MYCALL}",
            "AGN?", "?", "B4", "73 TU {MYCALL}",
        ])
        XCTAssertEqual(MessageSets.standard.searchPounce, [
            "{MYCALL}", "{RST} {EXCH}", "TU", "{MYCALL}",
            "AGN?", "?", "R {RST} {EXCH}", "73",
        ])
    }

    // MARK: mentions

    func testMentionsScansBothSets() {
        XCTAssertTrue(MessageSets.standard.mentions("{RST}"))
        XCTAssertTrue(MessageSets.standard.mentions("{MYCALL}"))
        XCTAssertFalse(MessageSets.standard.mentions("{SERIAL}"))
        // S&P-only reference still counts.
        let sp = MessageSets(run: ["CQ"], searchPounce: ["{SERIAL} {EXCH}"])
        XCTAssertTrue(sp.mentions("{SERIAL}"))
        // ...and the mirror, so neither array can be silently dropped.
        XCTAssertTrue(
            MessageSets(run: ["{SERIAL} {EXCH}"], searchPounce: ["CQ"]).mentions("{SERIAL}")
        )
    }

    // MARK: exchangeMismatch — what the editor warns about

    func testMismatchFlagsASerialPartySendingAReport() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        XCTAssertEqual(MessageSets.standard.exchangeMismatch(with: cqp), .missingSerial,
                       "keys 5NN and no QSO number — the bug this closes")
        XCTAssertNil(MessageSets.defaults(for: cqp).exchangeMismatch(with: cqp))
    }

    /// The clause MDC is the reason for: no number is missing, but the report
    /// being sent is not part of the exchange.
    func testMismatchFlagsMDCStillSendingAReport() throws {
        let mdc = try XCTUnwrap(PartyCatalog.party(id: "mdc"))
        XCTAssertEqual(MessageSets.standard.exchangeMismatch(with: mdc), .extraneousRST)
        XCTAssertNil(MessageSets.defaults(for: mdc).exchangeMismatch(with: mdc))
    }

    /// A report party whose macros send no report: `{SERIAL}` expands to
    /// nothing where no number is assigned, so the exchange goes out bare.
    func testMismatchFlagsAReportPartySendingNoReport() throws {
        let ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        var swapped = MessageSets.standard
        swapped.run = swapped.run.map { $0.replacingOccurrences(of: "{RST}", with: "{SERIAL}") }
        swapped.searchPounce = swapped.searchPounce.map {
            $0.replacingOccurrences(of: "{RST}", with: "{SERIAL}")
        }
        XCTAssertEqual(swapped.exchangeMismatch(with: ksqp), .missingRST)
    }

    /// A both-flags party whose macros carry neither token trips clauses 1 and
    /// 3 at once; the missing number is reported, because that is the one the
    /// sponsor's log checker will reject.
    func testMissingSerialOutranksMissingRSTWhenBothApply() throws {
        let both = try party(",\"exchangeIncludesRST\":true,\"exchangeIncludesSerial\":true")
        let bare = MessageSets(run: ["CQ TEST {MYCALL}"], searchPounce: ["{MYCALL}"])
        XCTAssertEqual(bare.exchangeMismatch(with: both), .missingSerial)
    }

    func testMismatchIsSilentForEveryReportParty() throws {
        for id in Self.rstPartyIDs {
            let p = try XCTUnwrap(PartyCatalog.party(id: id), id)
            XCTAssertNil(MessageSets.standard.exchangeMismatch(with: p),
                         "\(id) sends a report and no number — nothing to warn about")
        }
    }

    func testMismatchIsSilentOnceTheOperatorHasFixedItByHand() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var custom = MessageSets.standard
        custom.run[1] = "{CALL} {SERIAL} {EXCH} GL"
        custom.searchPounce = custom.searchPounce.map {
            $0.replacingOccurrences(of: "{RST}", with: "{SERIAL}")
        }
        XCTAssertNil(custom.exchangeMismatch(with: cqp), "hand-fixed macros are not a warning")
    }

    func testMismatchIgnoresAnUnknownParty() {
        XCTAssertNil(MessageSets.standard.exchangeMismatch(with: nil))
    }

    // MARK: roster exhaustiveness

    /// The roster above must stay exhaustive: a newly bundled party fails here
    /// with a diff rather than silently escaping the byte-identity proof.
    func testEveryBundledPartyIsAccountedForByShape() {
        for p in PartyCatalog.loadBundled() {
            let isReportShape = p.exchangeIncludesRST && !p.exchangeIncludesSerial
            XCTAssertEqual(isReportShape, Self.rstPartyIDs.contains(p.id),
                           "\(p.id) changed exchange shape, or is a new party missing from the roster")
            XCTAssertEqual(MessageSets.defaults(for: p) == .standard, isReportShape, p.id)
            XCTAssertNil(MessageSets.defaults(for: p).exchangeMismatch(with: p),
                         "\(p.id)'s own defaults must never trip our warning")
        }
    }

    // MARK: The operator-facing warning

    func testWarningNamesThePartyAndTheMissingMacro() {
        XCTAssertEqual(
            MessageSets.ExchangeMismatch.missingSerial.warning(partyName: "California QSO Party"),
            "California QSO Party sends a QSO number, but no message uses {SERIAL}."
        )
        XCTAssertEqual(
            MessageSets.ExchangeMismatch.extraneousRST.warning(partyName: "Maryland-DC QSO Party"),
            "Maryland-DC QSO Party's exchange does not include a signal report, but a message still sends {RST}."
        )
        XCTAssertEqual(
            MessageSets.ExchangeMismatch.missingRST.warning(partyName: "Kansas QSO Party"),
            "Kansas QSO Party sends a signal report, but no message uses {RST}."
        )
    }

    /// Every case must supply its own wording — a `default:` arm here would let
    /// a future case inherit another's copy and tell the operator the wrong thing.
    func testEveryMismatchCaseHasDistinctWording() {
        let cases: [MessageSets.ExchangeMismatch] = [.missingSerial, .extraneousRST, .missingRST]
        let texts = cases.map { $0.warning(partyName: "P") }
        XCTAssertEqual(Set(texts).count, cases.count, "each case needs its own sentence")
        for text in texts {
            XCTAssertTrue(text.hasPrefix("P"), "the party's name leads: \(text)")
            XCTAssertTrue(text.hasSuffix("."), "a full sentence: \(text)")
        }
    }

    /// The warning an operator actually sees for the shipped defaults on the
    /// two parties that were wrong before this change.
    func testWarningForTheRealPartiesThatWereWrong() throws {
        for id in ["cqp", "paqp"] {
            let party = try XCTUnwrap(PartyCatalog.party(id: id))
            let mismatch = try XCTUnwrap(MessageSets.standard.exchangeMismatch(with: party), id)
            XCTAssertEqual(mismatch.warning(partyName: party.name),
                           "\(party.name) sends a QSO number, but no message uses {SERIAL}.")
        }
    }
}
