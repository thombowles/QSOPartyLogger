import XCTest
@testable import QSOPartyLogger

/// The parser against real captured SWPC payloads, and the modifier table
/// pinned bucket by bucket.
///
/// Both fixtures are the live products as they were served on 2026-08-09,
/// captured whole — headers, byte counts and the reasoning behind every bucket
/// edge are in `docs/research/space_weather_sources.md`.
final class SpaceWeatherTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"),
                                "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    private func flux() throws -> Data { try fixture("swpc_f107_cm_flux_2026-08-09") }
    private func planetaryK() throws -> Data { try fixture("swpc_planetary_k_index_2026-08-09") }

    private static func utc(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    // MARK: The real payloads

    /// `flux` arrives as `9.400000000000000e+001`. Read as a string it matches
    /// nothing; read as a Double it is 94 sfu.
    func testFluxParsesExponentialNotationFromTheLiveCapture() throws {
        let parsed = try XCTUnwrap(SpaceWeather.parseFlux(try flux()))
        XCTAssertEqual(parsed.sfi, 94)
        XCTAssertEqual(parsed.observedAt, Self.utc("2026-08-09 17:00:00"))
    }

    /// Kp comes in thirds and under a capital K. An `Int` here would floor
    /// 5.67 to 5 and move it a whole NOAA scale level.
    func testPlanetaryKParsesThirdsFromTheLiveCapture() throws {
        let parsed = try XCTUnwrap(SpaceWeather.parsePlanetaryK(try planetaryK()))
        XCTAssertEqual(parsed.kp, 1.33, accuracy: 0.001)
        XCTAssertEqual(parsed.observedAt, Self.utc("2026-08-09 15:00:00"))
    }

    /// The two captures came off the same server on the same day sorted
    /// **opposite** ways — flux newest-first, Kp oldest-first. Taking either
    /// end of the array would be right for one product and wrong for the
    /// other, which is why both are sorted.
    func testTheTwoProductsAreSortedOppositeWaysAndBothStillGiveTheNewest() throws {
        let fluxRows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try flux()) as? [[String: Any]])
        let kpRows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try planetaryK()) as? [[String: Any]])
        XCTAssertEqual(fluxRows.first?["time_tag"] as? String, "2026-08-09T17:00:00",
                       "the flux capture is newest-first")
        XCTAssertEqual(kpRows.last?["time_tag"] as? String, "2026-08-09T15:00:00",
                       "the Kp capture is oldest-first")

        XCTAssertEqual(try XCTUnwrap(SpaceWeather.parseFlux(try flux())).observedAt,
                       Self.utc("2026-08-09 17:00:00"))
        XCTAssertEqual(try XCTUnwrap(SpaceWeather.parsePlanetaryK(try planetaryK())).observedAt,
                       Self.utc("2026-08-09 15:00:00"))
    }

    /// The combined reading is stamped with the **older** observation, so "as
    /// of" can only understate its freshness.
    func testReadingTakesTheOlderOfTheTwoObservationTimes() throws {
        let reading = try XCTUnwrap(
            SpaceWeather.reading(flux: try flux(), planetaryK: try planetaryK()))
        XCTAssertEqual(reading.sfi, 94)
        XCTAssertEqual(try XCTUnwrap(reading.kp), 1.33, accuracy: 0.001)
        XCTAssertEqual(reading.observedAt, Self.utc("2026-08-09 15:00:00"))
    }

    /// One product down is not a reason to discard the other.
    func testOneProductAloneStillMakesAReading() throws {
        let kpOnly = try XCTUnwrap(SpaceWeather.reading(flux: nil, planetaryK: try planetaryK()))
        XCTAssertNil(kpOnly.sfi)
        XCTAssertEqual(try XCTUnwrap(kpOnly.kp), 1.33, accuracy: 0.001)

        let fluxOnly = try XCTUnwrap(SpaceWeather.reading(flux: try flux(), planetaryK: nil))
        XCTAssertEqual(fluxOnly.sfi, 94)
        XCTAssertNil(fluxOnly.kp)
    }

    // MARK: Malformed and empty bodies

    func testMalformedAndEmptyBodiesParseToNothing() {
        let bad: [Data] = [
            Data(),
            Data("not json at all".utf8),
            Data("{}".utf8),
            Data("[]".utf8),
            // The array-of-arrays shape several *other* SWPC products use.
            Data(#"[["time_tag","Kp"],["2026-08-09T15:00:00","1.33"]]"#.utf8),
            // Right shape, unreadable stamp.
            Data(#"[{"time_tag":"yesterday","Kp":4.0}]"#.utf8),
            // Right shape, missing the value.
            Data(#"[{"time_tag":"2026-08-09T15:00:00"}]"#.utf8),
        ]
        for data in bad {
            XCTAssertNil(SpaceWeather.parseFlux(data))
            XCTAssertNil(SpaceWeather.parsePlanetaryK(data))
            XCTAssertNil(SpaceWeather.reading(flux: data, planetaryK: data))
        }
    }

    /// A body with one good row among broken ones still yields that row —
    /// a single malformed entry must not take the whole strand off the air.
    func testOneGoodRowSurvivesBrokenNeighbours() throws {
        let data = Data("""
        [{"time_tag":"nonsense","Kp":9.0},
         {"time_tag":"2026-08-09T12:00:00","Kp":4.33},
         {"time_tag":"2026-08-09T09:00:00"}]
        """.utf8)
        let parsed = try XCTUnwrap(SpaceWeather.parsePlanetaryK(data))
        XCTAssertEqual(parsed.kp, 4.33, accuracy: 0.001)
        XCTAssertEqual(parsed.observedAt, Self.utc("2026-08-09 12:00:00"))
    }

    // MARK: The modifier table

    private let now = SpaceWeatherTests.utc("2026-08-09 18:00:00")

    private func reading(sfi: Int? = nil, kp: Double? = nil, ageHours: Double = 1) -> SpaceWeather {
        SpaceWeather(sfi: sfi, kp: kp,
                     observedAt: now.addingTimeInterval(-ageHours * 3600))
    }

    /// Quiet sun, quiet field: every band untouched. This is the commonest
    /// state and the one where the advisor must read exactly as it would with
    /// no network at all.
    func testAQuietReadingIsIdentityOnEveryBand() {
        let quiet = reading(sfi: 120, kp: 2.0)
        for band in Band.allCases {
            XCTAssertEqual(quiet.modifier(band: band, now: now), 1.0, accuracy: 0.0001,
                           "\(band) should be untouched")
        }
    }

    /// NOAA draws G1 at Kp 5 and G2 at Kp 6, and absorption goes as the
    /// inverse square of frequency — so a disturbance takes the low bands
    /// first and the high bands last.
    func testKpBucketsDampLowBandsHardestAndInOrder() {
        let g1 = reading(kp: 5.0)
        XCTAssertEqual(g1.modifier(band: .m80, now: now), 0.90, accuracy: 0.0001)
        XCTAssertEqual(g1.modifier(band: .m20, now: now), 0.95, accuracy: 0.0001)
        XCTAssertEqual(g1.modifier(band: .m10, now: now), 1.00, accuracy: 0.0001)

        let g2 = reading(kp: 6.0)
        XCTAssertEqual(g2.modifier(band: .m80, now: now), 0.75, accuracy: 0.0001)
        XCTAssertEqual(g2.modifier(band: .m20, now: now), 0.85, accuracy: 0.0001)
        XCTAssertEqual(g2.modifier(band: .m10, now: now), 0.95, accuracy: 0.0001)

        // Just below G1 nothing moves at all — the edge is NOAA's, not ours.
        let belowG1 = reading(kp: 4.67)
        for band in Band.allCases {
            XCTAssertEqual(belowG1.modifier(band: band, now: now), 1.0, accuracy: 0.0001)
        }
    }

    /// The high bands follow the F2 MUF, so the flux moves them and leaves the
    /// low bands alone.
    func testSfiBucketsMoveTheHighBandsOnly() {
        let low = reading(sfi: 70)
        XCTAssertEqual(low.modifier(band: .m10, now: now), 0.85, accuracy: 0.0001)
        XCTAssertEqual(low.modifier(band: .m20, now: now), 1.00, accuracy: 0.0001)
        XCTAssertEqual(low.modifier(band: .m80, now: now), 1.00, accuracy: 0.0001)

        let high = reading(sfi: 180)
        XCTAssertEqual(high.modifier(band: .m15, now: now), 1.15, accuracy: 0.0001)
        XCTAssertEqual(high.modifier(band: .m20, now: now), 1.05, accuracy: 0.0001)
        XCTAssertEqual(high.modifier(band: .m17, now: now), 1.05, accuracy: 0.0001)
        // 30 m is in the Kp middle group but takes no flux lift — it is not
        // one of the MUF-limited bands the banked source argues about.
        XCTAssertEqual(high.modifier(band: .m30, now: now), 1.00, accuracy: 0.0001)
        XCTAssertEqual(high.modifier(band: .m40, now: now), 1.00, accuracy: 0.0001)
    }

    /// Both indices at once compose by multiplication — a storm under a high
    /// flux is a real combination and neither term may swallow the other.
    func testTheTwoModifiersCompose() {
        let stormyAndActive = reading(sfi: 180, kp: 6.0)
        XCTAssertEqual(stormyAndActive.modifier(band: .m10, now: now),
                       0.95 * 1.15, accuracy: 0.0001)
    }

    /// 6 m and above take no claim from either index, the same silence the
    /// daypart table keeps about them.
    func testVHFAndAboveAreNeverModified() {
        let extreme = reading(sfi: 300, kp: 9.0)
        for band in [Band.m6, .m2, .cm125, .cm70] {
            XCTAssertEqual(extreme.modifier(band: band, now: now), 1.0, accuracy: 0.0001)
        }
    }

    // MARK: Stale and absent reduce to identity

    func testAReadingOlderThanTheStaleWindowStopsModifyingAnything() {
        let stormy = reading(kp: 8.0, ageHours: 5.9)
        XCTAssertEqual(stormy.modifier(band: .m80, now: now), 0.75, accuracy: 0.0001)

        let old = reading(kp: 8.0, ageHours: 6.1)
        XCTAssertTrue(old.isStale(now: now))
        for band in Band.allCases {
            XCTAssertEqual(old.modifier(band: band, now: now), 1.0, accuracy: 0.0001,
                           "a stale reading must weigh nothing")
        }
    }

    /// A clock-skewed stamp from the future is not evidence either.
    func testAFutureObservationIsTreatedAsStale() {
        let ahead = SpaceWeather(sfi: 300, kp: 8.0, observedAt: now.addingTimeInterval(4 * 3600))
        XCTAssertTrue(ahead.isStale(now: now))
        XCTAssertEqual(ahead.modifier(band: .m80, now: now), 1.0, accuracy: 0.0001)
    }

    func testAReadingWithNoValuesModifiesNothing() {
        let empty = SpaceWeather(sfi: nil, kp: nil, observedAt: now)
        for band in Band.allCases {
            XCTAssertEqual(empty.modifier(band: band, now: now), 1.0, accuracy: 0.0001)
        }
        XCTAssertNil(empty.summary(now: now))
    }

    // MARK: The copy

    func testSummaryAlwaysNamesTheObservationTime() {
        let fresh = SpaceWeather(sfi: 128, kp: 4.0,
                                 observedAt: Self.utc("2026-08-09 15:00:00"))
        XCTAssertEqual(fresh.summary(now: now), "Kp 4.0 · SFI 128, observed 1500Z")

        // Kp reads in thirds, and a bare "4" beside a "3.67" would hide that.
        let thirds = SpaceWeather(sfi: nil, kp: 3.67,
                                  observedAt: Self.utc("2026-08-09 15:00:00"))
        XCTAssertEqual(thirds.summary(now: now), "Kp 3.7, observed 1500Z")

        // Stale says so in the same breath as the figure, rather than being
        // silently dropped from a line the operator is reading for evidence.
        let old = SpaceWeather(sfi: 200, kp: nil, observedAt: Self.utc("2026-08-09 06:00:00"))
        XCTAssertEqual(old.summary(now: now),
                       "SFI 200, observed 0600Z — too old to weigh, ignoring it")
    }

    // MARK: Round trip

    /// The disk cache is JSON, so the model has to survive it unchanged.
    func testAReadingRoundTripsThroughItsCacheEncoding() throws {
        let original = SpaceWeather(sfi: 94, kp: 1.33,
                                    observedAt: Self.utc("2026-08-09 15:00:00"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(
            try decoder.decode(SpaceWeather.self, from: try encoder.encode(original)),
            original
        )
    }
}
