import XCTest
@testable import QSOPartyLogger

/// The cache round-trip, in a temp folder only — the real Application
/// Support folder is never touched (constitution Article 5).
final class SCPStoreTests: XCTestCase {

    private var folder: URL!
    private var store: SCPStore!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scp-\(UUID().uuidString)", isDirectory: true)
        store = SCPStore(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let fileText = "# Release 2026.07.31\nK5C\nN5KO\nW5NK\n"

    private func meta(checked: Date = Date(timeIntervalSince1970: 1_785_000_000))
    -> SCPStore.Meta {
        SCPStore.Meta(
            sourceLastModified: "Fri, 31 Jul 2026 00:03:08 GMT",
            fetchedAt: Date(timeIntervalSince1970: 1_785_000_000),
            lastCheckedAt: checked
        )
    }

    func testSaveThenLoadRoundTrips() throws {
        try store.save(data: Data(fileText.utf8), meta: meta())
        let cached = try XCTUnwrap(store.loadCached())
        XCTAssertEqual(cached.database.calls, ["K5C", "N5KO", "W5NK"])
        XCTAssertEqual(cached.database.release, "2026.07.31")
        XCTAssertEqual(cached.meta, meta())
    }

    func testNothingCachedIsNil() {
        XCTAssertNil(store.loadCached())
        XCTAssertNil(store.loadMeta())
    }

    /// A missing or unreadable sidecar never hides a readable file — the
    /// strip keeps working and only the staleness bookkeeping resets.
    func testMissingSidecarStillServesTheFile() throws {
        try store.save(data: Data(fileText.utf8), meta: meta())
        try FileManager.default.removeItem(at: store.metaURL)
        let cached = try XCTUnwrap(store.loadCached())
        XCTAssertNil(cached.meta)
        XCTAssertEqual(cached.database.recordCount, 3)
    }

    /// "Checked, nothing newer" advances the throttle clock without
    /// touching the file.
    func testTouchLastCheckedAdvancesOnlyTheClock() throws {
        try store.save(data: Data(fileText.utf8), meta: meta())
        let later = Date(timeIntervalSince1970: 1_785_100_000)
        try store.touchLastChecked(at: later)
        let reloaded = try XCTUnwrap(store.loadMeta())
        XCTAssertEqual(reloaded.lastCheckedAt, later)
        XCTAssertEqual(reloaded.sourceLastModified, meta().sourceLastModified)
        XCTAssertEqual(reloaded.fetchedAt, meta().fetchedAt)
    }

    /// With no sidecar there is nothing truthful to write about an unknown
    /// revision — touch is a no-op, not an invention.
    func testTouchWithoutSidecarWritesNothing() throws {
        try store.save(data: Data(fileText.utf8), meta: meta())
        try FileManager.default.removeItem(at: store.metaURL)
        try store.touchLastChecked(at: Date())
        XCTAssertNil(store.loadMeta())
    }
}
