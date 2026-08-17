import Foundation

/// The full checklist of multipliers a party offers an entrant — every token,
/// worked or not — and the band/mode slots each one can be counted in.
///
/// The sidebar drew only *worked* tokens for every class but counties, so it
/// could never answer "what am I still missing". This supplies the rest.
///
/// Modelled on N1MM Logger+'s Multipliers window, which shows all multipliers
/// by default (worked-only is the opt-in "Show Only Worked & Expected to be
/// Worked Mults") and gives each one a row of per-band blocks, "blue for a
/// band where the mult has already been worked". Manual fetched 2026-07-31,
/// <https://n1mmwp.hamdocs.com/manual-windows/multipliers-window/>.
///
/// Every roster is derived from the party definition, so all bundled parties
/// are correct without any new per-party data. `MultiplierRosterTests` drives
/// both directions through `ScoreEngine` for every party to keep it that way.
enum MultiplierRoster {

    /// One countable slot: `scope` is the exact `ScoreEngine.MultKey` scope
    /// component, so a filled block always means a held multiplier.
    struct Slot: Hashable, Identifiable, Sendable {
        let scope: String
        /// Short display text — a band ("20m") or a mode ("CW").
        let label: String
        /// The column this slot draws in. Bands own the column wherever a band
        /// is in scope, so a per-band/mode party draws eight columns of three
        /// rather than a twenty-four-block strip no sidebar can hold.
        let group: String

        var id: String { scope }
    }

    /// One display column: a band (or mode) and the slots inside it.
    struct Column: Identifiable, Sendable {
        let label: String
        let slots: [Slot]

        var id: String { label }
    }

    struct Entry: Hashable, Identifiable, Sendable {
        let token: String
        /// Long name for the tooltip, where the party names its tokens —
        /// counties and NAQP's country list. `nil` for states, provinces and
        /// sections, whose tokens are already what operators read on the air.
        let name: String?
        /// Credited by the rules without being worked (PAQP's EPA and WPA).
        let granted: Bool

        var id: String { token }
    }

    struct ClassRoster: Identifiable, Sendable {
        let multClass: MultClass
        let entries: [Entry]
        let slots: [Slot]
        /// False for a county list kept purely for award tracking, where the
        /// party does not score counties (KSQP in-state, Worked All Kansas).
        let isMultClass: Bool

        var id: MultClass { multClass }

        /// Slots grouped into display columns, source order preserved.
        var columns: [Column] {
            var order: [String] = []
            var byGroup: [String: [Slot]] = [:]
            for slot in slots {
                if byGroup[slot.group] == nil { order.append(slot.group) }
                byGroup[slot.group, default: []].append(slot)
            }
            return order.map { Column(label: $0, slots: byGroup[$0] ?? []) }
        }
    }

    // MARK: Slots

    /// Every scope value a multiplier can be counted under for this rule.
    static func slots(
        party: PartyDefinition, rule: PartyDefinition.MultRule
    ) -> [Slot] {
        let scope = rule.countScope
        let bands = party.validBands
        let modes = party.allowedModeClasses
        // A party with no legal band or mode has nothing to count per band or
        // per mode; fall back to the single unscoped slot rather than trap.
        guard let anyBand = bands.first, let anyMode = modes.first else {
            return [Slot(scope: "", label: "", group: "")]
        }
        switch scope {
        case .once:
            // One unscoped slot. The view draws this as a plain chip, which is
            // exactly what the county grid has always looked like.
            return [Slot(scope: "", label: "", group: "")]
        case .perBand:
            return bands.map {
                Slot(
                    scope: scope.component(band: $0, modeClass: anyMode),
                    label: $0.rawValue,
                    group: $0.rawValue
                )
            }
        case .perMode:
            return modes.map {
                Slot(
                    scope: scope.component(band: anyBand, modeClass: $0),
                    label: $0.shortLabel,
                    group: $0.shortLabel
                )
            }
        case .perBandMode:
            return bands.flatMap { band in
                modes.map { mode in
                    Slot(
                        scope: scope.component(band: band, modeClass: mode),
                        label: mode.shortLabel,
                        group: band.rawValue
                    )
                }
            }
        }
    }

    // MARK: Rosters

    /// Every class this entrant can chase, in sidebar order.
    static func classes(
        party: PartyDefinition, rule: PartyDefinition.MultRule
    ) -> [ClassRoster] {
        let scoped = slots(party: party, rule: rule)
        let unscoped = [Slot(scope: "", label: "", group: "")]
        var out: [ClassRoster] = []

        func add(_ multClass: MultClass, _ entries: [Entry], isMultClass: Bool = true) {
            guard !entries.isEmpty else { return }
            out.append(ClassRoster(
                multClass: multClass,
                entries: entries,
                slots: isMultClass ? scoped : unscoped,
                isMultClass: isMultClass
            ))
        }

        // Counties come first and are drawn even where they do not score: the
        // grid doubles as county-sweep award tracking, which is worked-or-not
        // and so never per band.
        let countiesScore = rule.classes.contains(.county)
        add(
            .county,
            party.counties.map {
                Entry(token: $0.abbr, name: $0.name, granted: isGranted(.county, $0.abbr, rule))
            },
            isMultClass: countiesScore
        )

        // A section party counts sections instead of states and provinces, not
        // alongside them, so these branches are mutually exclusive by rule.
        if rule.classes.contains(.section) {
            add(.section, entries(party.sections, .section, rule))
        } else {
            add(.state, entries(stateTokens(party: party, rule: rule), .state, rule))
            if rule.classes.contains(.province) {
                add(.province, entries(party.provinces, .province, rule))
            }
        }

        // `.dx` is deliberately absent: under prefix style any plausible prefix
        // is a multiplier, so there is no finite list to draw. The sidebar
        // keeps showing worked DX tokens as text.
        return out
    }

    /// The states this rule can actually credit.
    ///
    /// Not simply the accepted *tokens*: a party that aliases DC to MD accepts
    /// DC on the air but credits Maryland, so listing DC would promise a
    /// multiplier that cannot be earned. And a home state excluded as a token
    /// is still reachable where the party lets a home-state county satisfy it.
    private static func stateTokens(
        party: PartyDefinition, rule: PartyDefinition.MultRule
    ) -> Set<String> {
        guard rule.classes.contains(.state) else {
            // The class is not counted, but a home-state county may still
            // credit the home state — the only state reachable at all.
            return rule.homeStateCountsViaCounty ? [party.homeState] : []
        }
        var tokens = MultClass.acceptedStateTokens
            .subtracting(party.excludedStateTokens)
            .subtracting(party.stateAliases.keys)
        // An alias target is credited even where the target itself is an
        // excluded token, because the scorer resolves aliases first.
        tokens.formUnion(party.stateAliases.values)
        if rule.homeStateCountsViaCounty {
            // One log covering several states credits whichever the county
            // lies in, so every member state is reachable — not just the
            // party's primary one.
            tokens.formUnion(party.homeStates)
        }
        return tokens
    }

    private static func entries(
        _ tokens: Set<String>, _ multClass: MultClass, _ rule: PartyDefinition.MultRule
    ) -> [Entry] {
        let granted = rule.granted
            .filter { $0.multClass == multClass }
            .map(\.value)
        return tokens.union(granted).sorted().map {
            Entry(token: $0, name: nil, granted: granted.contains($0))
        }
    }

    private static func isGranted(
        _ multClass: MultClass, _ token: String, _ rule: PartyDefinition.MultRule
    ) -> Bool {
        rule.granted.contains { $0.multClass == multClass && $0.value == token }
    }

    // MARK: Worked state

    /// Slots of `entry` this log already holds, for the block strip.
    static func workedSlots(
        _ entry: Entry, in roster: ClassRoster, score: ScoreEngine.ScoreBreakdown
    ) -> Set<String> {
        // A granted multiplier is credited unscoped however the party counts
        // the rest, so it fills every block rather than just the first.
        if entry.granted {
            let held = score.multiplierKeys.contains {
                $0.multClass == roster.multClass && $0.value == entry.token
            }
            return held ? Set(roster.slots.map(\.scope)) : []
        }
        return Set(
            roster.slots.map(\.scope).filter { scope in
                score.multiplierKeys.contains(
                    ScoreEngine.MultKey(
                        multClass: roster.multClass, value: entry.token, scope: scope
                    )
                )
            }
        )
    }

    /// Worked tokens for a roster the party does not score — a county list
    /// kept for sweep awards. There are no multiplier keys to read, so this
    /// comes straight from the log.
    static func awardWorkedTokens(log: ContestLog, roster: ClassRoster) -> Set<String> {
        let listed = Set(roster.entries.map(\.token))
        return Set(log.qsos.map { $0.theirLoc.uppercased() }).intersection(listed)
    }
}
