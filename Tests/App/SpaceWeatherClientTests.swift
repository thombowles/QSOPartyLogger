import XCTest
@testable import QSOPartyLogger

/// The client's decision-making, on scripted server answers. Never touches the
/// network (constitution Article 5) and never writes outside a temp folder.
@MainActor
final class SpaceWeatherClientTests: XCTestCase {

    /// A scripted SWPC. Answers per URL, records what was asked, and can fail
    /// one product while serving the other.
    final class Fetcher: SpaceWeatherFetching, @unchecked Sendable {
        var bodies: [URL: Data] = [:]
        var errors: [URL: Error] = [:]
        var requests: [URL] = []

        func get(_ url: URL) async throws -> Data {
            requests.append(url)
            if let error = errors[url] { throw error }
            guard let body = bodies[url] else { throw Failure.notScripted }
            return body
        }

        enum Failure: LocalizedError {
            case notScripted
            case offline
            var errorDescription: String? {
                switch self {
                case .notScripted: "no scripted answer"
                case .offline: "the network is unreachable"
                }
            }
        }
    }

    private var cache: URL!

    override func setUpWithError() throws {
        cache = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spaceweather-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cache)
    }

    private static func utc(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    private let now = SpaceWeatherClientTests.utc("2026-08-09 18:00:00")

    private func scripted(sfi: Int = 128, kp: Double = 4.0, at stamp: String) -> Fetcher {
        let fetcher = Fetcher()
        fetcher.bodies[SpaceWeatherClient.fluxURL] = Data(
            #"[{"time_tag":"\#(stamp)","frequency":2800,"flux":\#(Double(sfi))e+000}]"#.utf8)
        fetcher.bodies[SpaceWeatherClient.planetaryKURL] = Data(
            #"[{"time_tag":"\#(stamp)","Kp":\#(kp),"a_running":27,"station_count":8}]"#.utf8)
        return fetcher
    }

    // MARK: The everyday case

    func testASuccessfulRefreshStoresTheReadingAndCachesIt() async {
        let fetcher = scripted(at: "2026-08-09T15:00:00")
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refresh(now: now)

        XCTAssertEqual(client.reading?.sfi, 128)
        XCTAssertEqual(client.reading?.kp, 4.0)
        XCTAssertEqual(client.reading?.observedAt, Self.utc("2026-08-09 15:00:00"))
        XCTAssertNil(client.lastError)
        XCTAssertEqual(client.status, .current(client.reading!))
        XCTAssertEqual(SpaceWeatherStore.load(at: cache)?.reading, client.reading)
        XCTAssertEqual(SpaceWeatherStore.load(at: cache)?.checkedAt, now)
    }

    /// The cache is what makes a contest that opens offline start with
    /// something rather than nothing.
    func testANewClientStartsFromTheDiskCache() async {
        let stored = SpaceWeather(sfi: 94, kp: 1.33, observedAt: Self.utc("2026-08-09 15:00:00"))
        SpaceWeatherStore.save(.init(reading: stored, checkedAt: now), to: cache)

        let fetcher = Fetcher()  // scripted with nothing: every request throws
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        XCTAssertEqual(client.reading, stored)
        XCTAssertTrue(fetcher.requests.isEmpty, "construction must not make a request")
    }

    // MARK: The throttle

    func testASecondRefreshInsideTheHourMakesNoRequest() async {
        let fetcher = scripted(at: "2026-08-09T15:00:00")
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refreshIfStale(now: now)
        XCTAssertEqual(fetcher.requests.count, 2, "one request per product")

        await client.refreshIfStale(now: now.addingTimeInterval(59 * 60))
        XCTAssertEqual(fetcher.requests.count, 2, "still inside the hour")

        await client.refreshIfStale(now: now.addingTimeInterval(61 * 60))
        XCTAssertEqual(fetcher.requests.count, 4)
    }

    func testForceOverridesTheThrottle() async {
        let fetcher = scripted(at: "2026-08-09T15:00:00")
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refreshIfStale(now: now)
        await client.refreshIfStale(now: now, force: true)
        XCTAssertEqual(fetcher.requests.count, 4)
    }

    // MARK: Failure is quiet, and never worse than no fetch

    func testAFailedRefreshKeepsTheLastGoodReading() async {
        let fetcher = scripted(at: "2026-08-09T15:00:00")
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refresh(now: now)
        let good = client.reading

        fetcher.errors[SpaceWeatherClient.fluxURL] = Fetcher.Failure.offline
        fetcher.errors[SpaceWeatherClient.planetaryKURL] = Fetcher.Failure.offline
        await client.refresh(now: now.addingTimeInterval(3600))

        XCTAssertEqual(client.reading, good, "a failed fetch must not discard what works")
        XCTAssertEqual(client.status, .failed("no usable reading from SWPC"))
        XCTAssertNotNil(client.lastError)
        XCTAssertEqual(SpaceWeatherStore.load(at: cache)?.reading, good)
    }

    /// One endpoint down still yields the other's value — the products are
    /// fetched independently for exactly this case.
    func testOneProductFailingStillProducesAReading() async {
        let fetcher = scripted(at: "2026-08-09T15:00:00")
        fetcher.errors[SpaceWeatherClient.fluxURL] = Fetcher.Failure.offline
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refresh(now: now)

        XCTAssertNil(client.reading?.sfi)
        XCTAssertEqual(client.reading?.kp, 4.0)
        XCTAssertEqual(client.lastError, "the network is unreachable",
                       "the failure is still recorded")
    }

    /// Garbage that parses as JSON but carries nothing usable is a failure,
    /// not a reading of nil values.
    func testAnUnusableBodyIsAFailureRatherThanAnEmptyReading() async {
        let fetcher = Fetcher()
        fetcher.bodies[SpaceWeatherClient.fluxURL] = Data("[]".utf8)
        fetcher.bodies[SpaceWeatherClient.planetaryKURL] = Data("[]".utf8)
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refresh(now: now)

        XCTAssertNil(client.reading)
        XCTAssertEqual(client.status, .failed("no usable reading from SWPC"))
        XCTAssertNil(SpaceWeatherStore.load(at: cache), "nothing unusable reaches the cache")
    }

    /// Every failure has to leave a trace somewhere the operator can find it.
    func testFailuresReachTheConsole() async {
        let fetcher = Fetcher()
        fetcher.errors[SpaceWeatherClient.fluxURL] = Fetcher.Failure.offline
        fetcher.errors[SpaceWeatherClient.planetaryKURL] = Fetcher.Failure.offline
        let client = SpaceWeatherClient(fetcher: fetcher, cacheURL: cache)
        await client.refresh(now: now)
        XCTAssertTrue(client.console.contains { $0.contains("the network is unreachable") })
    }

    /// The two URLs are the ones banked in the research doc. A silent edit to
    /// either would take the strand off the air with no other symptom.
    func testTheEndpointsAreTheBankedOnes() {
        XCTAssertEqual(SpaceWeatherClient.fluxURL.absoluteString,
                       "https://services.swpc.noaa.gov/json/f107_cm_flux.json")
        XCTAssertEqual(SpaceWeatherClient.planetaryKURL.absoluteString,
                       "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json")
    }
}
