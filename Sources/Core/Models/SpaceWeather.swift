import Foundation

/// What the sun is doing right now, coarsely, and what that usually does to
/// each band.
///
/// A modifier over `SolarGeometry`'s daypart weights and nothing more. The
/// geometry says which bands the hour favours; this says whether the ionosphere
/// is in any shape to deliver — an elevated Kp damps the low bands hardest, a
/// high solar flux lifts the high ones.
///
/// **Absence is identity by design.** No network, a failed fetch, a missing
/// field, or a reading older than `staleAfter` leaves every modifier at 1.0 and
/// the advisor runs on geometry alone, exactly as it would have without this
/// file. Nothing here can make an advisory appear that geometry did not.
///
/// Endpoints, captured payloads, the NOAA scales the buckets come from, and
/// what is deliberately left out (the R and S scales, all forecasts) are banked
/// in `docs/research/space_weather_sources.md`.
struct SpaceWeather: Codable, Equatable, Sendable {

    /// 10.7 cm solar flux in solar flux units. NOAA: "an excellent indicator of
    /// solar activity", ranging from below 50 to above 300 across a cycle.
    var sfi: Int?
    /// Planetary K index, in the conventional thirds (1.33, 3.67, 5.67…).
    var kp: Double?
    /// When the **older** of the two observations was made.
    ///
    /// Kp is three-hourly and the flux is reported three times a day, so the
    /// two are never stamped together. Taking the older one means "as of" can
    /// only ever understate this reading's freshness — the direction that
    /// cannot mislead an operator into trusting it too far.
    var observedAt: Date

    /// Past this, the reading stops modifying anything. Six hours, not one:
    /// Kp arrives every three hours, so a two-hour-old Kp is not stale, it is
    /// the current Kp.
    static let staleAfter: TimeInterval = 6 * 3600

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(observedAt) > Self.staleAfter
            || observedAt > now.addingTimeInterval(3600)  // a clock-skewed future stamp
    }

    /// The multiplier this reading puts on `band`'s daypart weight.
    ///
    /// Coarse on purpose — three buckets each, the Kp edges taken from NOAA's
    /// own G-scale (G1 at Kp 5, G2 at Kp 6), the flux edges round numbers
    /// inside NOAA's stated 50–300 range. Tendency, not measurement, the same
    /// law the daypart table obeys.
    func modifier(band: Band, now: Date) -> Double {
        guard !isStale(now: now) else { return 1 }
        return kpModifier(band) * sfiModifier(band)
    }

    /// `Kp 4.0 · SFI 128, observed 1800Z` — the observation time is never
    /// optional, so a stale figure cannot masquerade as a current one.
    /// `nil` when the reading carries neither value.
    func summary(now: Date) -> String? {
        var parts: [String] = []
        if let kp { parts.append("Kp \(Self.kpText(kp))") }
        if let sfi { parts.append("SFI \(sfi)") }
        guard !parts.isEmpty else { return nil }
        let stamp = "observed \(Self.zulu(observedAt))"
        return parts.joined(separator: " · ") + ", "
            + (isStale(now: now) ? "\(stamp) — too old to weigh, ignoring it" : stamp)
    }

    // MARK: The buckets

    /// Absorption goes as the inverse square of frequency, so a geomagnetic
    /// disturbance takes the low bands first and the high bands last —
    /// `docs/research/band_daypart_sources.md`, Source 3, finding 1.
    private func kpModifier(_ band: Band) -> Double {
        guard let kp else { return 1 }
        switch Self.group(band) {
        case .low: return kp >= 6 ? 0.75 : (kp >= 5 ? 0.90 : 1)
        case .mid: return kp >= 6 ? 0.85 : (kp >= 5 ? 0.95 : 1)
        case .high: return kp >= 6 ? 0.95 : 1
        case .vhf: return 1
        }
    }

    /// The high bands live or die by the F2-region MUF, which is what makes
    /// 15/12/10 the bands that follow solar activity. 20 and 17 get a smaller
    /// share of the same effect; nothing below them is claimed at all.
    private func sfiModifier(_ band: Band) -> Double {
        guard let sfi else { return 1 }
        switch Self.group(band) {
        case .high: return sfi > 150 ? 1.15 : (sfi < 90 ? 0.85 : 1)
        case .mid: return sfi > 150 && band != .m30 ? 1.05 : 1
        case .low, .vhf: return 1
        }
    }

    private enum BandGroup { case low, mid, high, vhf }

    private static func group(_ band: Band) -> BandGroup {
        switch band {
        case .m160, .m80, .m60, .m40: .low
        case .m30, .m20, .m17: .mid
        case .m15, .m12, .m10: .high
        case .m6, .m2, .cm125, .cm70: .vhf
        }
    }

    // MARK: Parsing SWPC's products

    /// SWPC stamps every product in UTC and writes no zone designator. The
    /// trailing-`Z` spelling is accepted too, because one endpoint gaining it
    /// must not silently take the whole strand off the air.
    private static let stampFormats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss'Z'"]

    static func timestamp(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in stampFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// The newest usable row of `json/f107_cm_flux.json`.
    ///
    /// `flux` arrives in exponential notation (`9.4e+001` is 94 sfu), so it is
    /// read as a `Double` and rounded — matching it as a string would find
    /// nothing.
    static func parseFlux(_ data: Data) -> (sfi: Int, observedAt: Date)? {
        newest(data, value: "flux").map { (Int($0.value.rounded()), $0.observedAt) }
    }

    /// The newest usable row of `products/noaa-planetary-k-index.json`. The
    /// capital K is the server's, and the key is case-sensitive.
    static func parsePlanetaryK(_ data: Data) -> (kp: Double, observedAt: Date)? {
        newest(data, value: "Kp").map { (kp: $0.value, observedAt: $0.observedAt) }
    }

    /// Both products are flat arrays of objects carrying a `time_tag` and one
    /// number this app reads. **Order is not guaranteed** — the two captures
    /// banked as fixtures came from the same server on the same day sorted
    /// opposite ways — so this sorts rather than trusting either end.
    private static func newest(
        _ data: Data, value key: String
    ) -> (value: Double, observedAt: Date)? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return rows.compactMap { row -> (value: Double, observedAt: Date)? in
            guard let raw = row["time_tag"] as? String,
                  let observedAt = timestamp(raw),
                  let number = row[key] as? NSNumber
            else { return nil }
            return (number.doubleValue, observedAt)
        }
        .max { $0.observedAt < $1.observedAt }
    }

    /// One reading from whichever products answered. `nil` when neither did —
    /// a reading with no values in it would only be a timestamp claiming to be
    /// evidence.
    static func reading(flux: Data?, planetaryK: Data?) -> SpaceWeather? {
        let sfi = flux.flatMap(parseFlux)
        let kp = planetaryK.flatMap(parsePlanetaryK)
        let stamps = [sfi?.observedAt, kp?.observedAt].compactMap { $0 }
        guard let oldest = stamps.min() else { return nil }
        return SpaceWeather(sfi: sfi?.sfi, kp: kp?.kp, observedAt: oldest)
    }

    // MARK: Formatting

    /// Kp reads in thirds, and `4.0` beside `3.67` is what tells an operator
    /// the scale is not integers.
    static func kpText(_ kp: Double) -> String {
        String(format: "%.1f", kp)
    }

    static func zulu(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HHmm'Z'"
        return formatter.string(from: date)
    }
}
