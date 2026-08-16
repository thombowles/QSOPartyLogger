import Foundation

/// How the operating mode follows the VFO knob around the CQ frequency.
///
/// N1MM Logger+ (Entry window, "Run mode and S+P mode", fetched 2026-08-15):
/// "When you call CQ on a frequency, the marker CQ-Frequency is placed at that
/// frequency on the Bandmap. Thereafter, if you are in S&P mode and you tune
/// within the tuning tolerance of the marker, the program will switch
/// automatically to Run mode." and "Normally when you are on your CQ-frequency
/// you will be in Run mode and QSYing will switch to S&P mode."
///
/// Three zones rather than N1MM's two: **on** the frequency (within the
/// tuning tolerance), **near** it (a QRM dodge — Tom's "reasonable amount of
/// vfo change"), and **away** (hunting). Leaving Run needs *away*; returning
/// needs *on*. In N1MM the S&P F1 is a CQ that puts you back in Run, so an
/// early flip costs one key there; here S&P F1 is "my call", so the flip has
/// to wait until you have genuinely left.
///
/// **Edge-triggered.** Only a change of zone acts, so ⌘R is never fought:
/// choose S&P by hand on the CQ frequency and you stay there; choose Run by
/// hand five kHz away and you stay there until F1 records the new frequency.
enum TuningPolicy {

    enum Zone: Equatable, Sendable {
        case onFrequency
        case near
        case away
    }

    /// `|vfo − cq|` ≤ tolerance → `.onFrequency`; ≤ leave → `.near`; else
    /// `.away`. A leave distance below the tolerance is read as equal to it.
    static func zone(vfoHz: Int, cqHz: Int, toleranceHz: Int, leaveHz: Int) -> Zone {
        let distance = abs(vfoHz - cqHz)
        if distance <= toleranceHz { return .onFrequency }
        if distance <= max(leaveHz, toleranceHz) { return .near }
        return .away
    }

    /// The mode to switch to on arriving in `zone` from `previous`, or nil.
    /// A nil `previous` is the first observation after a CQ frequency
    /// appeared: it only records the zone.
    static func modeChange(
        from previous: Zone?,
        to zone: Zone,
        mode: OperatingMode,
        leaveEnabled: Bool,
        returnEnabled: Bool
    ) -> OperatingMode? {
        guard let previous, previous != zone else { return nil }
        switch (zone, mode) {
        case (.away, .run):
            return leaveEnabled ? .searchPounce : nil
        case (.onFrequency, .searchPounce):
            return returnEnabled ? .run : nil
        default:
            return nil
        }
    }
}

/// One distance in Hz per mode class — N1MM's Configurer keeps a tuning
/// tolerance for SSB, CW and RTTY separately ("The default value is 300" for
/// each, fetched 2026-08-15). Used twice: the tuning tolerance (the call
/// frame, and "on the CQ frequency") and the leave-Run distance.
struct TuningDistances: Codable, Equatable, Sendable {
    var cwHz: Int
    var phoneHz: Int
    var digitalHz: Int

    func hz(for mode: ModeClass) -> Int {
        switch mode {
        case .cw: cwHz
        case .phone: phoneHz
        case .digital: digitalHz
        }
    }

    mutating func set(_ hz: Int, for mode: ModeClass) {
        switch mode {
        case .cw: cwHz = hz
        case .phone: phoneHz = hz
        case .digital: digitalHz = hz
        }
    }

    /// N1MM's 300 Hz for CW and digital. Phone is wider than N1MM's 300: RBN
    /// does not skim SSB, and human SSB spots are posted to the kHz or
    /// half-kHz, so 300 Hz misses a station you can plainly hear.
    static let defaultTolerance = TuningDistances(cwHz: 300, phoneHz: 1000, digitalHz: 300)

    /// Far enough that dodging QRM stays in Run; near enough that hunting
    /// does not. This app's own — N1MM leaves Run at the tolerance.
    static let defaultLeaveRun = TuningDistances(cwHz: 1000, phoneHz: 3000, digitalHz: 1000)
}
