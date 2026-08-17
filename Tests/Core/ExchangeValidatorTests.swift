import XCTest
@testable import QSOPartyLogger

final class ExchangeValidatorTests: XCTestCase {
    private func contest(_ id: String) throws -> ContestDefinition {
        try PartyLowering.lower(try XCTUnwrap(PartyCatalog.party(id: id)))
    }
    private func element(_ c: ContestDefinition, _ id: String) throws -> ExchangeElement {
        try XCTUnwrap(c.exchange.first { $0.id == id })
    }

    func testTokenElementAcceptsCountiesCountyLinesAndOutTokens() throws {
        let c = try contest("ksqp"), loc = try element(c, "location")
        XCTAssertEqual(try ExchangeValidator.validate("lin", element: loc, contest: c, side: "inside").get(), ["LIN"])
        XCTAssertEqual(try ExchangeValidator.validate("lin/and", element: loc, contest: c, side: "inside").get(), ["LIN", "AND"])
        XCTAssertEqual(try ExchangeValidator.validate("tx", element: loc, contest: c, side: "inside").get(), ["TX"])
        // Kansas is a home-stations-only party, so DX reaches a Kansas
        // entrant, never a Kansas entrant's out-of-state contact: the outside
        // side is paired to `inside`, and `ExchangeParser` rejects DX for
        // `role: .outOfState` there too (`acceptsOutStateTokens` is false).
        XCTAssertEqual(try ExchangeValidator.validate("dx", element: loc, contest: c, side: "inside").get(), ["DX"])
        XCTAssertThrowsError(try ExchangeValidator.validate("dx", element: loc, contest: c, side: "outside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("ks", element: loc, contest: c, side: "inside").get())    // home state token
        XCTAssertThrowsError(try ExchangeValidator.validate("lin/tx", element: loc, contest: c, side: "inside").get()) // mixed
        XCTAssertThrowsError(try ExchangeValidator.validate("", element: loc, contest: c, side: "inside").get())
        if case .failure(.invalid(let token, let suggestions)) = ExchangeValidator.validate("LNI", element: loc, contest: c, side: "inside") {
            XCTAssertEqual(token, "LNI")
            XCTAssertTrue(suggestions.contains("LIN"))
        } else { XCTFail("expected a suggestion") }
    }

    func testMarylandOutsideEntrantReceivesCountiesOnly() throws {
        let c = try contest("mdc"), loc = try element(c, "location")
        let county = try XCTUnwrap(PartyCatalog.party(id: "mdc")?.counties.first?.abbr)
        XCTAssertNoThrow(try ExchangeValidator.validate(county, element: loc, contest: c, side: "outside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("TX", element: loc, contest: c, side: "outside").get())
        XCTAssertNoThrow(try ExchangeValidator.validate("TX", element: loc, contest: c, side: "inside").get())
    }

    func testDXPrefixesAndAliases() throws {
        let c = try contest("fqp"), loc = try element(c, "location")
        XCTAssertEqual(try ExchangeValidator.validate("dl", element: loc, contest: c, side: "inside").get(), ["DL"])
        XCTAssertEqual(try ExchangeValidator.validate("r2", element: loc, contest: c, side: "inside").get(), ["R2"])
        XCTAssertThrowsError(try ExchangeValidator.validate("EM32", element: loc, contest: c, side: "inside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("FL", element: loc, contest: c, side: "inside").get())    // home state, not a prefix here
    }

    func testOtherKinds() throws {
        let c = try contest("cqp")
        let serial = try element(c, "serial")
        XCTAssertEqual(try ExchangeValidator.validate("007", element: serial, contest: c, side: "inside").get(), ["7"])
        XCTAssertThrowsError(try ExchangeValidator.validate("7a", element: serial, contest: c, side: "inside").get())
        let rst = ExchangeElement(id: "rst", kind: .rst, sentBy: ["all": .init()])
        XCTAssertEqual(try ExchangeValidator.validate("5nn", element: rst, contest: c, side: "inside").get(), ["599"])
        XCTAssertEqual(try ExchangeValidator.validate("59", element: rst, contest: c, side: "inside").get(), ["59"])
        XCTAssertThrowsError(try ExchangeValidator.validate("5", element: rst, contest: c, side: "inside").get())
        let zone = ExchangeElement(id: "zone", kind: .cqZone, sentBy: ["all": .init()])
        XCTAssertEqual(try ExchangeValidator.validate("05", element: zone, contest: c, side: "inside").get(), ["5"])
        XCTAssertThrowsError(try ExchangeValidator.validate("41", element: zone, contest: c, side: "inside").get())
        let prec = ExchangeElement(id: "precedence", kind: .precedence, sentBy: [:], letters: ["Q", "A", "B", "U", "M", "S"])
        XCTAssertEqual(try ExchangeValidator.validate("a", element: prec, contest: c, side: "inside").get(), ["A"])
        XCTAssertThrowsError(try ExchangeValidator.validate("X", element: prec, contest: c, side: "inside").get())
        let check = ExchangeElement(id: "check", kind: .check, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("65", element: check, contest: c, side: "inside").get(), ["65"])
        XCTAssertThrowsError(try ExchangeValidator.validate("655", element: check, contest: c, side: "inside").get())
        let cls = ExchangeElement(id: "class", kind: .classToken, sentBy: [:], letters: ["A", "B", "C", "D", "E", "F"], minNumber: 1)
        XCTAssertEqual(try ExchangeValidator.validate("3a", element: cls, contest: c, side: "inside").get(), ["3A"])
        XCTAssertThrowsError(try ExchangeValidator.validate("0A", element: cls, contest: c, side: "inside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("3G", element: cls, contest: c, side: "inside").get())
        let power = ExchangeElement(id: "power", kind: .power, sentBy: [:])
        for ok in ["100", "KW", "K", "500W", "1KW"] { XCTAssertNoThrow(try ExchangeValidator.validate(ok, element: power, contest: c, side: "inside").get(), ok) }
        XCTAssertThrowsError(try ExchangeValidator.validate("LOTS", element: power, contest: c, side: "inside").get())
        let grid = ExchangeElement(id: "grid", kind: .grid, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("em13le", element: grid, contest: c, side: "inside").get(), ["EM13LE"])
        XCTAssertThrowsError(try ExchangeValidator.validate("EM1", element: grid, contest: c, side: "inside").get())
        let report = ExchangeElement(id: "report", kind: .report, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("-12", element: report, contest: c, side: "inside").get(), ["-12"])
        let name = ExchangeElement(id: "name", kind: .name, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("bill", element: name, contest: c, side: "inside").get(), ["BILL"])
        XCTAssertThrowsError(try ExchangeValidator.validate("B1LL", element: name, contest: c, side: "inside").get())
        let member = ExchangeElement(id: "member", kind: .memberOrPower, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("5 w", element: member, contest: c, side: "inside").get(), ["5W"])
        XCTAssertEqual(try ExchangeValidator.validate("013", element: member, contest: c, side: "inside").get(), ["013"])
        XCTAssertThrowsError(try ExchangeValidator.validate("five", element: member, contest: c, side: "inside").get())
    }

    /// The oracle: on every bundled party, for both roles, the validator
    /// accepts exactly what `ExchangeParser` accepts and returns the same
    /// locations. Success/failure only — the two report errors differently.
    func testAgreesWithExchangeParserOnEveryParty() throws {
        for p in PartyCatalog.loadBundled() {
            let c = try PartyLowering.lower(p)
            let loc = try element(c, "location")
            var corpus = p.counties.map(\.abbr) + p.validOutStateTokens.sorted()
            corpus += ["ZZZ", "EM32", "SAF", "DL", "JA", "PA", "ON", "OK", "SD", "TN", "R1", "DX", "TX/OK", ""]
            if p.counties.count >= 2 { corpus += ["\(p.counties[0].abbr)/\(p.counties[1].abbr)", "\(p.counties[0].abbr)/TX"] }
            if p.counties.count >= 5 { corpus.append(p.counties.prefix(5).map(\.abbr).joined(separator: "/")) }
            for (role, side) in [(ExchangeParser.Role.inState, p.hasHomeRegion ? "inside" : "all"),
                                 (ExchangeParser.Role.outOfState, p.hasHomeRegion ? "outside" : "all")] {
                for raw in corpus {
                    // The legacy parser's DX branch ignores the role —
                    // `acceptsDXPrefix` is `party.dxStyle == .prefix` and
                    // nothing else — so an outside entrant of a
                    // home-stations-only party could log a DX token the rules
                    // give it no credit for: a bare prefix (MDC's DL, JA) or
                    // one of the party's own declared aliases (FQP's R1, whose
                    // maritime-mobile ITU regions the sponsor gives to Florida
                    // entrants only). The validator follows the pairing
                    // instead (spec §1.2). The skip is that branch's own
                    // predicate, `isDXPrefix`, so it covers exactly those
                    // probes and no other token in the corpus.
                    if role == .outOfState, p.outStateWorksHomeStationsOnly, p.isDXPrefix(raw) { continue }
                    let legacy = ExchangeParser.parse(raw, party: p, role: role)
                    let new = ExchangeValidator.validate(raw, element: loc, contest: c, side: side)
                    switch (legacy, new) {
                    case (.success(let l), .success(let n)):
                        XCTAssertEqual(l.locations, n, "\(p.id) \(role) '\(raw)'")
                    case (.failure, .failure):
                        break
                    default:
                        XCTFail("\(p.id) \(role) '\(raw)': legacy \(legacy) vs new \(new)")
                    }
                }
            }
        }
    }
}
