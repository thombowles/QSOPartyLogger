import XCTest
@testable import QSOPartyLogger

/// The strip's one ranking, over two sources: MASTER.SCP and the party's call
/// history file (for the Skeeter Hunt, the roster of Skeeter numbers).
/// N1MM's Check window draws from both, in separate panes; this app has one
/// line, so history calls join it marked, and rank first inside each tier
/// (2026-08-16: "make the history calls be included in the callsign lookup
/// helper, not just SCP. And highlight the calls that are in the history").
final class SuperCheckTests: XCTestCase {

    private let scp = ["AK5C", "K5CW", "K5CX", "W5K5C"]
    private let history = ["K5CX", "K5CZ", "N5K5C"]

    private func calls(_ m: SuperCheck.Matches) -> [String] { m.calls.map(\.call) }
    private func marked(_ m: SuperCheck.Matches) -> [String] {
        m.calls.filter(\.inHistory).map(\.call)
    }

    /// Exact, then prefix, then containment — and inside each tier the
    /// history calls first, alphabetical after that. A call in both sources
    /// appears once, marked.
    func testTiersWithHistoryFirstInsideEach() {
        let m = SuperCheck.matches(for: "K5C", scpCalls: scp, historyCalls: history, limit: 24)
        XCTAssertEqual(calls(m), ["K5CX", "K5CZ", "K5CW", "N5K5C", "AK5C", "W5K5C"])
        XCTAssertEqual(marked(m), ["K5CX", "K5CZ", "N5K5C"])
        XCTAssertEqual(m.total, 6)
        XCTAssertEqual(m.scpTotal, 4)
        XCTAssertEqual(m.historyTotal, 3)
    }

    /// The exact call leads whichever source it came from, and carries its
    /// mark — bold says "exact", the mark says "in the history".
    func testTheExactCallLeadsAndKeepsItsMark() {
        let m = SuperCheck.matches(for: "K5CZ", scpCalls: scp, historyCalls: history, limit: 24)
        XCTAssertEqual(m.calls.first, SuperCheck.Match(call: "K5CZ", inHistory: true))
        let n = SuperCheck.matches(for: "K5CW", scpCalls: scp, historyCalls: history, limit: 24)
        XCTAssertEqual(n.calls.first, SuperCheck.Match(call: "K5CW", inHistory: false))
    }

    /// The history alone is a source: a cached roster shows before MASTER.SCP
    /// has landed, or with the database off.
    func testHistoryAloneMatches() {
        let m = SuperCheck.matches(for: "K5C", scpCalls: [], historyCalls: history, limit: 24)
        XCTAssertEqual(calls(m), ["K5CX", "K5CZ", "N5K5C"])
        XCTAssertEqual(m.scpTotal, 0)
        XCTAssertEqual(m.historyTotal, 3)
        XCTAssertEqual(m.total, 3)
    }

    /// No history is exactly what the SCP database did on its own.
    func testNoHistoryIsTheDatabaseAlone() {
        let m = SuperCheck.matches(for: "K5C", scpCalls: scp, historyCalls: [], limit: 24)
        XCTAssertEqual(calls(m), SCPDatabase(calls: scp, release: nil).matches(for: "K5C", limit: 24).calls)
        XCTAssertTrue(marked(m).isEmpty)
        XCTAssertEqual(m.historyTotal, 0)
    }

    /// The cap trims the list, never the counts — "+N more" has to be true.
    func testLimitCapsCallsButNotTotals() {
        let m = SuperCheck.matches(for: "K5C", scpCalls: scp, historyCalls: history, limit: 2)
        XCTAssertEqual(calls(m), ["K5CX", "K5CZ"])
        XCTAssertEqual(m.total, 6)
        XCTAssertEqual(m.scpTotal, 4)
        XCTAssertEqual(m.historyTotal, 3)
    }

    func testFragmentsBelowTheFloorMatchNothing() {
        XCTAssertEqual(SuperCheck.matches(for: "K5", scpCalls: scp, historyCalls: history, limit: 24), .none)
        XCTAssertEqual(SuperCheck.matches(for: "  ", scpCalls: scp, historyCalls: history, limit: 24), .none)
    }

    func testMatchIsCaseAndWhitespaceBlind() {
        let m = SuperCheck.matches(for: " k5cz ", scpCalls: scp, historyCalls: history, limit: 24)
        XCTAssertEqual(m.calls.first?.call, "K5CZ")
    }
}
