import XCTest
@testable import QSOPartyLogger

/// The client's decision-making, on scripted server answers. Never touches the
/// network (constitution Article 5) and never writes outside a temp folder.
@MainActor
final class DXCCLabelClientTests: XCTestCase {

    /// A scripted server. Records what was asked of it, so a test can assert
    /// that the body was *not* downloaded.
    final class Fetcher: DXCCFetching, @unchecked Sendable {
        var lastModified: String?
        var body: Data
        var headCount = 0
        var getCount = 0
        var headError: Error?

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
            return (body, lastModified)
        }
    }

    private var overlay: URL!

    override func setUpWithError() throws {
        overlay = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dxcc-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: overlay)
    }

    private func table() -> DXCCTable {
        DXCCTable(
            source: "ARRL DXCC List", fetched: "Mon, 03 Aug 2026 00:11:31 GMT",
            entities: [
                .init(code: "230", name: "Germany", continent: "EU",
                      prefixes: ["DA", "DL"], primaryPrefix: "DL"),
                .init(code: "223", name: "England", continent: "EU",
                      prefixes: ["G", "M"], primaryPrefix: "G"),
            ],
            prefixes: ["DA": "230", "DL": "230", "G": "223", "M": "223"],
            mergedPrefixes: [:], withoutPrefix: [:]
        )
    }

    // MARK: The everyday case

    /// Upstream unchanged: one HEAD, no download.
    func testAnUnchangedReleaseDownloadsNothing() async {
        let fetcher = Fetcher(lastModified: "Mon, 03 Aug 2026 00:11:31 GMT")
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        await client.refresh()
        XCTAssertEqual(fetcher.headCount, 1)
        XCTAssertEqual(fetcher.getCount, 0, "the 350 KB body must not be fetched")
        XCTAssertEqual(client.status, .current(release: "Mon, 03 Aug 2026 00:11:31 GMT"))
    }

    /// An older upstream is never taken — a clock or mirror going backwards
    /// must not roll labels back.
    func testAnOlderUpstreamIsIgnored() async {
        let fetcher = Fetcher(lastModified: "Mon, 01 Jan 2024 00:00:00 GMT")
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        await client.refresh()
        XCTAssertEqual(fetcher.getCount, 0)
    }

    // MARK: The throttle, which is what makes the triggers free

    /// Called at launch and at every contest load — so six logs in an
    /// afternoon must still make at most one request.
    func testRepeatedTriggersMakeOneRequestADay() async {
        let fetcher = Fetcher(lastModified: "Mon, 03 Aug 2026 00:11:31 GMT")
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        let start = Date(timeIntervalSince1970: 1_785_000_000)

        for i in 0..<6 {
            await client.refreshIfStale(now: start.addingTimeInterval(Double(i) * 600))
        }
        XCTAssertEqual(fetcher.headCount, 1, "six contest loads, one check")

        await client.refreshIfStale(now: start.addingTimeInterval(25 * 3600))
        XCTAssertEqual(fetcher.headCount, 2, "…and one more the next day")
    }

    // MARK: Failure is quiet

    func testAServerFailureLeavesTheHeldLabelsAlone() async {
        let fetcher = Fetcher(lastModified: nil)
        fetcher.headError = URLError(.notConnectedToInternet)
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        await client.refresh()
        if case .failed = client.status {} else {
            XCTFail("expected .failed, got \(client.status)")
        }
        XCTAssertNotNil(client.lastError)
        XCTAssertNil(DXCCLabelStore.loadLabels(at: overlay), "nothing stored on failure")
    }

    /// No Last-Modified means freshness cannot be judged, and downloading
    /// blind would be worse than doing nothing.
    func testAMissingReleaseHeaderIsAFailureRatherThanABlindDownload() async {
        let fetcher = Fetcher(lastModified: nil)
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        await client.refresh()
        XCTAssertEqual(fetcher.getCount, 0)
        if case .failed = client.status {} else { XCTFail("expected .failed") }
    }

    /// A newer file whose contents this cannot account for is refused, and the
    /// held labels stay in service.
    func testANewerButUnusableFileIsRefused() async {
        let fetcher = Fetcher(lastModified: "Tue, 04 Aug 2026 00:00:00 GMT",
                              body: Data("nonsense".utf8))
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        await client.refresh()
        XCTAssertEqual(fetcher.getCount, 1, "it did download")
        if case .failed = client.status {} else { XCTFail("…and then refused it") }
        XCTAssertNil(DXCCLabelStore.loadLabels(at: overlay))
    }

    // MARK: A real change

    func testANewerFileWithAMovedLabelIsStoredForTheNextLaunch() async throws {
        let cty = """
        Fed. Rep. of Germany:     14:  28:  EU:   51.00:   -10.00:    -1.0:  DA:
            DA,DL;
        England:                  14:  27:  EU:   52.00:    -1.00:    -0.0:  G:
            G,M;
        """ + (0..<6).map { "\nWAE \($0): 14: 27: EU: 50.0: -1.0: -1.0: *W\($0):\n    W\($0);" }.joined()
        // Padded past the truncation floor the way the real 350 KB file is.
        let padded = cty + "\n" + String(repeating: " ", count: DXCCLabelRefresh.minimumBytes)

        let fetcher = Fetcher(lastModified: "Tue, 04 Aug 2026 00:00:00 GMT",
                              body: Data(padded.utf8))
        let client = DXCCLabelClient(fetcher: fetcher, table: table(), overlayURL: overlay)
        await client.refresh()

        XCTAssertEqual(client.status, .updated(count: 1, release: "Tue, 04 Aug 2026 00:00:00 GMT"))
        XCTAssertEqual(DXCCLabelStore.loadLabels(at: overlay), ["230": "DA"])

        // Stored, not live: the running table is untouched, so no contest has
        // its labels change underneath it.
        XCTAssertEqual(table().entities.first { $0.code == "230" }?.primaryPrefix, "DL")
        // It is a load-time overlay, and it only moves the label.
        let next = table().applyingLabels(DXCCLabelStore.loadLabels(at: overlay) ?? [:])
        XCTAssertEqual(next.entities.first { $0.code == "230" }?.primaryPrefix, "DA")
        XCTAssertEqual(next.entity(forCallsign: "DL1AA")?.code, "230")
    }
}
