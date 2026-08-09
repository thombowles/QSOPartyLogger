import Foundation

/// Where the sun is, and which bands that usually favours.
///
/// The advisor's one strand that needs no spots and no log: the terminator is
/// a fact about the operator's own coordinates, so it keeps working for a
/// NON-ASSISTED entry and for a station that has not made a contact yet.
///
/// Equations transcribed from the cell formulas of NOAA's own
/// `NOAA_Solar_Calculations_day.ods` — see `docs/research/solar_geometry_sources.md`,
/// which carries the whole table with its coefficients and the fetch date.
/// NOAA's page names Jean Meeus's *Astronomical Algorithms* as their source.
/// The transcription is pinned against the US Naval Observatory's independent
/// rise/set service at four places and dates, agreeing to within a minute at
/// every one.
///
/// Reads no clock and holds no calendar. `date` is passed in, everything is
/// UTC, and the Julian Day comes straight off the Unix timestamp — so there is
/// no daylight-saving, locale, or time-zone edge anywhere in this file.
///
/// Lives beside `Maidenhead`, which supplies its inputs: Contest Setup already
/// stores a grid square, and its center is the operator's position.
enum SolarGeometry {

    /// The sun's crossings for one UTC day at one place.
    ///
    /// `sunset` is the one that **follows** `sunrise`, which for most of the
    /// Americas falls on the next UTC day — the operator's evening. That is
    /// the pairing the advisor needs ("sunset was 0112Z"); an almanac's
    /// convention of reporting whatever set lands inside the requested UTC day
    /// would hand back last night's.
    struct Times: Equatable, Sendable {
        var sunrise: Date
        var solarNoon: Date
        var sunset: Date
    }

    /// Which of the three propagation regimes this place is in right now.
    enum Daypart: String, Equatable, Sendable, CaseIterable {
        case day
        case grayLine
        case night
    }

    /// How far either side of a crossing still counts as gray line. ARRL's own
    /// gray-line material treats sunrise and sunset as events with a window
    /// around them rather than instants — `docs/research/band_daypart_sources.md`,
    /// Source 3, finding 3.
    static let grayLineWindow: TimeInterval = 45 * 60

    /// The zenith angle NOAA defines a crossing at: the sun's apparent radius
    /// plus mean horizon refraction. It is why these times match an almanac's
    /// rather than a geometric horizon's.
    private static let sunriseZenith = 90.833

    // MARK: Position

    /// Solar elevation in degrees, corrected for atmospheric refraction —
    /// positive with the sun up, negative with it down.
    static func elevation(latitude: Double, longitude: Double, date: Date) -> Double {
        let raw = rawElevation(latitude: latitude, longitude: longitude, date: date)
        return raw + refraction(elevation: raw)
    }

    /// The sun's declination in degrees at `date`. Exposed because it is the
    /// one intermediate a test can check against a published almanac figure.
    static func declination(date: Date) -> Double {
        position(date).declination
    }

    /// Apparent solar time minus mean solar time, in minutes.
    static func equationOfTime(date: Date) -> Double {
        position(date).equationOfTime
    }

    /// Sunrise, solar noon and sunset for the UTC day containing `date`.
    ///
    /// `nil` where the sun neither rises nor sets — inside the Arctic or
    /// Antarctic circles in their respective seasons, where NOAA's own
    /// spreadsheet yields `#NUM!`. The advisor's solar strand goes silent
    /// there rather than inventing a terminator.
    static func sunriseSunset(latitude: Double, longitude: Double, date: Date) -> Times? {
        let dayStart = utcDayStart(date)
        // Solar noon depends on the equation of time, which depends on the
        // instant — so start from mean solar noon and refine. One pass lands
        // within a second or two; the second is free and removes the question.
        var noon = dayStart.addingTimeInterval((720 - 4 * longitude) * 60)
        for _ in 0..<2 {
            let eqTime = position(noon).equationOfTime
            noon = dayStart.addingTimeInterval((720 - 4 * longitude - eqTime) * 60)
        }

        let declination = position(noon).declination
        let cosHA = cos(radians(sunriseZenith))
            / (cos(radians(latitude)) * cos(radians(declination)))
            - tan(radians(latitude)) * tan(radians(declination))
        guard cosHA >= -1, cosHA <= 1 else { return nil }

        // One degree of hour angle is four minutes of time — the 4 and the
        // 1440 in NOAA's sheet are that same fact twice.
        let halfDay = degrees(acos(cosHA)) * 4 * 60
        return Times(
            sunrise: noon.addingTimeInterval(-halfDay),
            solarNoon: noon,
            sunset: noon.addingTimeInterval(halfDay)
        )
    }

    // MARK: Daypart

    /// Day, gray line, or night at this place and instant.
    ///
    /// Gray line wins wherever it applies. The nearest crossing is searched
    /// across yesterday, today and tomorrow, because a window that straddles
    /// midnight UTC would otherwise find only the far end of its own day.
    ///
    /// Where the sun neither rises nor sets, there is no gray line to be in
    /// and the answer is whichever side of the horizon the sun is on.
    static func daypart(latitude: Double, longitude: Double, date: Date) -> Daypart {
        if let gap = secondsToNearestCrossing(latitude: latitude, longitude: longitude, date: date),
           abs(gap) <= grayLineWindow {
            return .grayLine
        }
        return elevation(latitude: latitude, longitude: longitude, date: date) > 0 ? .day : .night
    }

    /// Seconds until (negative: since) the nearest sunrise or sunset. `nil` at
    /// a place and season with no crossings at all.
    static func secondsToNearestCrossing(
        latitude: Double, longitude: Double, date: Date
    ) -> TimeInterval? {
        nearestCrossing(latitude: latitude, longitude: longitude, date: date)
            .map { $0.date.timeIntervalSince(date) }
    }

    /// The nearest sunrise or sunset, and **which of the two it is** — the
    /// half the copy needs, since "sunset was 0120Z" and "sunrise was 1147Z"
    /// point at opposite ends of the band stack.
    ///
    /// Searched across yesterday, today and tomorrow, because a crossing
    /// minutes away can easily belong to the neighbouring UTC day: EM13's
    /// sunset lands after midnight UTC all summer.
    static func nearestCrossing(
        latitude: Double, longitude: Double, date: Date
    ) -> (isSunrise: Bool, date: Date)? {
        var nearest: (isSunrise: Bool, date: Date)?
        for dayOffset in -1...1 {
            let probe = date.addingTimeInterval(Double(dayOffset) * 86400)
            guard let times = sunriseSunset(latitude: latitude, longitude: longitude, date: probe)
            else { continue }
            for candidate in [(true, times.sunrise), (false, times.sunset)] {
                let gap = abs(candidate.1.timeIntervalSince(date))
                if nearest.map({ gap < abs($0.date.timeIntervalSince(date)) }) ?? true {
                    nearest = (isSunrise: candidate.0, date: candidate.1)
                }
            }
        }
        return nearest
    }

    /// How much this band is usually worth in this daypart, 0…1.
    ///
    /// **Tendency, not measurement.** The whole table and the reasoning for
    /// every row is banked in `docs/research/band_daypart_sources.md`: NOAA's
    /// ionosphere and HF pages for the D-layer/illumination physics, ARRL's
    /// K9LA papers for the MUF and gray-line findings. Observed spot evidence
    /// outranks this wherever both exist — these numbers exist so a candidate
    /// band with no spots on it still sorts sensibly against one that has some.
    ///
    /// 6 m and above get a flat weight on purpose: sporadic-E and tropo are
    /// not what those sources describe, and a daypart claim about them would
    /// be invention.
    static func weight(band: Band, daypart: Daypart) -> Double {
        let (day, grayLine, night): (Double, Double, Double) = switch band {
        case .m160: (0.10, 1.00, 1.00)
        case .m80: (0.20, 1.00, 1.00)
        case .m60: (0.30, 0.95, 0.90)
        case .m40: (0.60, 1.00, 1.00)
        case .m30: (0.70, 0.90, 0.90)
        case .m20: (1.00, 0.90, 0.60)
        case .m17: (1.00, 0.80, 0.40)
        case .m15: (0.90, 0.70, 0.20)
        case .m12: (0.80, 0.60, 0.15)
        case .m10: (0.80, 0.60, 0.10)
        case .m6, .m2, .cm125, .cm70: (0.50, 0.50, 0.50)
        }
        return switch daypart {
        case .day: day
        case .grayLine: grayLine
        case .night: night
        }
    }

    // MARK: The NOAA chain

    /// The two quantities every other figure here is built from.
    private struct Position {
        var declination: Double
        var equationOfTime: Double
    }

    private static func position(_ date: Date) -> Position {
        // The Unix epoch *is* JD 2440587.5, so this replaces NOAA's
        // spreadsheet-serial term exactly and needs no calendar.
        let julianDay = date.timeIntervalSince1970 / 86400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLong = (280.46646 + t * (36_000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnom = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let centre = sin(radians(meanAnom)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnom)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnom)) * 0.000289
        let trueLong = meanLong + centre
        let appLong = trueLong - 0.00569 - 0.00478 * sin(radians(125.04 - 1934.136 * t))
        let meanObliq = 23 + (26 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60) / 60
        let obliq = meanObliq + 0.00256 * cos(radians(125.04 - 1934.136 * t))

        let declination = degrees(asin(sin(radians(obliq)) * sin(radians(appLong))))
        let varY = pow(tan(radians(obliq / 2)), 2)
        let equationOfTime = 4 * degrees(
            varY * sin(2 * radians(meanLong))
                - 2 * eccentricity * sin(radians(meanAnom))
                + 4 * eccentricity * varY * sin(radians(meanAnom)) * cos(2 * radians(meanLong))
                - 0.5 * varY * varY * sin(4 * radians(meanLong))
                - 1.25 * eccentricity * eccentricity * sin(2 * radians(meanAnom))
        )
        return Position(declination: declination, equationOfTime: equationOfTime)
    }

    /// Elevation before the refraction correction.
    private static func rawElevation(latitude: Double, longitude: Double, date: Date) -> Double {
        let p = position(date)
        let minutesIntoDay = date.timeIntervalSince(utcDayStart(date)) / 60
        var trueSolarTime = (minutesIntoDay + p.equationOfTime + 4 * longitude)
            .truncatingRemainder(dividingBy: 1440)
        // A longitude east of Greenwich can push the sum past a day's end and
        // a western one below its start; NOAA's MOD wraps both ways.
        if trueSolarTime < 0 { trueSolarTime += 1440 }

        let quarter = trueSolarTime / 4
        let hourAngle = quarter < 0 ? quarter + 180 : quarter - 180

        let cosZenith = sin(radians(latitude)) * sin(radians(p.declination))
            + cos(radians(latitude)) * cos(radians(p.declination)) * cos(radians(hourAngle))
        // Rounding can put the cosine a hair outside its domain at the poles,
        // where `acos` would return NaN and every comparison against it would
        // silently read as false.
        return 90 - degrees(acos(min(1, max(-1, cosZenith))))
    }

    /// NOAA's piecewise refraction correction, in degrees.
    private static func refraction(elevation: Double) -> Double {
        if elevation > 85 { return 0 }
        let t = tan(radians(elevation))
        let arcSeconds: Double = if elevation > 5 {
            58.1 / t - 0.07 / pow(t, 3) + 0.000086 / pow(t, 5)
        } else if elevation > -0.575 {
            1735 + elevation
                * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711)))
        } else {
            -20.772 / t
        }
        return arcSeconds / 3600
    }

    private static func utcDayStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 86400).rounded(.down) * 86400)
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
