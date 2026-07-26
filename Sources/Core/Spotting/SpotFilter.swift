import Foundation

/// Continent test on a spotter's callsign, used to keep the band map to
/// stations that can plausibly hear your run frequency. Prefix-based rather
/// than a full DXCC table: the goal is dropping EU/JA/VK skimmer noise, not
/// award-grade country resolution.
///
/// US calls (including KH6/KL7) all count as North America — a Hawaii or
/// Alaska spotter is a US station worth seeing in a stateside QSO party.
enum SpotFilter {

    /// Whole-entity prefixes, longest first so VP2/VP5/VP9 (NA) don't drag in
    /// VP8 (South America), and PJ5–7 (NA) don't drag in PJ2/PJ4 (SA).
    private static let threeCharacter: Set<String> = [
        "KP1", "KP2", "KP3", "KP4", "KP5", "KG4",       // US Caribbean
        "VP2", "VP5", "VP9",                            // Br. Caribbean + Bermuda
        "PJ5", "PJ6", "PJ7",                            // Saba, St Eustatius, St Maarten
    ]

    private static let twoCharacter: Set<String> = [
        // Canada
        "VE", "VA", "VB", "VC", "VD", "VF", "VG", "VO", "VX", "VY",
        "CY", "CZ", "CF", "CG", "CH", "CI", "CJ", "CK",
        // Mexico
        "XE", "XF", "XA", "XB", "XC", "XD", "XG", "XH", "XI",
        "4A", "4B", "4C", "6D", "6E", "6F", "6G", "6H", "6I", "6J",
        // Greenland + St Pierre
        "OX", "XP", "FP",
        // Central America
        "TG", "TD", "TI", "TE", "YN", "H6", "H7", "YS", "HR", "HQ",
        "HP", "HO", "H3", "H8", "H9", "V3",
        // Caribbean
        "CO", "CM", "CL", "T4", "HI", "HH", "6Y", "C6", "ZF",
        "V2", "V4", "J3", "J6", "J7", "J8", "8P", "FM", "FG", "FJ", "FS",
    ]

    /// US blocks: K, N, W and AA–AL.
    private static func isUnitedStates(_ call: String) -> Bool {
        guard let first = call.first else { return false }
        if first == "K" || first == "N" || first == "W" { return true }
        guard first == "A", let second = call.dropFirst().first else { return false }
        return second >= "A" && second <= "L"
    }

    /// Continent test for any callsign — the spotter or the spotted station.
    static func isNorthAmerican(call: String) -> Bool {
        // Skimmers append "-#" / "-1"; portables append "/4" — the home call
        // in front is what identifies the entity.
        let base = call
            .uppercased()
            .split(whereSeparator: { $0 == "-" || $0 == "/" })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard base.count >= 2, base.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }

        if threeCharacter.contains(String(base.prefix(3))) { return true }
        if twoCharacter.contains(String(base.prefix(2))) { return true }
        return isUnitedStates(base)
    }

    static func isNorthAmerican(spotter: String) -> Bool {
        isNorthAmerican(call: spotter)
    }

    /// RBN/skimmer spots: posted by a "-#" node, or carrying the automated
    /// signal report a human would never type ("22 dB 25 WPM").
    static func isSkimmer(_ spot: Spot) -> Bool {
        if spot.spotter.uppercased().hasSuffix("-#") { return true }
        let tokens = Set(
            spot.comment.uppercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        return tokens.contains("DB") && tokens.contains("WPM")
    }

    /// Convenience for view code: apply the filter only when it's turned on.
    static func northAmericanOnly(_ spots: [Spot], enabled: Bool = true) -> [Spot] {
        guard enabled else { return spots }
        return spots.filter { isNorthAmerican(spotter: $0.spotter) }
    }

    // MARK: Mode inference

    /// Mode hints a spotter might type. Matched as whole words so a callsign
    /// like K5CW in a comment isn't mistaken for a mode.
    private static let commentModes: [(token: String, mode: ModeClass)] = [
        ("CW", .cw),
        ("SSB", .phone), ("USB", .phone), ("LSB", .phone), ("PHONE", .phone), ("SSTV", .phone),
        ("FT8", .digital), ("FT4", .digital), ("RTTY", .digital), ("PSK", .digital),
        ("PSK31", .digital), ("JT65", .digital), ("JS8", .digital), ("DIGI", .digital),
        ("DATA", .digital), ("MFSK", .digital), ("OLIVIA", .digital),
    ]

    /// Sub-band boundaries in kHz: CW below `cw`, digital below `digital`,
    /// phone above. Rough by design — the comment wins when present.
    private static let segments: [(band: Band, cw: Double, digital: Double)] = [
        (.m160, 1840, 1845),
        (.m80, 3570, 3600),
        (.m60, 5330, 5330),
        (.m40, 7045, 7100),
        (.m30, 10130, 10150),      // no phone on 30m
        (.m20, 14070, 14112),
        (.m17, 18095, 18110),
        (.m15, 21070, 21125),
        (.m12, 24915, 24930),
        (.m10, 28070, 28190),
        (.m6, 50100, 50100),       // 6m handled specially below
    ]

    /// What mode a spot most likely is, from the spotter's comment first and
    /// the band plan second.
    static func modeClass(freqKHz: Double, comment: String) -> ModeClass {
        let tokens = Set(
            comment.uppercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        for (token, mode) in commentModes where tokens.contains(token) {
            return mode
        }

        guard let band = Band.from(freqKHz: Int(freqKHz.rounded())) else { return .phone }
        // 6m: CW at the bottom, the FT8 watering hole at 50.313, phone between.
        if band == .m6 {
            if freqKHz < 50100 { return .cw }
            return (50300...50400).contains(freqKHz) ? .digital : .phone
        }
        guard let segment = segments.first(where: { $0.band == band }) else { return .phone }
        if freqKHz < segment.cw { return .cw }
        if freqKHz < segment.digital { return .digital }
        return .phone
    }

    /// Sub-bands run CW, then digital, then phone up from the bottom of each
    /// band — the order a disallowed mode has to be redistributed along.
    private static let segmentOrder: [ModeClass] = [.cw, .digital, .phone]

    /// Mode inference held to the modes a party actually permits.
    ///
    /// The band plan above is tuned for DX cluster spots, where the FT8
    /// watering holes are real. A QSO party that forbids digital has no such
    /// segment: its CW activity simply runs further up the band (ALQP's
    /// reaches about 7060, well past the generic 7045 boundary). Left
    /// unconstrained the inference is not merely cosmetic — `wouldAddMultiplier`
    /// rejects any mode the party disallows, so the multiplier badge vanishes
    /// on every station in the phantom segment.
    ///
    /// A forbidden mode is folded into its neighbour, preferring the lower
    /// segment, which is where the activity it displaced actually sits. An
    /// empty allow-list means no constraint.
    static func modeClass(
        freqKHz: Double,
        comment: String,
        allowedModes: [ModeClass]
    ) -> ModeClass {
        let inferred = modeClass(freqKHz: freqKHz, comment: comment)
        guard !allowedModes.isEmpty, !allowedModes.contains(inferred) else { return inferred }
        guard let index = segmentOrder.firstIndex(of: inferred) else { return inferred }

        for distance in 1..<segmentOrder.count {
            let below = index - distance
            if below >= 0, allowedModes.contains(segmentOrder[below]) {
                return segmentOrder[below]
            }
            let above = index + distance
            if above < segmentOrder.count, allowedModes.contains(segmentOrder[above]) {
                return segmentOrder[above]
            }
        }
        return inferred
    }

    // MARK: Combined filtering

    /// Every axis the band map can filter on. Defaults keep everything;
    /// empty `modes` / `bands` mean "no restriction on that axis".
    struct Options: Equatable {
        /// Who posted the spot must be in North America.
        var northAmericanSpottersOnly = false
        /// The station being spotted must be in North America.
        var northAmericanStationsOnly = false
        /// Drop stations already in the log for this band+mode.
        var hideWorked = false
        /// Drop automated RBN/skimmer spots.
        var hideSkimmer = false
        var modes: Set<ModeClass> = []
        var bands: Set<Band> = []
        /// Modes the active party permits, so a spot's inferred mode is held
        /// to the same rules that decide whether it can be a multiplier.
        /// Empty means no constraint.
        var allowedModes: [ModeClass] = []
        /// Which feeds to show. Empty means no restriction. A cluster carries
        /// hundreds of spots against the hub's handful, so isolating the
        /// county-bearing feed is the difference between using it and losing
        /// it in the noise.
        var sources: Set<SpotSource> = []
        /// Calls counted as worked when `hideWorked` is on.
        var workedCalls: Set<String> = []
        /// `CALL|COUNTY` pairs already worked. A spot that reports a county is
        /// judged on these instead of the callsign, because a mobile in a new
        /// county is a new contact — `DupeChecker.DupeKey` says so. Without
        /// this a worked rover stays hidden through every county it drives
        /// into, which is where the multipliers are.
        var workedCallCounties: Set<String> = []

        /// Any filter narrowing the list (age is separate — it's not a view filter).
        var isActive: Bool {
            northAmericanSpottersOnly || northAmericanStationsOnly
                || hideWorked || hideSkimmer || !modes.isEmpty || !bands.isEmpty
                || !sources.isEmpty
        }
    }

    /// Whether there is anything left to work on this spot.
    ///
    /// A spot that reports a county is judged on call+county; one that does
    /// not can only be judged on the call, which is every cluster spot and so
    /// preserves the original behaviour exactly.
    static func isWorked(
        _ spot: Spot,
        workedCalls: Set<String>,
        workedCallCounties: Set<String>
    ) -> Bool {
        let call = spot.call.uppercased()
        guard let county = spot.county, !county.isEmpty else {
            return workedCalls.contains(call)
        }
        return workedCallCounties.contains("\(call)|\(county.uppercased())")
    }

    static func matches(_ spot: Spot, options: Options) -> Bool {
        if options.northAmericanSpottersOnly, !isNorthAmerican(call: spot.spotter) { return false }
        if options.northAmericanStationsOnly, !isNorthAmerican(call: spot.call) { return false }
        // Your own log is never what the source filter is choosing between:
        // "QSO Party Hub spots only" picks a feed, and this is not one. Hiding
        // worked stations is the control that clears these, and clears all of
        // them — every station in your log is worked by definition.
        if !options.sources.isEmpty, spot.source != .local,
           !options.sources.contains(spot.source) {
            return false
        }
        if options.hideWorked,
           isWorked(spot, workedCalls: options.workedCalls,
                    workedCallCounties: options.workedCallCounties) {
            return false
        }
        if options.hideSkimmer, isSkimmer(spot) { return false }
        if !options.bands.isEmpty, let band = spot.band, !options.bands.contains(band) { return false }
        if !options.modes.isEmpty,
           !options.modes.contains(modeClass(freqKHz: spot.freqKHz, comment: spot.comment,
                                             allowedModes: options.allowedModes)) {
            return false
        }
        return true
    }

    static func filter(_ spots: [Spot], options: Options) -> [Spot] {
        spots.filter { matches($0, options: options) }
    }
}
