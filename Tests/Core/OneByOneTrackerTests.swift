import XCTest
@testable import QSOPartyLogger

final class OneByOneTrackerTests: XCTestCase {

    let config = PartyDefinition.OneByOneConfig(
        words: ["KANSAS", "SUNFLOWER", "QSOPARTY", "YELLOWBRICKROAD"],
        wildcard: "KS0KS"
    )

    func progressFor(_ calls: [String]) -> [OneByOneTracker.WordProgress] {
        OneByOneTracker.progress(calls: calls, config: config)
    }

    func word(_ name: String, in results: [OneByOneTracker.WordProgress]) -> OneByOneTracker.WordProgress {
        results.first { $0.word == name }!
    }

    func testIsOneByOne() {
        XCTAssertTrue(OneByOneTracker.isOneByOne("W0K"))
        XCTAssertTrue(OneByOneTracker.isOneByOne("k0a"))
        XCTAssertTrue(OneByOneTracker.isOneByOne("N9Z"))
        XCTAssertFalse(OneByOneTracker.isOneByOne("KS0KS"))
        XCTAssertFalse(OneByOneTracker.isOneByOne("W0BH"))
        XCTAssertFalse(OneByOneTracker.isOneByOne("A0K"), "prefix must be K/N/W")
    }

    func testKansasCompletesWithOfficialExample() {
        // Rules example: w0K k0A n0N k0S n0A w0S — two distinct A and S calls.
        let r = word("KANSAS", in: progressFor(["W0K", "K0A", "N0N", "K0S", "N0A", "W0S"]))
        XCTAssertTrue(r.complete)
        XCTAssertEqual(Set(r.assignments.compactMap { $0 }).count, 6, "six distinct calls used")
    }

    func testDuplicateLetterNeedsDistinctCalls() {
        // KANSAS has A twice and S twice; one A-call and one S-call fill only one each.
        let r = word("KANSAS", in: progressFor(["W0K", "K0A", "N0N", "K0S"]))
        XCTAssertFalse(r.complete)
        XCTAssertEqual(r.filledCount, 4)
        // K0A credited once even though A appears twice.
        XCTAssertEqual(r.assignments.filter { $0 == "K0A" }.count, 1)
    }

    func testCallsSharedAcrossWords() {
        let r = progressFor(["K0S"])
        XCTAssertEqual(word("KANSAS", in: r).filledCount, 1)
        XCTAssertEqual(word("SUNFLOWER", in: r).filledCount, 1, "K0S serves both words")
        XCTAssertEqual(word("QSOPARTY", in: r).filledCount, 1)
    }

    func testWildcardFillsExactlyOneGap() {
        // KANSAS missing only the final S; wildcard closes the word with fewest gaps.
        let calls = ["W0K", "K0A", "N0N", "K0S", "N0A", "KS0KS"]
        let r = progressFor(calls)
        XCTAssertTrue(word("KANSAS", in: r).complete)
        XCTAssertTrue(word("KANSAS", in: r).assignments.contains("KS0KS"))
        // Wildcard must appear in exactly one word.
        let wildcardUses = r.flatMap(\.assignments).filter { $0 == "KS0KS" }.count
        XCTAssertEqual(wildcardUses, 1)
    }

    func testNoWildcardWithoutWorkingIt() {
        let r = progressFor(["W0K", "K0A", "N0N", "K0S", "N0A"])
        XCTAssertFalse(word("KANSAS", in: r).complete)
        XCTAssertFalse(r.flatMap(\.assignments).contains("KS0KS"))
    }

    func testYellowBrickRoadDuplicates() {
        // L×2, O×3, R×2 in YELLOWBRICKROAD need distinct calls per instance.
        let calls = ["W0Y", "K0E", "N0L", "W0L", "K0O", "N0O", "W0O", "K0W", "N0B",
                     "W0R", "K0R", "N0I", "W0C", "K0K", "N0A", "W0D"]
        let r = word("YELLOWBRICKROAD", in: progressFor(calls))
        XCTAssertTrue(r.complete)
        XCTAssertEqual(r.assignments.count, 15)
        XCTAssertEqual(Set(r.assignments.compactMap { $0 }).count, 15, "all distinct calls")
    }
}
