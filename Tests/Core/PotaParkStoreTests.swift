import XCTest
@testable import QSOPartyLogger

final class PotaParkStoreTests: XCTestCase {

    func tempStore() throws -> PotaParkStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PotaParkStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PotaParkStore(folder: dir)
    }

    func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_parks_sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = try tempStore()
        let fetched = Date(timeIntervalSince1970: 1_754_400_000)
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: fetched, lastCheckedAt: fetched))
        let cached = try XCTUnwrap(store.loadCached())
        XCTAssertEqual(cached.directory.parks.count, 6)
        XCTAssertEqual(store.loadMeta()?.fetchedAt, fetched)
    }

    func testMissingSidecarNeverHidesAReadableFile() throws {
        let store = try tempStore()
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: Date(), lastCheckedAt: Date()))
        try FileManager.default.removeItem(at: store.metaURL)
        XCTAssertEqual(store.loadCached()?.directory.parks.count, 6)
        XCTAssertNil(store.loadCached()?.meta)
    }

    func testEmptyFolderLoadsNothing() throws {
        XCTAssertNil(try tempStore().loadCached())
        XCTAssertNil(try tempStore().loadMeta())
    }
}
