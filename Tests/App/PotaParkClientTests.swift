import XCTest
@testable import QSOPartyLogger

@MainActor
final class PotaParkClientTests: XCTestCase {

    final class ScriptedFetcher: PotaParkFetching, @unchecked Sendable {
        var result: Result<Data, Error> = .failure(URLError(.notConnectedToInternet))
        private(set) var gets = 0
        func get(_ url: URL) async throws -> Data {
            gets += 1
            return try result.get()
        }
    }

    func tempStore() throws -> PotaParkStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PotaParkClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PotaParkStore(folder: dir)
    }

    func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_parks_sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testExplicitDownloadInstallsAndPublishes() async throws {
        let store = try tempStore()
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: store, fetcher: fetcher)
        await client.download()
        XCTAssertEqual(client.status, .ready(parks: 6))
        XCTAssertEqual(client.directory?.parks.count, 6)
        XCTAssertNotNil(store.loadMeta())
    }

    func testRefreshIfStaleNeverStartsTheFirstDownload() async throws {
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: try tempStore(), fetcher: fetcher)
        await client.refreshIfStale()
        XCTAssertEqual(fetcher.gets, 0, "the first download is the explicit button")
        XCTAssertEqual(client.status, .idle)
    }

    func testFreshCacheIsNotReDownloadedButForceIs() async throws {
        let store = try tempStore()
        let now = Date()
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: now, lastCheckedAt: now))
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: store, fetcher: fetcher)
        await client.refreshIfStale(now: now.addingTimeInterval(60))
        XCTAssertEqual(fetcher.gets, 0, "well inside the weekly throttle")
        await client.refreshIfStale(now: now.addingTimeInterval(60), force: true)
        XCTAssertEqual(fetcher.gets, 1, "Refresh is the operator's override")
    }

    func testStaleCacheReDownloads() async throws {
        let store = try tempStore()
        let old = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: old, lastCheckedAt: old))
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: store, fetcher: fetcher)
        await client.refreshIfStale()
        XCTAssertEqual(fetcher.gets, 1)
        XCTAssertEqual(client.status, .ready(parks: 6))
    }

    func testFailedRefreshKeepsTheCachedDirectory() async throws {
        let store = try tempStore()
        let old = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: old, lastCheckedAt: old))
        let client = PotaParkClient(store: store, fetcher: ScriptedFetcher())
        await client.refreshIfStale()
        XCTAssertEqual(client.directory?.parks.count, 6,
                       "whatever is cached stays in service")
        guard case .failed = client.status else {
            return XCTFail("failure belongs in the status line")
        }
    }

    func testPublishCachedTouchesNoNetwork() async throws {
        let store = try tempStore()
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: Date(), lastCheckedAt: Date()))
        let fetcher = ScriptedFetcher()
        let client = PotaParkClient(store: store, fetcher: fetcher)
        client.publishCached()
        XCTAssertEqual(client.status, .ready(parks: 6))
        XCTAssertEqual(fetcher.gets, 0)
    }
}
