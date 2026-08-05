import XCTest
@testable import QSOPartyLogger

/// Default F1–F8 macros follow the party's exchange shape. Three bundled
/// parties send no signal report: CQP and PAQP send a QSO number instead
/// ("QSO number and 4-letter county abbreviation"), and MDC sends call and
/// location only ("You give your Call Sign and Location to each contacted
/// station"). A fixed {RST} default keys a report their sponsors do not want.
/// See docs/superpowers/specs/2026-07-25-serial-macros-cut-numbers-mode-default-design.md
final class MessageDefaultsTests: XCTestCase {

    /// Every party whose exchange carries a report and no number, named so a
    /// party cannot change shape unnoticed. Deliberately not described by a
    /// count in prose — the list grows with each party added, and a stale number
    /// in a comment is a small lie that nothing catches.
    static let rstPartyIDs = [
        "alqp", "arqp", "azqp", "bcqp", "coqp", "deqp", "fqp", "gaqp", "hqp", "iaqp", "ilqp", "in7qpne", "inqp", "ksqp", "kyqp", "laqp", "meqp", "miqp", "moqp", "msqp", "ndqp", "neqp", "newenglandqp", "nmqp",
        "nhqp", "njqp", "nyqp", "ohqp", "okqp", "oqp", "qcqp", "scqp", "sdqp", "sevenqp", "tnqp", "tqp", "vtqp",
        "warun",
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
    func testEveryReportPartyKeepsTheShippedDefaults() throws {
        XCTAssertEqual(Self.rstPartyIDs.count, 38,
                       "a party joined or left the report shape — update the roster deliberately")
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
            XCTAssertFalse(sets.mentions(.rst), "\(id) exchanges no report")
        }
    }

    func testMDCSendsCallAndLocationOnly() throws {
        let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "mdc")))
        XCTAssertEqual(sets.run[1], "{CALL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[1], "{EXCH}")
        XCTAssertEqual(sets.searchPounce[6], "R {EXCH}")
        XCTAssertFalse(sets.mentions(.rst), "MDC's exchange is call + location")
        XCTAssertFalse(sets.mentions(.serial), "and carries no number either")
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
        XCTAssertTrue(MessageSets.standard.mentions(.rst))
        XCTAssertTrue(MessageSets.standard.mentions(.myCall))
        XCTAssertFalse(MessageSets.standard.mentions(.serial))
        // S&P-only reference still counts.
        let sp = MessageSets(run: ["CQ"], searchPounce: ["{SERIAL} {EXCH}"])
        XCTAssertTrue(sp.mentions(.serial))
        // ...and the mirror, so neither array can be silently dropped.
        XCTAssertTrue(
            MessageSets(run: ["{SERIAL} {EXCH}"], searchPounce: ["CQ"]).mentions(.serial)
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
                && p.memberExchange == nil
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
            "California QSO Party sends a QSO number, but not every message that "
                + "sends the exchange uses {SERIAL}."
        )
        XCTAssertEqual(
            MessageSets.ExchangeMismatch.extraneousRST.warning(partyName: "Maryland-DC QSO Party"),
            "Maryland-DC QSO Party's exchange does not include a signal report, but a message still sends {RST}."
        )
        XCTAssertEqual(
            MessageSets.ExchangeMismatch.missingRST.warning(partyName: "Kansas QSO Party"),
            "Kansas QSO Party sends a signal report, but not every message that "
                + "sends the exchange uses {RST}."
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
                           "\(party.name) sends a QSO number, but not every message that "
                               + "sends the exchange uses {SERIAL}.")
        }
    }

    // MARK: Each message set is judged on its own (2026-07-25)

    /// The gap this closes. An operator who fixes Run but retypes S&P F2 to
    /// drop the number is still sending no QSO number on every search-and-
    /// pounce contact, and CQP accepts Cabrillo only — so the log is
    /// unsubmittable. A single OR across both sets called this agreement.
    func testAnEditToOnlyTheSearchPounceSetStillWarns() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var macros = MessageSets.defaults(for: cqp)
        macros.searchPounce[1] = "{EXCH}"
        XCTAssertEqual(macros.exchangeMismatch(with: cqp), .missingSerial,
                       "the Run set still has {SERIAL}; S&P does not")
    }

    /// Symmetric: the Run set is not privileged.
    func testAnEditToOnlyTheRunSetStillWarns() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var macros = MessageSets.defaults(for: cqp)
        macros.run = macros.run.map { $0.replacingOccurrences(of: "{SERIAL} ", with: "") }
        XCTAssertEqual(macros.exchangeMismatch(with: cqp), .missingSerial)
    }

    /// Also symmetric for the report cases, so neither set is special-cased.
    func testAStrayReportInOnlyOneSetWarns() throws {
        let mdc = try XCTUnwrap(PartyCatalog.party(id: "mdc"))
        var macros = MessageSets.defaults(for: mdc)
        macros.searchPounce[1] = "{RST} {EXCH}"
        XCTAssertEqual(macros.exchangeMismatch(with: mdc), .extraneousRST)
    }

    /// The trap: an operator who never calls CQ has no Run messages, and an
    /// empty message cannot send the wrong exchange. Judging a blank set would
    /// nag them permanently with nothing to fix.
    func testAnEmptySetIsSkippedRatherThanJudged() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let correct = MessageSets.defaults(for: cqp)

        let noRun = MessageSets(run: Array(repeating: "", count: 8),
                                searchPounce: correct.searchPounce)
        XCTAssertNil(noRun.exchangeMismatch(with: cqp), "no Run messages to be wrong")

        let noSP = MessageSets(run: correct.run,
                               searchPounce: Array(repeating: "", count: 8))
        XCTAssertNil(noSP.exchangeMismatch(with: cqp), "no S&P messages to be wrong")
    }

    /// And a set of nothing at all warns about nothing.
    func testEntirelyEmptyMacrosDoNotWarn() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let blank = MessageSets(run: Array(repeating: "", count: 8),
                                searchPounce: Array(repeating: "", count: 8))
        XCTAssertNil(blank.exchangeMismatch(with: cqp))
    }

    /// Only a truly empty message counts as absent: the skip test is plain
    /// emptiness, not a trim. A set of spaces is therefore judged rather than
    /// skipped, and warns.
    ///
    /// Nothing reaches the air either way — `AppSettings.expandMacros` trims,
    /// so `"   "` sends nothing — which makes this a warning about a set that
    /// is broken in a slightly different way than the text describes. It is
    /// the deliberate trade for a simpler predicate, and it costs an operator
    /// nothing unless they type spaces into all eight fields.
    func testAWhitespaceOnlySetIsJudgedRatherThanSkipped() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let correct = MessageSets.defaults(for: cqp)
        let spaces = MessageSets(run: Array(repeating: "   ", count: 8),
                                 searchPounce: correct.searchPounce)
        XCTAssertEqual(spaces.exchangeMismatch(with: cqp), .missingSerial,
                       "spaces are content as far as the emptiness check is concerned")
    }

    /// The masking case. CQP's S&P defaults carry the exchange twice, so an
    /// intact repeat-back at F7 must not excuse a broken answer at F2. Judging
    /// the set as a whole rather than message by message misses this.
    func testAnIntactRepeatBackDoesNotMaskABrokenAnswer() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var macros = MessageSets.defaults(for: cqp)
        XCTAssertEqual(macros.searchPounce[6], "R {SERIAL} {EXCH}", "precondition: F7 also carries it")

        macros.searchPounce[1] = "{EXCH}"
        XCTAssertEqual(macros.exchangeMismatch(with: cqp), .missingSerial,
                       "F7 still carries {SERIAL}; F2 does not, and F2 is what answers a CQ")
    }

    /// A populated set that sends no exchange at all cannot be right either, so
    /// it is judged rather than skipped — the distinction from a blank set.
    func testAPopulatedSetThatSendsNoExchangeIsStillJudged() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let noExchange = MessageSets(
            run: ["CQ TEST {MYCALL}", "{CALL}", "TU {MYCALL}", "", "", "", "", ""],
            searchPounce: MessageSets.defaults(for: cqp).searchPounce
        )
        XCTAssertEqual(noExchange.exchangeMismatch(with: cqp), .missingSerial,
                       "nothing in the Run set sends the exchange")

        let ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        XCTAssertEqual(noExchange.exchangeMismatch(with: ksqp), .missingRST,
                       "same set, report party: the report is what is missing")
    }

    /// Missing and extraneous are not symmetric. A missing token is a property
    /// of the exchange message, but an extraneous report is a should-never-
    /// appear check: `{RST}` fat-fingered into F5 keys a literal report every
    /// time F5 is pressed, for a party whose exchange has no room for one.
    func testAStrayReportOutsideTheExchangeMessageStillWarns() throws {
        let mdc = try XCTUnwrap(PartyCatalog.party(id: "mdc"))
        var macros = MessageSets.defaults(for: mdc)
        XCTAssertNil(macros.exchangeMismatch(with: mdc), "precondition: MDC's defaults agree")

        macros.searchPounce[4] = "AGN? {RST}"
        XCTAssertEqual(macros.exchangeMismatch(with: mdc), .extraneousRST,
                       "F5 is not an exchange message, but it still sends a report")
    }
}
