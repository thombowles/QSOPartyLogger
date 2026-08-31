import XCTest
@testable import QSOPartyLogger

/// The user folders are re-read only when their contents change. The cache
/// is an optimisation and correctness is the contract: an added, removed, or
/// edited-in-place file must be served fresh on the very next call — a stale
/// definition silently scoring a contest is the failure mode to fear.
final class CatalogCacheTests: XCTestCase {

    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A valid v2 contest JSON: the bundled POTA definition with its id and
    /// name swapped — nothing hand-typed that the schema could refuse.
    private func contestJSON(id: String, name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "pota", withExtension: "json", subdirectory: "Contests"))
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["id"] = id
        object["name"] = name
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// Rewriting in place with a guaranteed-moved mtime, so the test never
    /// races the filesystem's timestamp granularity.
    private func write(_ data: Data, to url: URL, mtime: Date) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    func testEditedInPlaceFileIsServedFresh() throws {
        let file = dir.appendingPathComponent("mine.json")
        let base = Date(timeIntervalSince1970: 1_788_300_000)
        try write(try contestJSON(id: "cachetest", name: "AAA"), to: file, mtime: base)

        let first = ContestCatalog.loadUserContests(in: dir)
        XCTAssertEqual(try first.first?.result.get().name, "AAA")

        // Same call again — the cached answer must be the same answer.
        XCTAssertEqual(try ContestCatalog.loadUserContests(in: dir).first?.result.get().name, "AAA")

        // Edited in place (same byte count, same name) — only the mtime moves.
        try write(try contestJSON(id: "cachetest", name: "BBB"), to: file, mtime: base.addingTimeInterval(5))
        XCTAssertEqual(try ContestCatalog.loadUserContests(in: dir).first?.result.get().name, "BBB")
    }

    func testAddedAndRemovedFilesAreServedFresh() throws {
        XCTAssertTrue(ContestCatalog.loadUserContests(in: dir).isEmpty)

        let file = dir.appendingPathComponent("added.json")
        try write(try contestJSON(id: "cachetest2", name: "Added"),
                  to: file, mtime: Date(timeIntervalSince1970: 1_788_300_100))
        XCTAssertEqual(ContestCatalog.loadUserContests(in: dir).count, 1)

        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(ContestCatalog.loadUserContests(in: dir).isEmpty)
    }

    func testUserPartiesFolderTakesADirectoryAndCaches() throws {
        // No party files: empty, twice (second answer from the cache).
        XCTAssertTrue(PartyCatalog.loadUserParties(in: dir).isEmpty)
        XCTAssertTrue(PartyCatalog.loadUserParties(in: dir).isEmpty)

        // A malformed file is returned as its failure — and stays returned
        // through the cache.
        let bad = dir.appendingPathComponent("broken.json")
        try write(Data("not json".utf8), to: bad, mtime: Date(timeIntervalSince1970: 1_788_300_200))
        XCTAssertEqual(PartyCatalog.loadUserParties(in: dir).count, 1)
        if case .success = PartyCatalog.loadUserParties(in: dir)[0].result {
            XCTFail("a broken file must be returned as a failure")
        }
    }

    func testStampMovesWithEdits() throws {
        let before = UserFolderStamp.of(dir)
        XCTAssertEqual(before, UserFolderStamp.of(dir))
        let file = dir.appendingPathComponent("a.json")
        try write(Data("{}".utf8), to: file, mtime: Date(timeIntervalSince1970: 1_788_300_300))
        let added = UserFolderStamp.of(dir)
        XCTAssertNotEqual(before, added)
        // Same size, later mtime — still a different stamp.
        try write(Data("{}".utf8), to: file, mtime: Date(timeIntervalSince1970: 1_788_300_305))
        XCTAssertNotEqual(added, UserFolderStamp.of(dir))
    }
}
