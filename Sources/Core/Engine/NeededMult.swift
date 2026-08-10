import Foundation

/// One question, asked of one spot: **would working this station add a
/// multiplier this log does not already hold?**
///
/// The advisor's needed-mult chips and the `moveCall` census both run on this,
/// so a chip can never point at a county the score would not pay for.
///
/// It reads an already-computed `ScoreBreakdown` rather than re-scoring the
/// log, because it is asked once per spot on every tick and `ScoreEngine.score`
/// folds the whole log. What it does **not** do is re-derive the scope rule:
/// per-band, per-mode, per-band-and-mode and once-only scopes all exist in the
/// catalogue, and it calls `ScoreEngine`'s own `scopeComponent` — two
/// implementations of "what does *worked on 20 m* mean" is a scoring bug
/// factory.
///
/// ## What v1 can see
///
/// **County-class multipliers only, and only from spots that name a county** —
/// which in practice means hub spots, since cluster spots carry no location at
/// all. A state-, province- or DX-class need cannot be detected from a spot
/// that does not say where the station is, and inferring it from the callsign
/// would be a guess dressed as a multiplier. The advisor never claims
/// completeness (spec §8).
enum NeededMult {

    /// Would a valid, non-dupe QSO with a station in `county`, on `band`, in
    /// `modeClass`, add a `MultKey` this log does not already hold?
    ///
    /// `false` for everything the rules make pointless as well as everything
    /// already worked: a mode or band this party does not count, a token that
    /// is not one of its counties, an entrant side that does not count
    /// counties at all, a log already at the party's scored multiplier ceiling,
    /// and a county whose activation multiplier would simply be traded away
    /// for the worked one.
    static func isNeeded(
        county: String,
        band: Band,
        modeClass: ModeClass,
        score: ScoreEngine.ScoreBreakdown,
        party: PartyDefinition,
        myLocation: MyLocation
    ) -> Bool {
        let abbr = county.trimmingCharacters(in: .whitespaces).uppercased()
        guard !abbr.isEmpty,
              party.allowedModeClasses.contains(modeClass),
              party.validBands.contains(band),
              party.county(for: abbr) != nil
        else { return false }

        let rule = myLocation.isInState ? party.multipliers.inState : party.multipliers.outState
        guard rule.classes.contains(.county) else { return false }

        // Past the party's scored ceiling a further multiplier pays nothing,
        // so the chip must not send the operator chasing it — the same guard
        // `ScoreEngine.wouldAddMultiplier` applies to the NEW MULT badge
        // (CQP: 58 of 63).
        if let cap = rule.maxScoredMultipliers, score.multiplierKeys.count >= cap { return false }

        let scope = ScoreEngine.scopeComponent(rule.countScope, band: band, modeClass: modeClass)
        let key = ScoreEngine.MultKey(multClass: .county, value: abbr, scope: scope)
        guard !score.multiplierKeys.contains(key) else { return false }

        // A county the operator has already self-activated under a forfeiting
        // rule trades one key for another rather than adding one.
        if let activation = rule.activatedCountyMultiplier, activation.notOtherwiseWorked,
           !ScoreEngine.countyGains(abbr, addingScope: scope, to: score.multiplierKeys) {
            return false
        }
        return true
    }

    /// The spots among `spots` that name a county this log still needs, in the
    /// order they were given.
    ///
    /// A spot with no county — every cluster spot — is silently not a needed
    /// mult rather than a maybe. Spots whose frequency lands outside any band
    /// are dropped for the same reason.
    static func spots(
        _ spots: [Spot],
        currentMode: ModeClass,
        followBandPlan: Bool,
        score: ScoreEngine.ScoreBreakdown,
        party: PartyDefinition,
        myLocation: MyLocation
    ) -> [Spot] {
        spots.filter { spot in
            guard let county = spot.county, let band = spot.band else { return false }
            return isNeeded(
                county: county,
                band: band,
                modeClass: workedModeClass(
                    atKHz: spot.freqKHz, currentMode: currentMode, followBandPlan: followBandPlan
                ),
                score: score,
                party: party,
                myLocation: myLocation
            )
        }
    }

    /// The mode class a contact made at `kHz` would be logged in — which is
    /// what decides the scope, and therefore whether the multiplier is needed
    /// at all in a per-mode party.
    ///
    /// Deferred to `BandPlan.modeChange`, the same rule the tune path itself
    /// obeys, so the chip and the radio cannot disagree about what tuning
    /// there would do. With the band-plan follow switched off the radio stays
    /// where it is, and so does this.
    static func workedModeClass(
        atKHz kHz: Double, currentMode: ModeClass, followBandPlan: Bool
    ) -> ModeClass {
        guard followBandPlan,
              let change = BandPlan.modeChange(toKHz: kHz, currentMode: currentMode)
        else { return currentMode }
        return change
    }
}
