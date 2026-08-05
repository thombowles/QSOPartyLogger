import XCTest
@testable import QSOPartyLogger

/// The client's decision-making on scripted server answers. Never touches
/// the network (constitution Article 5) and never writes outside a temp
/// folder.
@MainActor
final class SCPClientTests: XCTestCase {

    /// A scripted server that records what was asked of it, so a test can
    /// assert the ~360 KB body was *not* downloaded.
    final class Fetcher: SCPFetching, @unchecked Sendable {
        var lastModified: String?
        var body: Data
        var headCount = 0
        var getCount = 0
        var headError: Error?
        var getError: Error?

        init(lastModified: String?, body: Data = Data()) {
            self.lastModified = lastModified
            self.body = body
        }

        func head(_ url: URL) async throws -> String? {
            headCount += 1
            if let headError { throw headError }
            return lastModified
        }

        func get(_ url: URL) async throws -> (Data, String?) {
            getCount += 1
            if let getError { throw getError }
            return (body, lastModified)
        }
    }

    private var folder: URL!
    private var store: SCPStore!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scpclient-\(UUID().uuidString)", isDirectory: true)
        store = SCPStore(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A plausible file: a release comment and enough generated calls to
    /// clear `SCPDatabase.minimumRecords`.
    private func plausibleFile(release: String = "2026.07.31") -> Data {
        var lines = ["!!Order,1,1", "# Release \(release)"]
        for i in 0..<(SCPDatabase.minimumRecords + 100) {
            lines.append(String(format: "K5AA%04d", i))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private func installedMeta(
        lastModified: String = "Fri, 31 Jul 2026 00:03:08 GMT",
        checkedAt: Date = Date(timeIntervalSince1970: 1_785_000_000)
    ) throws {
        try store.save(
            data: plausibleFile(),
            meta: SCPStore.Meta(
                sourceLastModified: lastModified,
                fetchedAt: Date(timeIntervalSince1970: 1_785_000_000),
                lastCheckedAt: checkedAt
            )
        )
    }

    // MARK: First launch — nothing cached

    /// No cached file means nothing to compare and nothing to protect:
    /// straight to the download, no HEAD first. This is what makes the
    /// feature zero-setup.
    func testFirstLaunchDownloadsWithoutAHead() async throws {
        let fetcher = Fetcher(lastModified: "Fri, 31 Jul 2026 00:03:08 GMT",
                              body: plausibleFile())
        let client = SCPClient(store: store, fetcher: fetcher)
        var published: SCPDatabase?
        client.onDatabase = { published = $0 }

        await client.refreshIfStale(now: Date(timeIntervalSince1970: 1_785_000_000))

        XCTAssertEqual(fetcher.headCount, 0)
        XCTAssertEqual(fetcher.getCount, 1)
        XCTAssertEqual(published?.recordCount, SCPDatabase.minimumRecords + 100)
        XCTAssertEqual(store.loadMeta()?.sourceLastModified,
                       "Fri, 31 Jul 2026 00:03:08 GMT")
        if case .ready = client.status {} else {
            XCTFail("expected .ready, got \(client.status)")
        }
    }

    // MARK: The everyday case — cached and current

    func testAnUnchangedReleaseDownloadsNothing() async throws {
        try installedMeta()
        let fetcher = Fetcher(lastModified: "Fri, 31 Jul 2026 00:03:08 GMT")
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        XCTAssertEqual(fetcher.headCount, 1)
        XCTAssertEqual(fetcher.getCount, 0, "the ~360 KB body must not be fetched")
        if case .ready = client.status {} else {
            XCTFail("expected .ready, got \(client.status)")
        }
    }

    /// An older upstream is never taken — a mirror or clock going backwards
    /// must not roll the database back.
    func testAnOlderUpstreamIsIgnored() async throws {
        try installedMeta()
        let fetcher = Fetcher(lastModified: "Mon, 01 Jan 2024 00:00:00 GMT")
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        XCTAssertEqual(fetcher.getCount, 0)
    }

    // MARK: The throttle, which is what makes the triggers free

    /// Called at launch and at every contest load — six logs in an
    /// afternoon must still make at most one check.
    func testRepeatedTriggersMakeOneCheckADay() async throws {
        try installedMeta(checkedAt: Date(timeIntervalSince1970: 1_785_000_000))
        let fetcher = Fetcher(lastModified: "Fri, 31 Jul 2026 00:03:08 GMT")
        let client = SCPClient(store: store, fetcher: fetcher)
        let start = Date(timeIntervalSince1970: 1_785_000_100)

        for i in 0..<6 {
            await client.refreshIfStale(now: start.addingTimeInterval(Double(i) * 600))
        }
        XCTAssertEqual(fetcher.headCount, 0, "all six inside the throttle window")

        await client.refreshIfStale(now: start.addingTimeInterval(25 * 3600))
        XCTAssertEqual(fetcher.headCount, 1, "…and one check the next day")
    }

    /// The Contest Setup Refresh button bypasses the throttle but not the
    /// freshness comparison.
    func testForceBypassesTheThrottle() async throws {
        try installedMeta(checkedAt: Date(timeIntervalSince1970: 1_785_000_000))
        let fetcher = Fetcher(lastModified: "Fri, 31 Jul 2026 00:03:08 GMT")
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refreshIfStale(
            now: Date(timeIntervalSince1970: 1_785_000_100), force: true)
        XCTAssertEqual(fetcher.headCount, 1)
        XCTAssertEqual(fetcher.getCount, 0)
    }

    // MARK: Failure is quiet, and the cache stays

    func testAServerFailureKeepsTheCachedFile() async throws {
        try installedMeta()
        let fetcher = Fetcher(lastModified: nil)
        fetcher.headError = URLError(.notConnectedToInternet)
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        if case .failed = client.status {} else {
            XCTFail("expected .failed, got \(client.status)")
        }
        XCTAssertNotNil(client.lastError)
        XCTAssertNotNil(store.loadCached(), "the cached file stays in service")
    }

    /// A transport failure must say what is still true, the way
    /// `CallHistoryClient` does — never a bare system string.
    ///
    /// Measured need, not a hypothetical: on 2026-08-05 supercheckpartial.com's
    /// CDN was timing out about half its requests (HEAD and GET alike, ~7 s
    /// when it answered at all), and the Refresh button reported the whole of
    /// it as "The request timed out." — which reads as a broken feature while
    /// a complete database sits cached and the strip works perfectly.
    func testATransportFailureNamesTheHostAndWhatStaysInService() async throws {
        try installedMeta()
        let fetcher = Fetcher(lastModified: nil)
        fetcher.headError = URLError(.timedOut)
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))

        let message = try XCTUnwrap(client.lastError)
        XCTAssertNotEqual(
            message, URLError(.timedOut).localizedDescription,
            "the bare system string is exactly what the operator saw on 2026-08-05"
        )
        XCTAssertTrue(message.contains("supercheckpartial.com"),
                      "name what could not be reached — got: \(message)")
        XCTAssertTrue(message.contains("stay in use"),
                      "say the cached calls survive — got: \(message)")
        XCTAssertTrue(message.contains("\(SCPDatabase.minimumRecords + 100)"),
                      "say how many are still in service — got: \(message)")
    }

    /// With nothing cached there is no reassurance to offer, and the message
    /// must not pretend otherwise.
    func testATransportFailureWithNoCacheSaysTheStripStaysEmpty() async {
        let fetcher = Fetcher(lastModified: nil)
        fetcher.getError = URLError(.notConnectedToInternet)
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_000_000))

        let message = client.lastError ?? ""
        XCTAssertTrue(message.contains("supercheckpartial.com"), message)
        XCTAssertFalse(message.contains("stay in use"),
                       "nothing is cached, so nothing stays in use — got: \(message)")
    }

    /// Our own refusals already explain themselves and must not be
    /// double-wrapped into "Couldn't reach … The server answered with a page".
    func testOurOwnRefusalsAreNotWrappedAsUnreachable() async throws {
        try installedMeta()
        let fetcher = Fetcher(
            lastModified: "Sat, 01 Aug 2026 00:00:00 GMT",
            body: Data("<!DOCTYPE html><html><body>denied".utf8)
        )
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        let message = client.lastError ?? ""
        XCTAssertFalse(message.contains("Couldn't reach"),
                       "the server was reached — got: \(message)")
        XCTAssertTrue(message.contains("page instead of the file"), message)
    }

    /// With a cache, a missing Last-Modified means freshness cannot be
    /// judged — downloading blind would be the worse error.
    func testAMissingHeaderWithACacheIsAQuietFailureNotABlindDownload() async throws {
        try installedMeta()
        let fetcher = Fetcher(lastModified: nil)
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        XCTAssertEqual(fetcher.getCount, 0)
        if case .failed = client.status {} else { XCTFail("expected .failed") }
    }

    /// Without a cache the same missing header changes nothing: there is
    /// nothing to protect, so the download happens anyway.
    func testAMissingHeaderWithoutACacheStillDownloads() async {
        let fetcher = Fetcher(lastModified: nil, body: plausibleFile())
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_000_000))
        XCTAssertEqual(fetcher.getCount, 1)
        if case .ready = client.status {} else { XCTFail("expected .ready") }
        XCTAssertEqual(store.loadMeta()?.sourceLastModified, "")
    }

    /// The site answering a refused download with its error *page*, status
    /// 200 — bytes that must not install as a database.
    func testAnHTMLMasqueradeIsRefused() async throws {
        try installedMeta()
        let fetcher = Fetcher(
            lastModified: "Sat, 01 Aug 2026 00:00:00 GMT",
            body: Data("<!DOCTYPE html><html><body>denied".utf8)
        )
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        XCTAssertEqual(fetcher.getCount, 1, "it did download")
        if case .failed = client.status {} else { XCTFail("…and then refused it") }
        XCTAssertEqual(store.loadMeta()?.sourceLastModified,
                       "Fri, 31 Jul 2026 00:03:08 GMT",
                       "the held release survives")
    }

    /// A newer but implausibly small file — truncation, a stub, a
    /// lookalike — is refused and the held release stays.
    func testATruncatedFileIsRefused() async throws {
        try installedMeta()
        let fetcher = Fetcher(
            lastModified: "Sat, 01 Aug 2026 00:00:00 GMT",
            body: Data("# Release 2026.08.01\r\nK5C\r\nN5KO\r\n".utf8)
        )
        let client = SCPClient(store: store, fetcher: fetcher)
        await client.refresh(now: Date(timeIntervalSince1970: 1_785_090_000))
        if case .failed = client.status {} else { XCTFail("expected .failed") }
        XCTAssertEqual(store.loadCached()?.database.release, "2026.07.31")
    }

    // MARK: A real update

    func testANewerReleaseInstallsAndPublishes() async throws {
        try installedMeta()
        let fetcher = Fetcher(
            lastModified: "Sat, 01 Aug 2026 00:00:00 GMT",
            body: plausibleFile(release: "2026.08.01")
        )
        let client = SCPClient(store: store, fetcher: fetcher)
        var published: SCPDatabase?
        client.onDatabase = { published = $0 }

        let now = Date(timeIntervalSince1970: 1_785_090_000)
        await client.refresh(now: now)

        XCTAssertEqual(published?.release, "2026.08.01")
        XCTAssertEqual(store.loadCached()?.database.release, "2026.08.01")
        XCTAssertEqual(store.loadMeta()?.sourceLastModified,
                       "Sat, 01 Aug 2026 00:00:00 GMT")
        XCTAssertEqual(store.loadMeta()?.lastCheckedAt, now)
        if case .ready(let records, let release) = client.status {
            XCTAssertEqual(records, SCPDatabase.minimumRecords + 100)
            XCTAssertEqual(release, "2026.08.01")
        } else {
            XCTFail("expected .ready, got \(client.status)")
        }
    }

    /// The cached database is published immediately at activation — before
    /// any network is considered.
    func testPublishCachedServesTheFileAtOnce() throws {
        try installedMeta()
        let client = SCPClient(store: store, fetcher: Fetcher(lastModified: nil))
        var published: SCPDatabase?
        client.onDatabase = { published = $0 }
        client.publishCached()
        XCTAssertEqual(published?.recordCount, SCPDatabase.minimumRecords + 100)
        if case .ready = client.status {} else { XCTFail("expected .ready") }
    }
}
