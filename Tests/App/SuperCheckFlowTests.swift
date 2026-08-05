import XCTest
@testable import QSOPartyLogger

/// The strip's contents follow the call field through every path that
/// changes it — typing, arriving from a spot, logging, clearing — and the
/// database's arrival or removal, which both happen while a fragment may
/// already be typed.
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

    private func context() -> EntryFlow.Context { EntryFlow.Context() }

    func testTypingRefreshesMatches() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "K5C"
        flow.callChanged(context())
        // KE5CW does not contain "K5C" — containment is literal.
        XCTAssertEqual(flow.scpMatches.calls, ["K5C", "K5CW"])
    }

    func testShortFragmentsShowNothing() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "K5"
        flow.callChanged(context())
        XCTAssertEqual(flow.scpMatches, .none)
    }

    /// The download lands while a fragment is already typed — the strip
    /// fills without another keystroke.
    func testALateDatabasePopulatesTheTypedFragment() {
        let flow = flow()
        flow.entry.call = "N5K"
        flow.callChanged(context())
        XCTAssertEqual(flow.scpMatches, .none)
        flow.updateSCPDatabase(db)
        XCTAssertEqual(flow.scpMatches.calls, ["N5KO"])
    }

    /// The toggle going off clears the strip immediately.
    func testRemovingTheDatabaseEmptiesMatches() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.entry.call = "N5K"
        flow.callChanged(context())
        flow.updateSCPDatabase(nil)
        XCTAssertEqual(flow.scpMatches, .none)
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
        XCTAssertEqual(flow.scpMatches.calls.first, "KE5CW")
        guard case .logged = flow.logContact(context(), undoManager: nil) else {
            return XCTFail("the contact should have logged")
        }
        XCTAssertEqual(flow.scpMatches, .none)
    }

    /// A spot click is `stationChanged`, not typing — same refresh.
    func testStationChangedRefreshesMatches() {
        let flow = flow()
        flow.updateSCPDatabase(db)
        flow.stationChanged(to: "W5NK", context())
        XCTAssertEqual(flow.scpMatches.calls, ["W5NK"])
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
