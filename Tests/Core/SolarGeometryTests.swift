import XCTest
@testable import QSOPartyLogger

/// The NOAA transcription, pinned against an independent authority.
///
/// Every rise/set figure below came from the US Naval Observatory's
/// Astronomical Applications API (v4.0.1, queried 2026-08-09 with `tz=0`) —
/// different institution, different code, same sky. If the transcription of
/// NOAA's spreadsheet formulas were wrong, these would not agree.
/// Provenance and the full comparison table: `docs/research/solar_geometry_sources.md`.
final class SolarGeometryTests: XCTestCase {

    private static func utc(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    /// W1AW, Newington CT — the same anchor `MaidenheadTests` uses.
    private let w1awLat = 41.714775
    private let w1awLon = -72.727260
    /// EM13, north Texas: KE5CW's own square.
    private let em13Lat = 33.5
    private let em13Lon = -97.0

    // MARK: Rise, transit, set against USNO

    func testSunriseSunsetMatchesUSNOAtFourPlacesAndDates() throws {
        // (latitude, longitude, UTC day, USNO rise, USNO transit, USNO set)
        let cases: [(Double, Double, String, String, String, String)] = [
            (w1awLat, w1awLon, "2026-06-21",
             "2026-06-21 09:16:00", "2026-06-21 16:53:00", "2026-06-22 00:29:00"),
            (w1awLat, w1awLon, "2026-12-21",
             "2026-12-21 12:15:00", "2026-12-21 16:49:00", "2026-12-21 21:23:00"),
            (em13Lat, em13Lon, "2026-08-09",
             "2026-08-09 11:46:00", "2026-08-09 18:33:00", "2026-08-10 01:21:00"),
            (0, 0, "2026-03-20",
             "2026-03-20 06:04:00", "2026-03-20 12:07:00", "2026-03-20 18:11:00"),
        ]
        for (lat, lon, day, rise, transit, set) in cases {
            let times = try XCTUnwrap(
                SolarGeometry.sunriseSunset(
                    latitude: lat, longitude: lon, date: Self.utc("\(day) 00:00:00")
                ),
                "no crossings at \(lat),\(lon) on \(day)"
            )
            // USNO publishes to the minute, so a minute is the whole tolerance
            // this comparison can carry.
            XCTAssertEqual(times.sunrise.timeIntervalSince(Self.utc(rise)), 0, accuracy: 60,
                           "sunrise \(day)")
            XCTAssertEqual(times.solarNoon.timeIntervalSince(Self.utc(transit)), 0, accuracy: 60,
                           "solar noon \(day)")
            XCTAssertEqual(times.sunset.timeIntervalSince(Self.utc(set)), 0, accuracy: 60,
                           "sunset \(day)")
        }
    }

    /// The sunset returned is the one that **follows** the sunrise, which in
    /// the Americas lands on the next UTC day. An almanac's own convention —
    /// whatever set falls inside the requested UTC day — would hand back the
    /// previous evening's, and the advisor would announce a sunset that
    /// happened twenty hours ago.
    func testSunsetFollowsSunriseRatherThanSharingItsUTCDay() throws {
        let times = try XCTUnwrap(SolarGeometry.sunriseSunset(
            latitude: w1awLat, longitude: w1awLon, date: Self.utc("2026-06-21 00:00:00")
        ))
        XCTAssertGreaterThan(times.sunset, times.sunrise)
        XCTAssertGreaterThan(times.sunset, Self.utc("2026-06-22 00:00:00"))
    }

    /// Any instant inside a UTC day answers for that whole day.
    func testAnyInstantInTheDayGivesTheSameCrossings() throws {
        let early = try XCTUnwrap(SolarGeometry.sunriseSunset(
            latitude: em13Lat, longitude: em13Lon, date: Self.utc("2026-08-09 00:00:01")))
        let late = try XCTUnwrap(SolarGeometry.sunriseSunset(
            latitude: em13Lat, longitude: em13Lon, date: Self.utc("2026-08-09 23:59:59")))
        XCTAssertEqual(early, late)
    }

    // MARK: Elevation

    func testElevationAtSolarNoonAndMidnight() {
        // Newington at its own solar noon on the June solstice: 90 − latitude
        // + declination, and the arithmetic agrees — 90 − 41.71 + 23.44 ≈ 71.7.
        XCTAssertEqual(
            SolarGeometry.elevation(latitude: w1awLat, longitude: w1awLon,
                                    date: Self.utc("2026-06-21 16:52:46")),
            71.73, accuracy: 0.5
        )
        // Twelve hours away, the sun is as far below the horizon as it gets.
        XCTAssertEqual(
            SolarGeometry.elevation(latitude: w1awLat, longitude: w1awLon,
                                    date: Self.utc("2026-06-21 04:52:46")),
            -24.83, accuracy: 0.5
        )
        // The equator at the March equinox: the sun passes very nearly
        // overhead, and the zenith angle has nowhere left to go.
        XCTAssertEqual(
            SolarGeometry.elevation(latitude: 0, longitude: 0,
                                    date: Self.utc("2026-03-20 12:07:25")),
            89.96, accuracy: 0.5
        )
        XCTAssertEqual(
            SolarGeometry.elevation(latitude: em13Lat, longitude: em13Lon,
                                    date: Self.utc("2026-08-09 18:00:00")),
            70.66, accuracy: 0.5
        )
    }

    /// Elevation and the computed crossings have to be the same fact. If they
    /// drifted apart, "sunset was 0112Z" would print while the sun still read
    /// as up.
    func testElevationCrossesZeroAtTheComputedCrossings() throws {
        let times = try XCTUnwrap(SolarGeometry.sunriseSunset(
            latitude: em13Lat, longitude: em13Lon, date: Self.utc("2026-08-09 00:00:00")))
        for crossing in [times.sunrise, times.sunset] {
            // NOAA's 90.833° zenith puts the crossing a little before the
            // geometric one, so the corrected elevation there is a shade
            // positive rather than exactly zero.
            XCTAssertEqual(
                SolarGeometry.elevation(latitude: em13Lat, longitude: em13Lon, date: crossing),
                0, accuracy: 0.6
            )
        }
        XCTAssertGreaterThan(
            SolarGeometry.elevation(latitude: em13Lat, longitude: em13Lon,
                                    date: times.sunrise.addingTimeInterval(3600)),
            0
        )
        XCTAssertLessThan(
            SolarGeometry.elevation(latitude: em13Lat, longitude: em13Lon,
                                    date: times.sunset.addingTimeInterval(3600)),
            0
        )
    }

    // MARK: Declination — the equinox and solstice checks

    func testDeclinationAtSolsticesAndEquinox() {
        XCTAssertEqual(SolarGeometry.declination(date: Self.utc("2026-06-21 12:00:00")),
                       23.44, accuracy: 0.1)
        XCTAssertEqual(SolarGeometry.declination(date: Self.utc("2026-12-21 12:00:00")),
                       -23.44, accuracy: 0.1)
        // Within a day of the March equinox the sun is on the celestial
        // equator, so the declination is a rounding error away from zero.
        XCTAssertEqual(SolarGeometry.declination(date: Self.utc("2026-03-20 12:00:00")),
                       0, accuracy: 0.5)
    }

    /// The equation of time stays inside its known ±17-minute envelope all
    /// year — the one cheap check that catches a mistyped coefficient in a
    /// term that has no separate published value to pin.
    func testEquationOfTimeStaysInsideItsAnnualEnvelope() {
        var day = Self.utc("2026-01-01 12:00:00")
        var extremes = (low: Double.greatestFiniteMagnitude, high: -Double.greatestFiniteMagnitude)
        for _ in 0..<365 {
            let value = SolarGeometry.equationOfTime(date: day)
            extremes.low = min(extremes.low, value)
            extremes.high = max(extremes.high, value)
            day = day.addingTimeInterval(86400)
        }
        XCTAssertEqual(extremes.low, -14.2, accuracy: 1.5)
        XCTAssertEqual(extremes.high, 16.4, accuracy: 1.5)
    }

    // MARK: Polar cases do not trap

    func testPolarDayAndPolarNightHaveNoCrossings() {
        // Svalbard: midnight sun in June, polar night in December.
        XCTAssertNil(SolarGeometry.sunriseSunset(
            latitude: 78, longitude: 15, date: Self.utc("2026-06-21 00:00:00")))
        XCTAssertNil(SolarGeometry.sunriseSunset(
            latitude: 78, longitude: 15, date: Self.utc("2026-12-21 00:00:00")))
    }

    /// With no crossing to be near, the daypart still answers — from which
    /// side of the horizon the sun is on — and nothing divides by a `nil`.
    func testDaypartInsideThePolarCirclesFallsBackToTheHorizon() {
        XCTAssertEqual(
            SolarGeometry.daypart(latitude: 78, longitude: 15,
                                  date: Self.utc("2026-06-21 02:00:00")),
            .day
        )
        XCTAssertEqual(
            SolarGeometry.daypart(latitude: 78, longitude: 15,
                                  date: Self.utc("2026-12-21 12:00:00")),
            .night
        )
    }

    func testExtremeCoordinatesReturnFiniteElevations() {
        for (lat, lon) in [(90.0, 0.0), (-90.0, 0.0), (0.0, 180.0), (0.0, -180.0)] {
            let value = SolarGeometry.elevation(
                latitude: lat, longitude: lon, date: Self.utc("2026-08-09 12:00:00"))
            XCTAssertFalse(value.isNaN, "NaN elevation at \(lat),\(lon)")
            XCTAssertTrue((-91...91).contains(value), "\(value)° at \(lat),\(lon)")
        }
    }

    // MARK: Daypart

    func testDaypartAcrossASingleEveningInEM13() throws {
        let times = try XCTUnwrap(SolarGeometry.sunriseSunset(
            latitude: em13Lat, longitude: em13Lon, date: Self.utc("2026-08-09 00:00:00")))

        func daypart(_ offset: TimeInterval) -> SolarGeometry.Daypart {
            SolarGeometry.daypart(latitude: em13Lat, longitude: em13Lon,
                                  date: times.sunset.addingTimeInterval(offset))
        }
        XCTAssertEqual(daypart(-4 * 3600), .day)
        // The window is ±45 minutes, so an hour out is still day and half an
        // hour out is already gray line.
        XCTAssertEqual(daypart(-60 * 60), .day)
        XCTAssertEqual(daypart(-30 * 60), .grayLine)
        XCTAssertEqual(daypart(0), .grayLine)
        XCTAssertEqual(daypart(30 * 60), .grayLine)
        XCTAssertEqual(daypart(90 * 60), .night)
        XCTAssertEqual(daypart(4 * 3600), .night)
    }

    /// The gray line around a crossing that falls on the far side of midnight
    /// UTC. Searching only the current UTC day would miss it and call an
    /// operator's sunset "night" — which is exactly the moment the advisory
    /// exists for.
    func testGrayLineIsFoundAcrossAUTCDayBoundary() {
        // EM13's sunset on 2026-08-09 lands at 2026-08-10 01:21Z.
        XCTAssertEqual(
            SolarGeometry.daypart(latitude: em13Lat, longitude: em13Lon,
                                  date: Self.utc("2026-08-10 01:00:00")),
            .grayLine
        )
        XCTAssertEqual(
            SolarGeometry.daypart(latitude: em13Lat, longitude: em13Lon,
                                  date: Self.utc("2026-08-10 01:50:00")),
            .grayLine
        )
    }

    func testSecondsToNearestCrossingIsSignedAndNearest() throws {
        let times = try XCTUnwrap(SolarGeometry.sunriseSunset(
            latitude: em13Lat, longitude: em13Lon, date: Self.utc("2026-08-09 00:00:00")))
        let before = try XCTUnwrap(SolarGeometry.secondsToNearestCrossing(
            latitude: em13Lat, longitude: em13Lon,
            date: times.sunset.addingTimeInterval(-600)))
        XCTAssertEqual(before, 600, accuracy: 1)
        let after = try XCTUnwrap(SolarGeometry.secondsToNearestCrossing(
            latitude: em13Lat, longitude: em13Lon,
            date: times.sunset.addingTimeInterval(600)))
        XCTAssertEqual(after, -600, accuracy: 1)
    }

    // MARK: The band weight table

    /// The rows that carry the table's whole claim: low bands after dark, high
    /// bands with the sun up, 40 m in between. Pinned so retuning one is a
    /// deliberate edit against `docs/research/band_daypart_sources.md`.
    func testBandWeightsPinTheDaypartClaim() {
        XCTAssertEqual(SolarGeometry.weight(band: .m80, daypart: .night), 1.0)
        XCTAssertEqual(SolarGeometry.weight(band: .m80, daypart: .day), 0.2)
        XCTAssertEqual(SolarGeometry.weight(band: .m10, daypart: .day), 0.8)
        XCTAssertEqual(SolarGeometry.weight(band: .m10, daypart: .night), 0.1)
        XCTAssertEqual(SolarGeometry.weight(band: .m40, daypart: .day), 0.6)
        XCTAssertEqual(SolarGeometry.weight(band: .m40, daypart: .night), 1.0)

        // 20 m is the one band that never falls far, either side of the
        // terminator.
        XCTAssertGreaterThanOrEqual(SolarGeometry.weight(band: .m20, daypart: .night), 0.6)
        XCTAssertEqual(SolarGeometry.weight(band: .m20, daypart: .day), 1.0)

        // Gray line lifts the low bands to their night value and no further.
        XCTAssertEqual(SolarGeometry.weight(band: .m160, daypart: .grayLine),
                       SolarGeometry.weight(band: .m160, daypart: .night))
    }

    /// No band claims anything outside 0…1, and 6 m and up claim nothing at
    /// all — sporadic-E is not what the banked sources describe.
    func testEveryBandHasSaneWeightsAndVHFMakesNoDaypartClaim() {
        for band in Band.allCases {
            for daypart in SolarGeometry.Daypart.allCases {
                let weight = SolarGeometry.weight(band: band, daypart: daypart)
                XCTAssertTrue((0...1).contains(weight), "\(band) \(daypart) = \(weight)")
            }
        }
        for band in [Band.m6, .m2, .cm125, .cm70] {
            let weights = SolarGeometry.Daypart.allCases.map {
                SolarGeometry.weight(band: band, daypart: $0)
            }
            XCTAssertEqual(Set(weights).count, 1, "\(band) should not vary by daypart")
        }
    }
}
