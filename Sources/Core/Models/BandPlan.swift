import Foundation

/// Where CW ends and phone begins on each band, so a QSY can put the radio in
/// the right mode without the operator reaching for the mode knob.
///
/// **Not to be confused with `SpotFilter.modeClass`.** That one guesses what
/// mode a *cluster spot* is in — a comment-first heuristic that wants the FT8
/// watering holes and is allowed to be wrong. This decides what mode *your
/// radio* should be in, from the regulations, and must not be wrong. The two
/// tables answer different questions and neither should be rewritten in terms
/// of the other.
///
/// Sources, banked in `docs/research/band_plan_sources.md`:
///
/// - **47 CFR §97.305(c)** (law.cornell.edu/cfr/text/47/97.305, read
///   2026-07-25) — the emission-type table, which is what says where phone is
///   permitted at all. Deliberately *not* §97.301(a)'s license-class phone
///   edges: the logger does not know the operator's class, and putting a radio
///   in SSB is not itself an unlawful act.
/// - **47 CFR §97.301(a)** (read 2026-07-25) for the one boundary §97.305(c)
///   names without a number: 80 m is 3.500–3.600 MHz and 75 m is 3.600–4.000
///   MHz in ITU Region 2, so the crossover is 3600 kHz.
/// - **ARRL band plan** (arrl.org/band-plan, read 2026-07-25) for 160 m alone,
///   where §97.305(c) permits phone across the whole band and so supplies no
///   crossover. The plan reads "1.843-2.000 SSB, SSTV and other wideband
///   modes".
enum BandPlan {

    private enum PhoneEdge {
        /// Phone starts at this frequency in kHz; below it the band is CW.
        case from(Double)
        /// Phone is never authorized on the band, so all of it is CW.
        case never
    }

    /// Where phone begins on each band. A band is absent when no defensible
    /// CW/phone boundary exists:
    ///
    /// - **60 m** — five channels, USB by rule with CW and data also permitted.
    ///   Nothing about a frequency there implies one mode over another.
    /// - **1.25 m, 70 cm** — all-mode allocations whose plans are organised by
    ///   activity (EME, beacons, repeater pairs, FM simplex), not by a single
    ///   CW→phone split.
    private static let plan: [Band: PhoneEdge] = [
        .m160: .from(1843),   // ARRL band plan; §97.305(c) permits phone band-wide
        .m80: .from(3600),    // §97.301(a): 80 m 3.500–3.600, 75 m 3.600–4.000 (Region 2)
        .m40: .from(7125),    // §97.305(c); the 7.075–7.100 phone row is Region 1/3 + Pacific
        .m30: .never,         // §97.305(c) gives 30 m an RTTY/data row and no phone row
        .m20: .from(14150),
        .m17: .from(18110),
        .m15: .from(21200),
        .m12: .from(24930),
        .m10: .from(28300),
        .m6: .from(50100),    // §97.305(c) phone from 50.1; ARRL "50.0-50.1 CW, beacons"
        .m2: .from(144100),   // §97.305(c) phone from 144.1; ARRL "144.05-144.10 General CW"
    ]

    /// The mode the radio belongs in at a frequency, or `nil` on the bands and
    /// frequencies where the plan has no opinion. Only ever `.cw` or `.phone` —
    /// the band plan never selects a digital mode.
    static func radioMode(atKHz kHz: Double) -> ModeClass? {
        guard let band = Band.from(freqKHz: Int(kHz.rounded())),
              let edge = plan[band] else { return nil }
        switch edge {
        case .never: return .cw
        case .from(let phoneStart): return kHz >= phoneStart ? .phone : .cw
        }
    }

    /// The mode to switch to when QSYing to `kHz` while operating in
    /// `currentMode`, or `nil` to leave the mode alone.
    ///
    /// Two cases deliberately leave it alone beyond "the plan has no opinion":
    ///
    /// - The mode is already right, so a QSY can never thrash the radio.
    /// - The operator is running a digital mode and the target is the band's
    ///   CW/data portion, where that digital mode is perfectly at home. N1MM's
    ///   manual makes the mirror-image promise — it "does not switch the radio
    ///   automatically to a digital mode if you click within a digital band
    ///   segment" — and dragging a RTTY operator into CW is the same
    ///   presumption in the other direction. Moving into the *phone* segment
    ///   does switch them, because RTTY does not belong there.
    static func modeChange(toKHz kHz: Double, currentMode: ModeClass) -> ModeClass? {
        guard let target = radioMode(atKHz: kHz), target != currentMode else { return nil }
        if currentMode == .digital, target == .cw { return nil }
        return target
    }

    /// The raw mode string the radio drivers and the manual mode picker both
    /// understand. "SSB" rather than USB/LSB on purpose — the driver resolves
    /// the sideband from the frequency it is already tuned to.
    static func rawMode(for mode: ModeClass) -> String? {
        switch mode {
        case .cw: "CW"
        case .phone: "SSB"
        case .digital: nil  // the band plan never selects a digital mode
        }
    }
}
