import XCTest
@testable import QSOPartyLogger

/// The lookup cache (spec 2026-08-25 decision 8): 30-day TTL, capped, so a
/// day's service allowance is never spent twice on one call.
final class CallbookCacheTests: XCTestCase {

    private func makeCache(cap: Int = 5000) -> CallbookCache {
        CallbookCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            cap: cap
        )
    }

    private func record(_ call: String, at t: TimeInterval) -> CallbookRecord {
        CallbookRecord(call: call, name: "Bob", qth: nil, state: "MO",
                       county: nil, grid: "EM48", country: nil, dxccID: nil,
                       source: .hamqth, fetchedAt: Date(timeIntervalSince1970: t))
    }

    func testRoundTripAndCaseInsensitiveKey() {
        let cache = makeCache()
        cache.store(record("W1AW", at: 0))
        XCTAssertEqual(cache.record(for: "w1aw",
                                    now: Date(timeIntervalSince1970: 60))?.state, "MO")
    }

    func testExpiredEntriesAreNotReturned() {
        let cache = makeCache()
        cache.store(record("W1AW", at: 0))
        let after31Days = Date(timeIntervalSince1970: 31 * 86_400)
        XCTAssertNil(cache.record(for: "W1AW", now: after31Days))
        let within = Date(timeIntervalSince1970: 29 * 86_400)
        XCTAssertNotNil(cache.record(for: "W1AW", now: within))
    }

    func testCapEvictsTheOldest() {
        let cache = makeCache(cap: 3)
        for (i, call) in ["A1A", "B2B", "C3C", "D4D"].enumerated() {
            cache.store(record(call, at: TimeInterval(i)))
        }
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertNil(cache.record(for: "A1A", now: now), "oldest evicted at the cap")
        XCTAssertNotNil(cache.record(for: "D4D", now: now))
    }

    func testSurvivesReload() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CallbookCache(directory: dir, cap: 100).store(record("W1AW", at: 0))
        let reloaded = CallbookCache(directory: dir, cap: 100)
        XCTAssertEqual(reloaded.record(for: "W1AW",
                                       now: Date(timeIntervalSince1970: 60))?.grid, "EM48")
    }
}
