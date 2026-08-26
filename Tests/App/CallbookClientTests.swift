import XCTest
@testable import QSOPartyLogger

/// The lookup client: sessions per each service's banked contract
/// (docs/research/callbook/SOURCES.md), primary then fallback, cache first.
/// Tests inject a scripted fetcher and an in-memory credential store —
/// never the network, never the real Keychain.
@MainActor
final class CallbookClientTests: XCTestCase {

    final class ScriptedFetcher: CallbookFetching, @unchecked Sendable {
        var responses: [String]
        private(set) var requested: [URL] = []
        init(_ responses: [String]) { self.responses = responses }
        func get(_ url: URL) async throws -> Data {
            requested.append(url)
            guard !responses.isEmpty else { throw URLError(.badServerResponse) }
            return Data(responses.removeFirst().utf8)
        }
    }

    private let qrzLoginOK = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Key>KEY1</Key></Session></QRZDatabase>
        """
    private let qrzW1AW = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Callsign><call>W1AW</call><fname>ARRL</fname><state>CT</state>\
        <grid>FN31pr</grid></Callsign>
        <Session><Key>KEY1</Key></Session></QRZDatabase>
        """
    private let qrzTimeout = """
        <QRZDatabase xmlns="http://xmldata.qrz.com">
        <Session><Error>Session Timeout</Error></Session></QRZDatabase>
        """
    private let hamqthLoginOK = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><session_id>SID1</session_id></session></HamQTH>
        """
    private let hamqthW1AW = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <search><callsign>W1AW</callsign><nick>Al</nick><grid>FN31</grid></search></HamQTH>
        """

    private func makeClient(
        fetcher: ScriptedFetcher,
        primary: CallbookService = .qrz,
        qrz: Bool = true, hamqth: Bool = false
    ) -> CallbookClient {
        let credentials = InMemoryCredentialStore()
        credentials.set("pw", service: CallbookService.qrz.keychainService, account: "ke5cw")
        credentials.set("pw", service: CallbookService.hamqth.keychainService, account: "ke5cw")
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return CallbookClient(
            fetcher: fetcher,
            credentials: credentials,
            cache: CallbookCache(directory: cacheDir),
            configuration: { .init(qrzEnabled: qrz, qrzUsername: "ke5cw",
                                   hamqthEnabled: hamqth, hamqthUsername: "ke5cw",
                                   primary: primary) }
        )
    }

    func testLoginOncePerSessionThenLookups() async {
        let fetcher = ScriptedFetcher([qrzLoginOK, qrzW1AW, qrzW1AW])
        let client = makeClient(fetcher: fetcher)
        let first = await client.lookup(call: "W1AW")
        XCTAssertNotNil(first)
        _ = await client.lookup(call: "W1AW2")  // distinct call, same session
        XCTAssertEqual(fetcher.requested.count, 3,
                       "one login, two lookups — never per-lookup logins")
    }

    func testCacheHitFetchesNothing() async {
        let fetcher = ScriptedFetcher([qrzLoginOK, qrzW1AW])
        let client = makeClient(fetcher: fetcher)
        let first = await client.lookup(call: "W1AW")
        XCTAssertEqual(first?.state, "CT")
        let requestsAfterFirst = fetcher.requested.count
        let second = await client.lookup(call: "W1AW")
        XCTAssertEqual(second?.state, "CT")
        XCTAssertEqual(fetcher.requested.count, requestsAfterFirst,
                       "a cached call costs no request")
    }

    func testSessionTimeoutRelogsInExactlyOnce() async {
        let fetcher = ScriptedFetcher([qrzLoginOK, qrzTimeout, qrzLoginOK, qrzW1AW])
        let client = makeClient(fetcher: fetcher)
        let record = await client.lookup(call: "W1AW")
        XCTAssertEqual(record?.call, "W1AW")
        XCTAssertEqual(fetcher.requested.count, 4,
                       "login, expired lookup, re-login, retry")
    }

    func testFallbackToSecondaryOnPrimaryFailure() async {
        // QRZ login fails outright; HamQTH answers.
        let fetcher = ScriptedFetcher(["not xml at all", hamqthLoginOK, hamqthW1AW])
        let client = makeClient(fetcher: fetcher, primary: .qrz, qrz: true, hamqth: true)
        let record = await client.lookup(call: "W1AW")
        XCTAssertEqual(record?.source, .hamqth)
        XCTAssertEqual(record?.name, "Al")
    }

    func testHamQTHPrimaryWinsWhenChosen() async {
        let fetcher = ScriptedFetcher([hamqthLoginOK, hamqthW1AW])
        let client = makeClient(fetcher: fetcher, primary: .hamqth,
                                qrz: true, hamqth: true)
        let record = await client.lookup(call: "W1AW")
        XCTAssertEqual(record?.source, .hamqth)
        XCTAssertEqual(fetcher.requested.count, 2, "QRZ never asked")
    }

    func testNothingConfiguredLooksUpNothing() async {
        let fetcher = ScriptedFetcher([])
        let client = makeClient(fetcher: fetcher, qrz: false, hamqth: false)
        let record = await client.lookup(call: "W1AW")
        XCTAssertNil(record)
        XCTAssertTrue(fetcher.requested.isEmpty)
    }

    func testPlausibleCallGate() {
        XCTAssertFalse(CallbookClient.isPlausibleCall("W"))
        XCTAssertFalse(CallbookClient.isPlausibleCall("QRZ"))
        XCTAssertTrue(CallbookClient.isPlausibleCall("W1A"))
        XCTAssertTrue(CallbookClient.isPlausibleCall("KE5CW"))
        XCTAssertTrue(CallbookClient.isPlausibleCall("EA8/W1AW"))
    }
}
