import XCTest
@testable import QSOPartyLogger

final class CallHistoryStoreTests: XCTestCase {

    private var folder: URL!
    private var store: CallHistoryStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CallHistoryStoreTests-\(UUID().uuidString)")
        store = CallHistoryStore(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func meta(checked: Date = Date(timeIntervalSince1970: 1_000_000)) -> CallHistoryStore.Meta {
        CallHistoryStore.Meta(
            sourceFileName: "QSOP_KS-2025-002.txt",
            listedDate: "2025-08-24",
            fetchedAt: Date(timeIntervalSince1970: 999_000),
            lastCheckedAt: checked
        )
    }

    private let fileText = """
    !!Order!!,Call,Name,Exch1
    # QSOPARTY KS
    K0VBU,Bill,JOH
    """

    func testSaveThenLoadRoundTrips() throws {
        try store.save(partyID: "ksqp", data: Data(fileText.utf8), meta: meta())
        let cached = try XCTUnwrap(store.loadCached(partyID: "ksqp"))
        XCTAssertEqual(cached.parsed.entry(for: "K0VBU")?.locations, ["JOH"])
        XCTAssertEqual(cached.meta, meta())
        XCTAssertTrue(cached.parsed.tokens.contains("QSOPARTYKS"))
    }

    func testSaveCreatesTheFolder() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        try store.save(partyID: "ksqp", data: Data(fileText.utf8), meta: meta())
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMissingCacheIsNil() {
        XCTAssertNil(store.loadCached(partyID: "ksqp"))
        XCTAssertNil(store.loadMeta(partyID: "ksqp"))
    }

    /// A lost or mangled sidecar must never hide a readable file — prefill
    /// keeps working, only staleness bookkeeping resets.
    func testFileWithoutMetaStillServes() throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        try Data(fileText.utf8).write(to: store.fileURL(partyID: "ksqp"))
        let cached = try XCTUnwrap(store.loadCached(partyID: "ksqp"))
        XCTAssertNil(cached.meta)
        XCTAssertEqual(cached.parsed.recordCount, 1)

        try Data("not json".utf8).write(to: store.metaURL(partyID: "ksqp"))
        let corrupt = try XCTUnwrap(store.loadCached(partyID: "ksqp"))
        XCTAssertNil(corrupt.meta)
        XCTAssertEqual(corrupt.parsed.recordCount, 1)
    }

    func testTouchLastCheckedAdvancesOnlyTheClock() throws {
        try store.save(partyID: "ksqp", data: Data(fileText.utf8), meta: meta())
        let later = Date(timeIntervalSince1970: 2_000_000)
        try store.touchLastChecked(partyID: "ksqp", at: later)
        let reloaded = try XCTUnwrap(store.loadMeta(partyID: "ksqp"))
        XCTAssertEqual(reloaded.lastCheckedAt.timeIntervalSince1970,
                       later.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(reloaded.sourceFileName, "QSOP_KS-2025-002.txt")
        XCTAssertEqual(reloaded.fetchedAt.timeIntervalSince1970,
                       999_000, accuracy: 1)
    }

    func testTouchWithoutMetaIsANoOp() throws {
        XCTAssertNoThrow(try store.touchLastChecked(partyID: "ksqp", at: Date()))
        XCTAssertNil(store.loadMeta(partyID: "ksqp"))
    }

    /// Parties cache independently — the combined May file lands once per
    /// party it serves, so a Delaware refresh can never corrupt Indiana's.
    func testPartiesAreIndependent() throws {
        try store.save(partyID: "deqp", data: Data(fileText.utf8), meta: meta())
        XCTAssertNil(store.loadCached(partyID: "inqp"))
        XCTAssertNotNil(store.loadCached(partyID: "deqp"))
    }
}
