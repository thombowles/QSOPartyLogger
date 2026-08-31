import XCTest
@testable import QSOPartyLogger

/// The window's background scan mode: matches land asynchronously, always
/// for the freshest fragment, and a stale scan never overwrites a newer
/// one. The default `.immediate` mode is the existing synchronous contract,
/// which every prior super-check test keeps exercising unchanged.
final class SuperCheckAsyncTests: XCTestCase {

    @MainActor
    private func makeFlow() -> EntryFlow {
        let flow = EntryFlow(document: LogDocument())
        flow.scpScanMode = .background
        flow.updateSCPDatabase(SCPDatabase(
            calls: ["K5AAA", "K5AAB", "K5ABC", "N5KO", "W5NK"], release: nil))
        return flow
    }

    @MainActor
    func testBackgroundScanPublishesForTheFragment() async throws {
        let flow = makeFlow()
        flow.entry.callTyped = "K5A"
        flow.callChanged(EntryFlow.Context())
        for _ in 0..<200 where flow.superCheckMatches == .none {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(flow.superCheckMatches.total, 3, "K5AAA, K5AAB, K5ABC")
    }

    @MainActor
    func testStaleScanNeverOvertakesTheNewerFragment() async throws {
        let flow = makeFlow()
        flow.entry.callTyped = "K5A"
        flow.callChanged(EntryFlow.Context())
        // The second keystroke lands before the first scan can apply.
        flow.entry.callTyped = "K5AB"
        flow.callChanged(EntryFlow.Context())
        for _ in 0..<200 where flow.superCheckMatches == .none {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // A beat for any straggling stale scan, then the newer set must stand.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(flow.superCheckMatches.total, 1, "only K5ABC contains K5AB")
    }
}
