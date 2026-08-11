import XCTest
@testable import QSOPartyLogger

/// The download orchestration, scripted end to end against a mock site —
/// no test here touches the network (constitution Article 5). The failure
/// posture under test throughout: whatever file is cached stays in service.
@MainActor
final class CallHistoryClientTests: XCTestCase {

    // MARK: Scripted site

    final class MockFetcher: CallHistoryFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [String] = []
        var requests: [String] {
            lock.lock(); defer { lock.unlock() }
            return _requests
        }

        /// Substring-matched, first hit wins. A URL nothing matches throws.
        var getResponses: [(match: String, status: Int, body: Data)] = []
        var postResponses: [(match: String, status: Int, body: Data)] = []
        var error: Error?

        private func record(_ line: String) {
            lock.lock(); defer { lock.unlock() }
            _requests.append(line)
        }

        func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
            record("GET \(url.absoluteString)")
            if let error { throw error }
            guard let scripted = getResponses.first(
                where: { url.absoluteString.contains($0.match) }) else {
                throw URLError(.unsupportedURL)
            }
            return (scripted.body, response(url: url, status: scripted.status))
        }

        func post(
            _ url: URL, form: [String: String], referer: String
        ) async throws -> (Data, HTTPURLResponse) {
            let fields = form.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            record("POST \(url.absoluteString) referer=\(referer) \(fields)")
            if let error { throw error }
            guard let scripted = postResponses.first(
                where: { url.absoluteString.contains($0.match) }) else {
                throw URLError(.unsupportedURL)
            }
            return (scripted.body, response(url: url, status: scripted.status))
        }

        private func response(url: URL, status: Int) -> HTTPURLResponse {
            HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
    }

    // MARK: Fixtures

    private var folder: URL!
    private var store: CallHistoryStore!
    private var fetcher: MockFetcher!
    private var client: CallHistoryClient!
    private var published: [(partyID: String, records: Int)] = []

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CallHistoryClientTests-\(UUID().uuidString)")
        store = CallHistoryStore(folder: folder)
        fetcher = MockFetcher()
        client = CallHistoryClient(store: store, fetcher: fetcher)
        published = []
        client.onIndex = { [weak self] id, parsed in
            self?.published.append((id, parsed.recordCount))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: id), id)
    }

    private let fileText = """
    !!Order!!,Call,Name,Exch1,UserText,
    # QSOPARTY KS
    # QSOP_KS
    K0VBU,Bill,JOH
    W0BH,Bob,BAR
    """

    private func listingHTML(_ rows: [(file: String, slug: String, date: String)]) -> String {
        let items = rows.map { row in
            """
            <li><span>
            <a href="https://n1mmwp.hamdocs.com/mmfiles/\(row.slug)/">
            <span class="cmdm-list-item-title">\(row.file)</span></a>
            <div class="cmdm-list-item-desc"> \(row.date) </div></span></li>
            """
        }.joined()
        return "<div class=\"CMDM-list-view\"><ul>\(items)</ul></div>"
    }

    private func filePageHTML(file: String, nonce: String = "abc123", id: String = "99") -> String {
        """
        <form method="post" class="CMDM-downloadForm" \
        action="https://n1mmwp.hamdocs.com/mmfile/get/file/\(file)">
        <input type="hidden" name="cmdm_nonce" value="\(nonce)" />
        <input type="hidden" name="id" value="\(id)" />
        </form>
        """
    }

    private func scriptHappyPath(
        file: String = "QSOP_KS-2025-002.txt",
        slug: String = "qsop_ks-2025-002-txt",
        date: String = "2025-08-24",
        body: String? = nil
    ) {
        fetcher.getResponses = [
            ("CMDsearch", 200, Data(listingHTML([(file, slug, date)]).utf8)),
            ("/mmfiles/\(slug)/", 200, Data(filePageHTML(file: file).utf8)),
        ]
        fetcher.postResponses = [
            ("/mmfile/get/file/", 200, Data((body ?? fileText).utf8)),
        ]
    }

    // MARK: Install

    func testDownloadsVerifiesAndInstalls() async throws {
        scriptHappyPath()
        await client.refreshIfStale(party: try party("ksqp"), now: now)

        XCTAssertEqual(client.status, .ready(
            partyID: "ksqp", revision: "QSOP_KS-2025-002.txt", records: 2))
        XCTAssertEqual(published.map(\.partyID), ["ksqp"])
        XCTAssertEqual(published.first?.records, 2)

        let cached = try XCTUnwrap(store.loadCached(partyID: "ksqp"))
        XCTAssertEqual(cached.meta?.sourceFileName, "QSOP_KS-2025-002.txt")
        XCTAssertEqual(cached.meta?.listedDate, "2025-08-24")
        XCTAssertEqual(cached.parsed.entry(for: "K0VBU")?.locations, ["JOH"])

        // The POST carried the form's nonce and rode on the page as referer.
        let post = try XCTUnwrap(fetcher.requests.last)
        XCTAssertTrue(post.contains("cmdm_nonce=abc123"))
        XCTAssertTrue(post.contains("id=99"))
        XCTAssertTrue(post.contains("referer=https://n1mmwp.hamdocs.com/mmfiles/qsop_ks-2025-002-txt/"))
    }

    /// The listing's newest *claimed* row wins — New England's file above
    /// Nebraska's must be passed over for Nebraska (the separator rule,
    /// live).
    func testPicksTheNewestClaimedRow() async throws {
        fetcher.getResponses = [
            ("CMDsearch", 200, Data(listingHTML([
                ("QSOP_NEWE-2026-001.txt", "qsop_newe-2026-001-txt", "2026-04-30"),
                ("QSOP_NE-2026-002.txt", "qsop_ne-2026-002-txt", "2026-04-15"),
            ]).utf8)),
            ("/mmfiles/qsop_ne-2026-002-txt/", 200,
             Data(filePageHTML(file: "QSOP_NE-2026-002.txt").utf8)),
        ]
        fetcher.postResponses = [
            ("/mmfile/get/file/", 200, Data("""
            !!Order!!,Call,Exch1
            # QSOPARTY NE
            AA0W,DIXO
            """.utf8)),
        ]
        await client.refreshIfStale(party: try party("neqp"), now: now)
        XCTAssertEqual(client.status, .ready(
            partyID: "neqp", revision: "QSOP_NE-2026-002.txt", records: 1))
        XCTAssertFalse(fetcher.requests.joined().contains("qsop_newe"),
                       "New England's page must never have been touched")
    }

    // MARK: Short circuits

    func testCurrentRevisionChecksButDoesNotDownload() async throws {
        try store.save(
            partyID: "ksqp", data: Data(fileText.utf8),
            meta: .init(sourceFileName: "QSOP_KS-2025-002.txt",
                        listedDate: "2025-08-24",
                        fetchedAt: now.addingTimeInterval(-100_000),
                        lastCheckedAt: now.addingTimeInterval(-100_000)))
        scriptHappyPath()

        await client.refreshIfStale(party: try party("ksqp"), now: now)

        XCTAssertEqual(fetcher.requests.count, 1, "one listing GET, nothing else")
        XCTAssertEqual(store.loadMeta(partyID: "ksqp")?.lastCheckedAt
                        .timeIntervalSince1970 ?? 0,
                       now.timeIntervalSince1970, accuracy: 1,
                       "the throttle clock advanced")
        XCTAssertEqual(client.status, .ready(
            partyID: "ksqp", revision: "QSOP_KS-2025-002.txt", records: 2),
            "the cached copy is (re)published as ready")
    }

    func testRecentCheckSkipsTheNetworkEntirely() async throws {
        try store.save(
            partyID: "ksqp", data: Data(fileText.utf8),
            meta: .init(sourceFileName: "QSOP_KS-2025-002.txt",
                        listedDate: "2025-08-24",
                        fetchedAt: now.addingTimeInterval(-3600),
                        lastCheckedAt: now.addingTimeInterval(-3600)))
        scriptHappyPath()

        await client.refreshIfStale(party: try party("ksqp"), now: now)
        XCTAssertEqual(fetcher.requests, [], "checked an hour ago — leave the site alone")

        await client.refreshIfStale(party: try party("ksqp"), now: now, force: true)
        XCTAssertFalse(fetcher.requests.isEmpty, "the Refresh button overrides the throttle")
    }

    func testPartyWithoutASourceIsUntouched() async throws {
        await client.refreshIfStale(party: try party("azqp"), now: now)
        XCTAssertEqual(fetcher.requests, [])
        XCTAssertEqual(client.status, .idle)
    }

    // MARK: Failures keep the cache

    private func preSeedCache() throws {
        try store.save(
            partyID: "ksqp", data: Data(fileText.utf8),
            meta: .init(sourceFileName: "QSOP_KS-2025-001.txt",
                        listedDate: "2025-07-01",
                        fetchedAt: now.addingTimeInterval(-200_000),
                        lastCheckedAt: now.addingTimeInterval(-200_000)))
    }

    private func assertCacheIntact(file: StaticString = #filePath, line: UInt = #line) {
        let cached = store.loadCached(partyID: "ksqp")
        XCTAssertEqual(cached?.meta?.sourceFileName, "QSOP_KS-2025-001.txt",
                       "the cached revision must have survived", file: file, line: line)
        XCTAssertEqual(cached?.parsed.recordCount, 2, file: file, line: line)
    }

    func testTokenMismatchIsNotInstalled() async throws {
        try preSeedCache()
        scriptHappyPath(body: """
        !!Order!!,Call,Exch1
        # QSOPARTY TX
        AA5AH,DALS
        """)
        await client.refreshIfStale(party: try party("ksqp"), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("does not declare"), message)
        assertCacheIntact()
        XCTAssertTrue(published.isEmpty, "a rejected file must not reach prefill")
    }

    /// The site answers a refused download with its access-denied *page*,
    /// status 200 — bytes that would otherwise install as an empty file.
    func testHTMLBodyIsRefusedNotInstalled() async throws {
        try preSeedCache()
        scriptHappyPath(body: "<!DOCTYPE html>\n<html><body>Access denied</body></html>")
        await client.refreshIfStale(party: try party("ksqp"), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("refused"), message)
        assertCacheIntact()
    }

    func testReshapedListingFailsLoudly() async throws {
        try preSeedCache()
        fetcher.getResponses = [
            ("CMDsearch", 200, Data("<html><body>redesign!</body></html>".utf8)),
        ]
        await client.refreshIfStale(party: try party("ksqp"), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("changed shape"), message)
        assertCacheIntact()
    }

    func testEmptyListingNamesThePrefix() async throws {
        try preSeedCache()
        fetcher.getResponses = [
            ("CMDsearch", 200, Data(listingHTML([]).utf8)),
        ]
        await client.refreshIfStale(party: try party("ksqp"), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("QSOP_KS"), message)
        assertCacheIntact()
    }

    func testNetworkFailureKeepsTheCache() async throws {
        try preSeedCache()
        fetcher.error = URLError(.notConnectedToInternet)
        await client.refreshIfStale(party: try party("ksqp"), now: now)

        guard case .failed = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertNotNil(client.lastError)
        assertCacheIntact()
    }

    // MARK: Cached publication

    func testPublishCachedServesTheStoredFile() throws {
        try preSeedCache()
        client.publishCached(party: try party("ksqp"))
        XCTAssertEqual(published.map(\.partyID), ["ksqp"])
        XCTAssertEqual(client.status, .ready(
            partyID: "ksqp", revision: "QSOP_KS-2025-001.txt", records: 2))
    }

    func testPublishCachedIsQuietWithNothingCached() throws {
        client.publishCached(party: try party("ksqp"))
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(client.status, .idle)
    }

    // MARK: The roster-page kind (Skeeter Hunt)

    /// A synthetic roster-kind party — the capability ships before any
    /// bundled party carries the kind, so the definition is decoded inline.
    private func rosterParty() throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"rp","name":"RP","cabrilloContest":"RP","homeState":"NA",
        "countyAbbrLength":2,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode","hasHomeRegion":false,
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[],
        "callHistory":{"kind":"w2ljRosterPage","pageURL":"https://sponsor.test/skeeter.html",
        "filePrefix":"SKEETER","token":"SKEETER ROSTER"}}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    private let rosterPageHTML = """
    <p>The entire 2026 Skeeter Hunt roster can be seen
    https://docs.google.com/spreadsheets/d/SHEETID123/edit?usp=drivesdk.</p>
    <p>2025 Scoreboard - click
    <a href="https://docs.google.com/spreadsheets/d/SCOREBOARD999/edit">here</a></p>
    """

    private let rosterCSV = """
    Skeeter #,Call,Name,S/P/C,Mode,Skeeter QSOs
    13,W2LJ,Larry,NJ, ,0
    20,KE5CW,Tom,TX, ,0
    """

    private func scriptRosterHappyPath() {
        fetcher.getResponses = [
            ("sponsor.test", 200, Data(rosterPageHTML.utf8)),
            ("SHEETID123/export?format=csv", 200, Data(rosterCSV.utf8)),
        ]
    }

    func testRosterDownloadsConvertsAndInstalls() async throws {
        scriptRosterHappyPath()
        await client.refreshIfStale(party: try rosterParty(), now: now)

        XCTAssertEqual(published.map(\.partyID), ["rp"])
        XCTAssertEqual(published.map(\.records), [2])
        guard case .ready(let id, let revision, let records) = client.status else {
            return XCTFail("expected ready, got \(client.status)")
        }
        XCTAssertEqual(id, "rp")
        XCTAssertEqual(records, 2)
        XCTAssertTrue(revision.hasPrefix("roster "), revision)

        // The installed file is the converted call-history shape, and it
        // declares the token it was installed under.
        let cached = try XCTUnwrap(store.loadCached(partyID: "rp"))
        XCTAssertEqual(cached.parsed.entry(for: "W2LJ")?.locations, ["13", "NJ"])
        XCTAssertTrue(
            cached.parsed.tokens.contains(CallHistorySource.normalized("SKEETER ROSTER")))

        // The scoreboard sheet was never touched.
        XCTAssertFalse(fetcher.requests.contains { $0.contains("SCOREBOARD999") })
    }

    /// The sheet is live, so a fresh check within the throttle does nothing
    /// and a forced one re-downloads — there is no unchanged-revision short
    /// circuit to hide behind.
    func testRosterHoldsToTheThrottleAndForceBypassesIt() async throws {
        scriptRosterHappyPath()
        let party = try rosterParty()
        await client.refreshIfStale(party: party, now: now)
        let firstRequestCount = fetcher.requests.count

        await client.refreshIfStale(party: party, now: now.addingTimeInterval(60))
        XCTAssertEqual(fetcher.requests.count, firstRequestCount,
                       "within the day, the sponsor's site is left alone")

        await client.refreshIfStale(
            party: party, now: now.addingTimeInterval(60), force: true)
        XCTAssertGreaterThan(fetcher.requests.count, firstRequestCount,
                             "Refresh is the operator's override")
    }

    func testRosterPageWithoutALinkFailsAndKeepsTheCache() async throws {
        scriptRosterHappyPath()
        let party = try rosterParty()
        await client.refreshIfStale(party: party, now: now)

        fetcher.getResponses = [
            ("sponsor.test", 200, Data("<html><p>redesigned</p></html>".utf8)),
        ]
        await client.refreshIfStale(
            party: party, now: now.addingTimeInterval(60), force: true)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("no longer links a roster"), message)
        XCTAssertNotNil(store.loadCached(partyID: "rp"),
                        "the cached roster stays in service")
    }

    /// Google answers a permissions problem with an HTML page at status 200 —
    /// the lookalike must not install as an empty roster.
    func testRosterSheetAnsweringHTMLFailsLoudly() async throws {
        fetcher.getResponses = [
            ("sponsor.test", 200, Data(rosterPageHTML.utf8)),
            ("SHEETID123/export?format=csv", 200,
             Data("<!DOCTYPE html><html>sign in</html>".utf8)),
        ]
        await client.refreshIfStale(party: try rosterParty(), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("refused its CSV export"), message)
        XCTAssertNil(store.loadCached(partyID: "rp"))
    }

    /// A plain-HTTP page URL is upgraded before the request: ATS refuses
    /// HTTP outright, so an un-upgraded URL fails with a policy message
    /// naming no site — which is exactly what shipped on 2026-08-04.
    func testAPlainHTTPPageURLIsUpgradedBeforeTheRequest() async throws {
        XCTAssertEqual(CallHistoryClient.secured("http://example.test/x"),
                       "https://example.test/x")
        XCTAssertEqual(CallHistoryClient.secured("https://example.test/x"),
                       "https://example.test/x", "already secure, untouched")

        let json = """
        {"schemaVersion":1,"id":"rp","name":"RP","cabrilloContest":"RP","homeState":"NA",
        "countyAbbrLength":2,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode","hasHomeRegion":false,
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[],
        "callHistory":{"kind":"w2ljRosterPage","pageURL":"http://sponsor.test/skeeter.html",
        "filePrefix":"SKEETER","token":"SKEETER ROSTER"}}
        """
        scriptRosterHappyPath()
        await client.refreshIfStale(
            party: try PartyCatalog.decode(Data(json.utf8)), now: now)

        XCTAssertEqual(published.map(\.records), [2])
        XCTAssertTrue(
            fetcher.requests.contains { $0.hasPrefix("GET https://sponsor.test") },
            "\(fetcher.requests)")
        XCTAssertFalse(fetcher.requests.contains { $0.contains("GET http://") })
    }

    func testRosterSheetWithAForeignShapeFailsLoudly() async throws {
        fetcher.getResponses = [
            ("sponsor.test", 200, Data(rosterPageHTML.utf8)),
            ("SHEETID123/export?format=csv", 200, Data("Call,Number\nW2LJ,13".utf8)),
        ]
        await client.refreshIfStale(party: try rosterParty(), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("changed shape"), message)
    }

    // MARK: The stable-report kind (ARS Flight of the Bumblebees)

    /// A synthetic party carrying the report kind — one GET and no
    /// discovery hop, the whole difference from the sheet kind above.
    private func reportParty(
        pageURL: String = "https://sponsor.test/FOBB/Process_Get_All_By_Number.php"
    ) throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"rr","name":"RR","cabrilloContest":"RR","homeState":"NA",
        "countyAbbrLength":2,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode","hasHomeRegion":false,
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[],
        "callHistory":{"kind":"arsFobbRoster","pageURL":"\(pageURL)",
        "filePrefix":"FOBB","token":"FOBB ROSTER"}}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    /// The report's own markup: headings wrapped in <font>, data cells bare.
    private let reportHTML = """
    <table><tr>
    <td> <font face="Arial">BB</font> </td>
    <td> <font face="Arial">Callsign</font> </td>
    <td> <font face="Arial">Name</font> </td>
    <td> <font face="Arial">SPC</font> </td>
    <td> <font face="Arial">Expected Location</font> </td>
    </tr><tr>
    <td>7</td><td>W4KAC</td><td>Ken</td><td>NC</td><td>Family farm</td>
    </tr><tr>
    <td>23</td><td>N7CQR</td><td>Dan</td><td>OR</td><td>A hilltop</td>
    </tr></table>
    """

    func testFOBBRosterInstallsFromTheReportPage() async throws {
        fetcher.getResponses = [("sponsor.test", 200, Data(reportHTML.utf8))]
        await client.refreshIfStale(party: try reportParty(), now: now)

        XCTAssertEqual(published.map(\.partyID), ["rr"])
        // Two bees, each under its bare call and its /BB form.
        XCTAssertEqual(published.map(\.records), [4])
        guard case .ready(let id, let revision, let records) = client.status else {
            return XCTFail("expected ready, got \(client.status)")
        }
        XCTAssertEqual(id, "rr")
        XCTAssertEqual(records, 4)
        XCTAssertTrue(revision.hasPrefix("roster "), revision)

        let cached = try XCTUnwrap(store.loadCached(partyID: "rr"))
        XCTAssertEqual(cached.parsed.entry(for: "W4KAC")?.locations, ["7", "NC"])
        XCTAssertEqual(cached.parsed.entry(for: "W4KAC/BB")?.locations, ["7", "NC"])
        XCTAssertTrue(
            cached.parsed.tokens.contains(CallHistorySource.normalized("FOBB ROSTER")))

        // One request, straight to the report — there is nothing to discover.
        XCTAssertEqual(fetcher.requests.count, 1, "\(fetcher.requests)")
    }

    func testFOBBRosterKeepsTheCacheOnHTTPFailure() async throws {
        fetcher.getResponses = [("sponsor.test", 200, Data(reportHTML.utf8))]
        let party = try reportParty()
        await client.refreshIfStale(party: party, now: now)

        fetcher.getResponses = [("sponsor.test", 503, Data())]
        await client.refreshIfStale(
            party: party, now: now.addingTimeInterval(60), force: true)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("answered 503"), message)
        XCTAssertNotNil(store.loadCached(partyID: "rr"),
                        "the cached roster stays in service")
    }

    func testFOBBRosterRefusesDriftedMarkup() async throws {
        fetcher.getResponses = [
            ("sponsor.test", 200, Data("<html><p>maintenance</p></html>".utf8)),
        ]
        await client.refreshIfStale(party: try reportParty(), now: now)

        guard case .failed(let message) = client.status else {
            return XCTFail("expected a failure, got \(client.status)")
        }
        XCTAssertTrue(message.contains("changed shape"), message)
        XCTAssertNil(store.loadCached(partyID: "rr"), "nothing was installed")
    }

    /// Numbers issue until the event, so there is no revision to compare
    /// against — the daily throttle alone paces it, and Refresh overrides.
    func testFOBBRosterHoldsToTheThrottleAndForceBypassesIt() async throws {
        fetcher.getResponses = [("sponsor.test", 200, Data(reportHTML.utf8))]
        let party = try reportParty()
        await client.refreshIfStale(party: party, now: now)
        XCTAssertEqual(fetcher.requests.count, 1)

        await client.refreshIfStale(party: party, now: now.addingTimeInterval(3600))
        XCTAssertEqual(fetcher.requests.count, 1,
                       "within the day, the sponsor's site is left alone")

        await client.refreshIfStale(party: party, now: now.addingTimeInterval(90_000))
        XCTAssertEqual(fetcher.requests.count, 2,
                       "a day later it re-downloads, with nothing to compare")

        await client.refreshIfStale(
            party: party, now: now.addingTimeInterval(90_060), force: true)
        XCTAssertEqual(fetcher.requests.count, 3, "Refresh is the operator's override")
    }

    /// A plain-HTTP page URL is upgraded here too — ATS refuses HTTP
    /// outright, and the sponsor writes its own links however it likes.
    func testFOBBRosterUpgradesAPlainHTTPPageURL() async throws {
        fetcher.getResponses = [("sponsor.test", 200, Data(reportHTML.utf8))]
        await client.refreshIfStale(
            party: try reportParty(pageURL: "http://sponsor.test/FOBB/report.php"),
            now: now)

        XCTAssertEqual(published.map(\.records), [4])
        XCTAssertTrue(
            fetcher.requests.contains { $0.hasPrefix("GET https://sponsor.test") },
            "\(fetcher.requests)")
        XCTAssertFalse(fetcher.requests.contains { $0.contains("GET http://") })
    }
}
