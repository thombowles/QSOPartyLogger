import XCTest
@testable import QSOPartyLogger

/// The strip's contents follow the call field through every path that
/// changes it — typing, arriving from a spot, logging, clearing — and the
/// arrival or removal of either source, the SCP database and the party's
/// call history file, both of which land while a fragment may already be
/// typed.
@MainActor
final class SuperCheckFlowTests: XCTestCase {

    private func flow() -> EntryFlow {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        return EntryFlow(document: doc)
    }

    private var db: SCPDatabase {
        SCPDatabase(calls: ["K5C", "K5CW", "KE5CW", "N5KO", "W5NK"], release: nil)
    }

    /// A Kansas call history naming one call the database has (W5NK) and one
    /// it lacks (K5CX).
    private func ksqpIndex() -> (partyID: String, parsed: CallHistoryFile.Parsed) {
        ("ksqp", CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY KS
        K5CX,Bill,JOH,
        W5NK,Bob,BAR,
        """))
    }

    private func context() -> EntryFlow.Context { EntryFlow.Context() }

    private func calls(_ flow: EntryFlow) -> [String] { flow.superCheckMatches.calls.map(\.call) }
    private func marked(_ flow: EntryFlow) -> [String] {
        flow.superCheckMatches.calls.filter(\.inHistory).map(\.call)
    }

    func testTypingRefreshesMatches() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "K5C"
        flow.callChanged(context())
        // KE5CW does not contain "K5C" — containment is literal.
        XCTAssertEqual(calls(flow), ["K5C", "K5CW"])
    }

    func testShortFragmentsShowNothing() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "K5"
        flow.callChanged(context())
        XCTAssertEqual(flow.superCheckMatches, .none)
    }

    /// The download lands while a fragment is already typed — the strip
    /// fills without another keystroke.
    func testALateDatabasePopulatesTheTypedFragment() {
        let flow = flow()
        flow.entry.call = "N5K"
        flow.callChanged(context())
        XCTAssertEqual(flow.superCheckMatches, .none)
        flow.updateSCPDatabase(db)
        XCTAssertEqual(calls(flow), ["N5KO"])
    }

    /// The toggle going off clears the strip immediately.
    func testRemovingTheDatabaseEmptiesMatches() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "N5K"
        flow.callChanged(context())
        flow.updateSCPDatabase(nil)
        XCTAssertEqual(flow.superCheckMatches, .none)
        XCTAssertNil(flow.scpDatabase)
    }

    /// Logging a contact clears the call field — no strip may outlive the
    /// call it belonged to.
    func testLoggingClearsTheStrip() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "KE5CW"
        flow.entry.exchange = "CRA"
        flow.callChanged(context())
        XCTAssertEqual(calls(flow).first, "KE5CW")
        guard case .logged = flow.logContact(context(), undoManager: nil) else {
            return XCTFail("the contact should have logged")
        }
        XCTAssertEqual(flow.superCheckMatches, .none)
    }

    /// A spot click is `stationChanged`, not typing — same refresh.
    func testStationChangedRefreshesMatches() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.stationChanged(to: "W5NK", context())
        XCTAssertEqual(calls(flow), ["W5NK"])
    }

    // MARK: The call history joins the strip (2026-08-16)

    /// The report: history calls in the strip, marked, and ahead of the
    /// database's inside their tier — K5CX is a roster call the database has
    /// never heard of, and it leads the prefix tier over K5CW.
    func testHistoryCallsJoinTheStripMarkedAndFirstInTheirTier() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.callHistoryIndex = ksqpIndex()
        flow.entry.call = "K5C"
        flow.callChanged(context())
        XCTAssertEqual(calls(flow), ["K5C", "K5CX", "K5CW"])
        XCTAssertEqual(marked(flow), ["K5CX"])
        XCTAssertEqual(flow.superCheckMatches.historyTotal, 1)
        XCTAssertEqual(flow.superCheckMatches.scpTotal, 2)
    }

    /// A call in both sources shows once, marked as history.
    func testACallInBothSourcesShowsOnceMarked() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.callHistoryIndex = ksqpIndex()
        flow.entry.call = "W5N"
        flow.callChanged(context())
        XCTAssertEqual(flow.superCheckMatches.calls, [SuperCheck.Match(call: "W5NK", inHistory: true)])
        XCTAssertEqual(flow.superCheckMatches.total, 1)
    }

    /// The roster lands after the fragment is typed — as the database does.
    func testALateHistoryPopulatesTheTypedFragment() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "K5CX"
        flow.callChanged(context())
        XCTAssertEqual(calls(flow), [], "the database alone has no K5CX")
        flow.callHistoryIndex = ksqpIndex()
        XCTAssertEqual(flow.superCheckMatches.calls, [SuperCheck.Match(call: "K5CX", inHistory: true)])
    }

    /// The history alone is a source: a cached roster shows before MASTER.SCP
    /// has landed, and the strip is live for it.
    func testHistoryAloneFeedsTheStripAndMakesItLive() {
        let flow = flow()
        XCTAssertFalse(flow.superCheckLive)
        flow.callHistoryIndex = ksqpIndex()
        XCTAssertTrue(flow.superCheckLive)
        flow.entry.call = "K5C"
        flow.callChanged(context())
        XCTAssertEqual(calls(flow), ["K5CX"])
    }

    /// A file downloaded for a party the operator has since left is not this
    /// party's roster — the tag check the prefill already makes.
    func testAHistoryFileForAnotherPartyIsNotConsulted() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.callHistoryIndex = ("cqp", ksqpIndex().parsed)
        flow.entry.call = "K5C"
        flow.callChanged(context())
        XCTAssertEqual(calls(flow), ["K5C", "K5CW"])
        XCTAssertTrue(marked(flow).isEmpty)
    }

    /// The history going away (the toggle, a party change) empties its half.
    func testRemovingTheHistoryDropsItsCalls() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.callHistoryIndex = ksqpIndex()
        flow.entry.call = "K5C"
        flow.callChanged(context())
        XCTAssertEqual(marked(flow), ["K5CX"])
        flow.callHistoryIndex = nil
        XCTAssertEqual(calls(flow), ["K5C", "K5CW"])
        XCTAssertTrue(marked(flow).isEmpty)
    }

    /// The option, machine-level like its peers: on by default, off with
    /// one toggle, persisted. A scratch suite — never the operator's real
    /// preferences.
    func testSuperCheckSettingDefaultsOnAndPersists() {
        let suiteName = "scp-setting-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppSettings(defaults: defaults).superCheckEnabled)
        AppSettings(defaults: defaults).superCheckEnabled = false
        XCTAssertFalse(AppSettings(defaults: defaults).superCheckEnabled)
    }
}
