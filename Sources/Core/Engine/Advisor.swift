import Foundation

/// In-contest strategy from the data already on hand.
///
/// The app measures nearly everything a contest decision needs — four rate
/// windows, the exact worked-multiplier set, live spots with counties on them,
/// every bonus rule and operating window — and until now interpreted none of
/// it. This is the interpretation, and it obeys four laws:
///
/// 1. **Facts, not orders.** The headline is a true sentence about the
///    operator's own data. Any suggestion lives in `detail`, phrased as what
///    usually pays.
/// 2. **Quiet.** No advisory is manufactured to fill space; an empty array is
///    the commonest and most correct answer.
/// 3. **Read-only.** Nothing here logs, keys, or moves a radio. A `TuneChip`
///    carries a `Spot` and the caller decides what to do with it.
/// 4. **Evidence or silence.** A figure with too little behind it does not
///    appear, and every advisory names its evidence in `detail` — the same law
///    `RateColumn` obeys.
///
/// **Category-honest by construction.** A `NON-ASSISTED` entry receives no
/// spots at all (`SpottingPolicy` stops them reaching the store), so every
/// spot-derived strand is silent for it with no rule needed here. The own-log
/// and solar strands, which use no spotting information, keep working for
/// every category.
///
/// Pure, in the `ESM` / `RateMeter` mould: takes an explicit `now`, owns no
/// clock, touches no store, and threads its own `State` through the caller.
/// The engine owns the copy, like `RateColumn` — wording is testable and the
/// view stays a layout.
///
/// Design: `docs/superpowers/specs/2026-08-09-strategy-advisor-design.md`.
enum Advisor {

    // MARK: Thresholds
    //
    // Every number the advisor turns on, in one place, so a real contest
    // weekend can retune them without a search.

    /// A trailing hour under this was not much of a run, and halving it is
    /// noise rather than a fade.
    static let rateFloor = 20
    /// `lastTen` at or under this share of `lastHour` is a fade.
    static let fadeRatio = 0.5
    /// …and it takes this share to clear. The gap between the two is what
    /// stops the advisory flapping.
    static let clearRatio = 0.75
    /// A condition must hold across this much wall clock before it fires. One
    /// bad instantaneous reading is not a trend.
    static let sustain: TimeInterval = 3 * 60
    /// How near a window's end the countdown starts.
    static let windowWarn: TimeInterval = 2 * 3600
    /// How near the next window's opening is worth saying anything about.
    ///
    /// This advisory is about a **two-day party's overnight gap**, which is
    /// thirteen to twenty hours in every bundled schedule — not about the
    /// calendar. Without a bound, opening next month's party in August reads
    /// "Next window opens 1400Z (in 487 h 15 m)", which is not advice; the
    /// Contest Dashboard's upcoming list is where a season belongs.
    static let windowNextWithin: TimeInterval = 24 * 3600
    /// How much better a candidate must be than where you are before moving is
    /// worth the lost minutes.
    static let bandMargin = 2.0
    /// What one needed multiplier is worth in workable-station units under the
    /// Score goal. Zero under QSOs — see `Goal`.
    static let multWeight = 4.0
    /// A candidate worth less than this is not worth naming however much it
    /// beats a dead band. Evidence or silence.
    static let moveFloor = 3.0
    /// Contacts an hour one spotted station on a band implies for a run there.
    /// Ordinal, not a prediction: it exists so a band with an audience sorts
    /// above one without.
    static let runAudience = 1.0
    /// An in-state station *is* the multiplier every hunter needs, and running
    /// pays accordingly.
    static let inStateRunFactor = 1.5
    /// How far back the posture strands look.
    static let trailingWindow: TimeInterval = 60 * 60
    /// Below this many stamped rows, or this many minutes of them, an own-rate
    /// figure is not a measurement.
    static let minPostureSamples = 3
    static let minPostureMinutes = 5.0
    /// Tune chips shown before the rest become a "+N more".
    static let maxChips = 3

    // MARK: What the operator is optimising

    /// The yardstick every advisory is read against.
    ///
    /// The same census reads differently on a State QSO Party Challenge
    /// weekend — where the sponsor's formula is Σ valid QSOs × qualifying
    /// parties (`ChallengeStanding`, `docs/research/sqp_challenge_rules.md`)
    /// and a new in-contest multiplier is worth exactly nothing — than in a
    /// serious single-party entry where multipliers multiply everything.
    enum Goal: String, Codable, CaseIterable, Sendable {
        /// What this contact does to *this party's* claimed score: a heavy
        /// premium on anything that adds a `MultKey`.
        case score
        /// Every valid contact equally, because that is what the Challenge
        /// pays. `neededMultsSpotted` still shows — the party's own award has
        /// not gone anywhere — it just stops outbidding raw activity.
        case qsos

        var label: String {
            switch self {
            case .score: "Score"
            case .qsos: "QSOs"
            }
        }

        /// The multiplier premium in the `moveCall` weighting.
        var multWeight: Double {
            switch self {
            case .score: Advisor.multWeight
            case .qsos: 0
            }
        }
    }

    // MARK: Input

    /// One contact's posture, as the advisor needs it: no call, no exchange,
    /// nothing that could turn this into a second log.
    struct PostureSample: Equatable, Sendable {
        var band: Band
        var posture: OperatingMode
        var timestamp: Date
    }

    /// A band-and-mode slot of a bonus station's rule, so the advisor can name
    /// what is still open without being handed the log.
    struct BonusSlot: Hashable, Sendable {
        var band: Band
        var modeClass: ModeClass
    }

    /// Everything one evaluation reads.
    ///
    /// A struct rather than a parameter list on purpose: the deferred
    /// prior-year archive strand bolts on here later as one more optional
    /// field, touching no existing advisory.
    struct Input {
        var goal: Goal = .score
        var reading: RateMeter.Reading = .init()
        var mode: OperatingMode = .searchPounce
        var currentBand: Band?
        var currentModeClass: ModeClass = .cw
        /// One entry per valid, non-dupe row of the trailing hour that carries
        /// a posture. Rows logged before `QSO.posture` existed are simply
        /// absent, and contribute nothing.
        var recent: [PostureSample] = []
        var score: ScoreEngine.ScoreBreakdown = .init()
        var party: PartyDefinition?
        var myLocation: MyLocation = .outOfState(location: "TX")
        /// `nil` keeps the solar strand silent — no grid, no terminator.
        var gridLocator: String?
        /// `nil` or stale leaves every propagation modifier at identity.
        var spaceWeather: SpaceWeather?
        /// Post-`SpotFilter`, across every band the party runs. Empty means a
        /// NON-ASSISTED entry, a cluster that is not connected, or a genuinely
        /// empty board — the advisor cannot tell those apart and does not try.
        var spots: [Spot] = []
        /// Which band/mode slots each `workStation` bonus call has been worked
        /// in, keyed by upper-cased callsign.
        var bonusWorked: [String: Set<BonusSlot>] = [:]
        /// Whether a QSY would take the radio's mode with it, which decides
        /// the scope a spot's multiplier would land in.
        var followsBandPlan: Bool = true
        var mutedKinds: Set<Advisory.Kind> = []
    }

    // MARK: Output

    struct TuneChip: Equatable, Identifiable, Sendable {
        /// `GRY 7040` — the multiplier and where it is.
        var label: String
        /// The spot itself, so the caller fires the very same `tune(to:)` a
        /// band-map click fires. One tune rule, held in one place.
        var spot: Spot

        var id: String { "\(label)|\(spot.id)" }
    }

    struct Advisory: Identifiable, Equatable, Sendable {
        enum Kind: String, Codable, CaseIterable, Sendable {
            case runFading
            case moveCall
            case neededMultsSpotted
            case bonusStanding
            case scheduleEdge

            /// What the mute menu calls it.
            var label: String {
                switch self {
                case .runFading: "Run health"
                case .moveCall: "Move calls"
                case .neededMultsSpotted: "Needed multipliers"
                case .bonusStanding: "Bonus stations"
                case .scheduleEdge: "Operating windows"
                }
            }
        }

        /// Stable while the condition is, so a dismissal survives
        /// re-evaluation and a *different* condition of the same kind can
        /// still speak.
        var id: String
        var kind: Kind
        /// A true sentence about the operator's own data. Never an order.
        var headline: String
        /// Tooltip depth: the evidence, the thresholds, and what usually pays.
        var detail: String
        var chips: [TuneChip] = []
    }

    // MARK: State

    /// What one evaluation has to remember from the last.
    ///
    /// Sustain windows and once-per-transition flags are dates compared
    /// against the `now` argument, never a wall clock. Dismissals are
    /// per-sitting — the ⌘. spots-badge convention — and die with the window.
    struct State: Equatable, Sendable {
        /// Advisory id → when its condition first became continuously true.
        /// A lapse removes the key, so the sustain window restarts.
        var pendingSince: [String: Date] = [:]
        /// Kind → the posture and band a live advisory fired under. Present
        /// means live; a change of anchor is one of the ways it clears.
        var live: [Kind: Anchor] = [:]
        /// Ids the operator has waved off this sitting.
        var dismissed: Set<String> = []
        /// Solar crossings already announced, so each fires exactly once.
        var announced: Set<String> = []

        typealias Kind = Advisory.Kind

        struct Anchor: Equatable, Sendable {
            var posture: OperatingMode
            var band: Band?
        }

        /// Wave an advisory off for the rest of this sitting.
        mutating func dismiss(_ advisory: Advisory) {
            dismissed.insert(advisory.id)
        }
    }

    // MARK: Evaluate

    /// Every advisory that is live right now, most urgent first, and the state
    /// the next evaluation should be given.
    static func evaluate(
        _ input: Input, state: State, now: Date
    ) -> (advisories: [Advisory], state: State) {
        var state = state
        guard let party = input.party else { return ([], state) }

        // After the last operating window there is nothing left to advise
        // about, so the section as a whole goes quiet rather than counting
        // down to a contest that is over.
        if let schedule = party.schedule, !schedule.isEmpty,
           let last = schedule.map(\.end).max(), now > last {
            return ([], State(dismissed: state.dismissed))
        }

        var advisories: [Advisory] = []

        // Priority order. `runFading` first because a dying run is the one
        // thing that is costing points while it is being read about.
        let fading = runFading(input, state: &state, now: now)
        advisories.append(contentsOf: fading)
        advisories.append(contentsOf: moveCall(
            input, party: party, runIsFading: !fading.isEmpty, state: &state, now: now
        ))
        advisories.append(contentsOf: neededMults(input, party: party))
        advisories.append(contentsOf: bonusStanding(input, party: party, now: now))
        advisories.append(contentsOf: scheduleEdge(party: party, now: now))

        return (
            advisories.filter {
                !input.mutedKinds.contains($0.kind) && !state.dismissed.contains($0.id)
            },
            state
        )
    }

    /// Keep at most one live sustain timer per kind: the one for the condition
    /// currently on offer. A timer for a condition that has lapsed is dead
    /// weight, and worse — left behind, it would let that condition fire the
    /// instant it returned, skipping the window entirely.
    ///
    /// Pruned per kind rather than globally, because a kind that is *pending*
    /// has nothing in the returned list to recognise itself by, and a global
    /// sweep would delete the very timer it is trying to accumulate.
    private static func keepTimer(
        _ id: String?, forKind prefix: String, in state: inout State, now: Date
    ) {
        state.pendingSince = state.pendingSince.filter {
            !$0.key.hasPrefix(prefix) || $0.key == id
        }
        if let id { state.pendingSince[id] = state.pendingSince[id] ?? now }
    }

    // MARK: 1 — the run is dying under you

    private static func runFading(
        _ input: Input, state: inout State, now: Date
    ) -> [Advisory] {
        let anchor = State.Anchor(posture: input.mode, band: input.currentBand)
        let id = "runFading|\(input.currentBand?.rawValue ?? "?")"

        guard input.mode == .run, let lastTen = input.reading.lastTen else {
            state.live[.runFading] = nil
            keepTimer(nil, forKind: "runFading|", in: &state, now: now)
            return []
        }
        // The band changing ends this run and starts another one.
        if let live = state.live[.runFading], live != anchor {
            state.live[.runFading] = nil
        }

        let hour = input.reading.lastHour
        let wasLive = state.live[.runFading] != nil

        // Hysteresis: it takes 0.5× to start and 0.75× to stop, so a rate
        // hovering at the threshold cannot flap the advisory on and off.
        let threshold = wasLive ? clearRatio : fadeRatio
        let fading = hour >= rateFloor && Double(lastTen) <= threshold * Double(hour)
        guard fading else {
            state.live[.runFading] = nil
            keepTimer(nil, forKind: "runFading|", in: &state, now: now)
            return []
        }

        keepTimer(id, forKind: "runFading|", in: &state, now: now)
        if !wasLive {
            let since = state.pendingSince[id] ?? now
            guard now.timeIntervalSince(since) >= sustain else { return [] }
        }
        state.live[.runFading] = anchor

        return [Advisory(
            id: id,
            kind: .runFading,
            headline: "Run fading: \(lastTen)/hr last 10, down from \(hour) the past hour.",
            detail: """
            The last ten QSOs are running \(lastTen)/hr against \(hour) in the trailing hour — \
            at or under \(Int(fadeRatio * 100))% of it, held for \(UTCTime.minutes(sustain)). \
            It clears again at \(Int(clearRatio * 100))%.
            Two moves that usually pay: an S&P sweep (⌘R), or a band change — ⌘J returns here.
            """
        )]
    }

    // MARK: 2 — where the next hour is, and in which posture

    /// One `(posture, band)` pair with its evidence, in contacts-an-hour units
    /// so the two postures compare on one axis.
    struct Candidate: Equatable, Sendable {
        var posture: OperatingMode
        var band: Band
        var value: Double
        /// Workable spots on the band — observed, not predicted.
        var workable: Int
        /// How many of those would add a multiplier.
        var neededMults: Int
        /// The operator's own measured rate in this posture on this band, and
        /// how many minutes of evidence it rests on. `nil` below the floor.
        var ownRate: Int?
        var ownMinutes: Int
        /// The propagation weight, for the detail line. 1.0 where nothing is
        /// known.
        var weight: Double

        var label: String { "\(postureWord) \(band.rawValue)" }
        var postureWord: String { posture == .run ? "Run" : "S&P" }
    }

    private static func moveCall(
        _ input: Input, party: PartyDefinition, runIsFading: Bool,
        state: inout State, now: Date
    ) -> [Advisory] {
        // A working run is not interrupted by arithmetic.
        guard input.mode != .run || runIsFading else {
            keepTimer(nil, forKind: "moveCall|", in: &state, now: now)
            return []
        }

        // With no spots at all — a NON-ASSISTED entry, or a cluster that is
        // not connected — the spot-free strand is the whole strand, and the
        // operator's own rates are carried inside it rather than raised as a
        // second advisory. Nagging somebody every three minutes that another
        // band paid better an hour ago is not advice.
        guard !input.spots.isEmpty else {
            keepTimer(nil, forKind: "moveCall|", in: &state, now: now)
            return solarTransition(input, party: party, state: &state, now: now)
        }

        let candidates = ranked(self.candidates(input, party: party, now: now))
        let current = candidates.first {
            $0.posture == input.mode && $0.band == input.currentBand
        }
        let currentValue = current?.value ?? 0

        guard let best = candidates.first,
              !(best.posture == input.mode && best.band == input.currentBand),
              best.value >= moveFloor,
              // A dead current band divides by 1 rather than by zero, so
              // "twice as good" stays a finite claim.
              best.value >= bandMargin * max(currentValue, 1)
        else {
            keepTimer(nil, forKind: "moveCall|", in: &state, now: now)
            // With no census worth acting on, the spot-free strand is all
            // there is — and it is the whole strand for a NON-ASSISTED entry.
            return solarTransition(input, party: party, state: &state, now: now)
        }

        // Both endpoints are in the id, because "from Run 20 m, move to S&P
        // 40 m" is the condition. A QSY makes it a different one, which
        // restarts the sustain window and retires any dismissal of the old
        // advice — the spec's "clears on posture or band change", falling out
        // of the identity rather than needing a rule of its own.
        let id = "moveCall|from|\(input.mode.rawValue)|\(input.currentBand?.rawValue ?? "?")"
            + "|to|\(best.postureWord)|\(best.band.rawValue)"
        keepTimer(id, forKind: "moveCall|", in: &state, now: now)
        guard now.timeIntervalSince(state.pendingSince[id] ?? now) >= sustain else { return [] }

        return [Advisory(
            id: id,
            kind: .moveCall,
            headline: headline(for: best, input: input, current: current),
            detail: detail(for: candidates, current: current, input: input, now: now)
        )]
    }

    /// Best first, with the ties broken deterministically rather than by the
    /// order the bands happen to be declared in.
    ///
    /// S&P wins a tie because its evidence is *observed* — those stations are
    /// audible now — while a run's audience is a proxy for people nobody has
    /// spotted. Equal numbers, unequal confidence.
    private static func ranked(_ candidates: [Candidate]) -> [Candidate] {
        let order = Band.allCases.enumerated()
            .reduce(into: [Band: Int]()) { $0[$1.element] = $1.offset }
        return candidates.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            if $0.posture != $1.posture { return $0.posture == .searchPounce }
            return (order[$0.band] ?? 0) < (order[$1.band] ?? 0)
        }
    }

    private static func candidates(
        _ input: Input, party: PartyDefinition, now: Date
    ) -> [Candidate] {
        let place = position(input)
        let daypart = place.map {
            SolarGeometry.daypart(latitude: $0.latitude, longitude: $0.longitude, date: now)
        }

        return party.validBands.flatMap { band -> [Candidate] in
            let onBand = input.spots.filter { $0.band == band }
            let needed = NeededMult.spots(
                onBand,
                currentMode: input.currentModeClass,
                followBandPlan: input.followsBandPlan,
                score: input.score,
                party: party,
                myLocation: input.myLocation
            )
            let weight = daypart.map {
                SolarGeometry.weight(band: band, daypart: $0)
                    * (input.spaceWeather?.modifier(band: band, now: now) ?? 1)
            } ?? 1

            return OperatingMode.allCases.map { posture in
                let own = ownRate(input, posture: posture, band: band, now: now)
                let value: Double
                switch posture {
                case .searchPounce:
                    // Observed evidence only. Those stations are demonstrably
                    // audible right now, so no propagation guess outranks
                    // them — spec §8's rule, in arithmetic.
                    let census = Double(onBand.count)
                        + input.goal.multWeight * Double(needed.count)
                    value = max(census, Double(own.rate ?? 0))
                case .run:
                    // Nobody has spotted the audience for a CQ, so this is the
                    // one candidate the sky gets a vote on.
                    let base = Double(own.rate ?? 0) > 0
                        ? Double(own.rate ?? 0)
                        : Double(onBand.count) * runAudience
                    value = base * weight
                        * (input.myLocation.isInState ? inStateRunFactor : 1)
                }
                return Candidate(
                    posture: posture, band: band, value: value,
                    workable: onBand.count, neededMults: needed.count,
                    ownRate: own.rate, ownMinutes: own.minutes,
                    weight: posture == .run ? weight : 1
                )
            }
        }
    }

    /// What this posture on this band has actually paid, from the operator's
    /// own posture-stamped rows.
    ///
    /// The **current** pair is measured to `now`, so a band that has gone
    /// quiet decays on its own — the failure that makes a rate meter worse
    /// than none. Every other pair is measured across the span it actually
    /// happened in, because "your 40 m run earlier: 31/hr" is a claim about
    /// then, not now.
    private static func ownRate(
        _ input: Input, posture: OperatingMode, band: Band, now: Date
    ) -> (rate: Int?, minutes: Int) {
        let stamps = input.recent
            .filter { $0.posture == posture && $0.band == band }
            .map(\.timestamp)
            .sorted()
        guard stamps.count >= minPostureSamples, let first = stamps.first,
              let last = stamps.last
        else { return (nil, 0) }

        let isCurrent = posture == input.mode && band == input.currentBand
        let end = isCurrent ? now : last
        let elapsed = end.timeIntervalSince(first)
        let minutes = elapsed / 60
        guard minutes >= minPostureMinutes else { return (nil, 0) }
        // n − 1 intervals, the same arithmetic `RateMeter` uses: ten QSOs a
        // minute apart is 60/hr, not 66.7.
        return (Int((Double(stamps.count - 1) * 3600 / elapsed).rounded()), Int(minutes))
    }

    private static func headline(
        for best: Candidate, input: Input, current: Candidate?
    ) -> String {
        let spots = "\(best.workable) workable spot\(best.workable == 1 ? "" : "s")"
        switch input.goal {
        case .score:
            var line = "\(best.label): \(spots)"
            if best.neededMults > 0 {
                line += ", \(best.neededMults) needed mult\(best.neededMults == 1 ? "" : "s")"
            }
            if let current, let lastTen = input.reading.lastTen {
                line += " — this \(current.band.rawValue) "
                    + "\(current.posture == .run ? "run" : "S&P"): \(lastTen)/hr last 10"
            }
            return line + "."
        case .qsos:
            var line = "\(best.label): \(spots)."
            if let rate = best.ownRate {
                line += " Your \(best.postureWord) there has given \(rate)/hr "
                    + "for \(best.ownMinutes) min."
            } else if let current, let lastTen = input.reading.lastTen {
                line += " This \(current.band.rawValue) "
                    + "\(current.posture == .run ? "run" : "S&P"): \(lastTen)/hr last 10."
            }
            return line
        }
    }

    private static func detail(
        for candidates: [Candidate], current: Candidate?, input: Input, now: Date
    ) -> String {
        var lines = ["Candidates, best first — goal: \(input.goal.label)."]
        for candidate in candidates.prefix(6) where candidate.value > 0 {
            var evidence: [String] = ["\(candidate.workable) workable"]
            if candidate.neededMults > 0 { evidence.append("\(candidate.neededMults) needed") }
            if let rate = candidate.ownRate {
                evidence.append("yours here \(rate)/hr over \(candidate.ownMinutes) min")
            }
            if candidate.posture == .run, candidate.weight != 1 {
                evidence.append(String(format: "band weight %.2f", candidate.weight))
            }
            lines.append("  \(candidate.label) — \(evidence.joined(separator: ", "))"
                + String(format: " (%.1f)", candidate.value))
        }
        if let current {
            lines.append(String(
                format: "Now: %@ (%.1f). A move needs %.1f× that.",
                current.label, current.value, bandMargin
            ))
        }
        if let sky = skyLine(input, now: now) { lines.append(sky) }
        lines.append("Nothing moves the radio but you. ⌘J returns to this run frequency.")
        return lines.joined(separator: "\n")
    }

    /// Where the sun is and what the ionosphere is doing, with every
    /// observation time named. `nil` without a grid square.
    private static func skyLine(_ input: Input, now: Date) -> String? {
        guard let place = position(input) else { return nil }
        let daypart = SolarGeometry.daypart(
            latitude: place.latitude, longitude: place.longitude, date: now
        )
        var line = "Sun: \(word(for: daypart)) at \(input.gridLocator ?? "your grid")"
        if let times = SolarGeometry.sunriseSunset(
            latitude: place.latitude, longitude: place.longitude, date: now
        ) {
            line += ", sunrise \(UTCTime.zulu(times.sunrise)), sunset \(UTCTime.zulu(times.sunset))"
        }
        line += ". Tendency, not measurement — spots outrank it."
        if let summary = input.spaceWeather?.summary(now: now) { line += " \(summary)." }
        return line
    }

    private static func word(for daypart: SolarGeometry.Daypart) -> String {
        switch daypart {
        case .day: "up"
        case .grayLine: "on the gray line"
        case .night: "down"
        }
    }

    /// The spot-free half of `moveCall`: the terminator moved, and the bands
    /// that usually take over are not the ones you are on.
    ///
    /// This is the whole strand for a NON-ASSISTED entry, and it fires exactly
    /// once per crossing — a sunset is an event, not a state to be reminded of
    /// every thirty seconds.
    private static func solarTransition(
        _ input: Input, party: PartyDefinition, state: inout State, now: Date
    ) -> [Advisory] {
        guard let place = position(input),
              let crossing = SolarGeometry.nearestCrossing(
                  latitude: place.latitude, longitude: place.longitude, date: now
              )
        else { return [] }

        // Just past a crossing, not approaching one: the advice is about what
        // has already changed under the operator.
        let since = now.timeIntervalSince(crossing.date)
        guard since >= 0, since <= SolarGeometry.grayLineWindow else { return [] }

        let key = "\(crossing.isSunrise ? "sunrise" : "sunset")"
            + "|\(Int(crossing.date.timeIntervalSince1970))"
        guard !state.announced.contains(key) else { return [] }

        let daypart = SolarGeometry.daypart(
            latitude: place.latitude, longitude: place.longitude, date: now
        )
        // Ordered by weight, then by the band table, so two bands that are
        // equally favoured always come out in the same order rather than in
        // whatever order the sort happened to leave them.
        let order = Band.allCases.enumerated()
            .reduce(into: [Band: Int]()) { $0[$1.element] = $1.offset }
        let taking = party.validBands
            .filter { $0 != input.currentBand }
            .sorted {
                let (left, right) = (weight($0, daypart: daypart, input: input, now: now),
                                     weight($1, daypart: daypart, input: input, now: now))
                if left != right { return left > right }
                return (order[$0] ?? 0) < (order[$1] ?? 0)
            }
            .prefix(2)
        guard !taking.isEmpty else { return [] }
        state.announced.insert(key)

        var headline = "\(crossing.isSunrise ? "Sunrise" : "Sunset") "
            + "was \(UTCTime.zulu(crossing.date)). "
            + "\(list(taking.map(\.rawValue))) usually take over from here."
        // Only the operator's own log can turn "usually" into "did".
        if let best = taking.compactMap({ band -> (Band, Int, OperatingMode)? in
            let run = ownRate(input, posture: .run, band: band, now: now)
            let sp = ownRate(input, posture: .searchPounce, band: band, now: now)
            if let rate = run.rate, rate >= (sp.rate ?? 0) { return (band, rate, .run) }
            if let rate = sp.rate { return (band, rate, .searchPounce) }
            return nil
        }).max(by: { $0.1 < $1.1 }) {
            headline += " Your \(best.0.rawValue) "
                + "\(best.2 == .run ? "run" : "S&P") earlier: \(best.1)/hr."
        }

        return [Advisory(
            id: "moveCall|solar|\(key)",
            kind: .moveCall,
            headline: headline,
            detail: (skyLine(input, now: now).map { $0 + "\n" } ?? "")
                + "Fired once at the crossing, not repeated. "
                + "Nothing moves the radio but you."
        )]
    }

    private static func weight(
        _ band: Band, daypart: SolarGeometry.Daypart, input: Input, now: Date
    ) -> Double {
        SolarGeometry.weight(band: band, daypart: daypart)
            * (input.spaceWeather?.modifier(band: band, now: now) ?? 1)
    }

    // MARK: 3 — unworked multipliers on the air right now

    private static func neededMults(_ input: Input, party: PartyDefinition) -> [Advisory] {
        let needed = NeededMult.spots(
            input.spots,
            currentMode: input.currentModeClass,
            followBandPlan: input.followsBandPlan,
            score: input.score,
            party: party,
            myLocation: input.myLocation
        )
        guard !needed.isEmpty else { return [] }

        let shown = needed.prefix(maxChips)
        let term = needed.count == 1 ? party.countyTerm : party.countyTermPlural
        var headline = "\(needed.count) needed \(term) on the air"
        if needed.count > shown.count {
            headline += " — \(shown.count) shown, +\(needed.count - shown.count) more"
        }

        return [Advisory(
            // Keyed on the counties themselves, so a new one arriving speaks
            // again even after the last set was waved off.
            id: "neededMultsSpotted|"
                + needed.compactMap { $0.county?.uppercased() }.sorted().joined(separator: ","),
            kind: .neededMultsSpotted,
            headline: headline + ".",
            detail: needed.map {
                "\($0.call) — \($0.county?.uppercased() ?? "?") on "
                    + "\(frequency($0.freqKHz)) (\($0.source.rawValue))"
            }.joined(separator: "\n")
                + "\nA chip tunes the radio and puts the call in the entry bar — "
                + "the same thing a band-map click does, and nothing more.",
            chips: shown.map {
                TuneChip(
                    label: "\($0.county?.uppercased() ?? $0.call) \(frequency($0.freqKHz))",
                    spot: $0
                )
            }
        )]
    }

    private static func frequency(_ kHz: Double) -> String {
        kHz == kHz.rounded() ? String(Int(kHz)) : String(format: "%.1f", kHz)
    }

    // MARK: 4 — the party's own prizes

    private static func bonusStanding(
        _ input: Input, party: PartyDefinition, now: Date
    ) -> [Advisory] {
        party.bonuses.compactMap { bonus -> Advisory? in
            guard case .workStation(let call, let points, let scope) = bonus else { return nil }
            let key = call.uppercased()
            let worked = input.bonusWorked[key] ?? []

            guard let standing = standing(
                call: key, points: points, scope: scope, worked: worked, party: party
            ) else { return nil }

            // If he is on the air right now, the frequency is the actionable
            // half of the sentence.
            let spot = input.spots.first { $0.call.uppercased() == key }
            return Advisory(
                id: "bonusStanding|\(key)|\(standing.stateKey)",
                kind: .bonusStanding,
                headline: standing.headline,
                detail: standing.detail
                    + (spot.map { "\nSpotted at \(frequency($0.freqKHz)) by \($0.spotter)." }
                        ?? "\nNot on the board right now."),
                chips: spot.map { [TuneChip(label: "\(key) \(frequency($0.freqKHz))", spot: $0)] }
                    ?? []
            )
        }
    }

    private static func standing(
        call: String, points: Int, scope: BonusRule.WorkStationScope,
        worked: Set<BonusSlot>, party: PartyDefinition
    ) -> (headline: String, detail: String, stateKey: String)? {
        switch scope {
        case .once:
            guard worked.isEmpty else { return nil }
            return ("Bonus \(call) not yet worked (+\(points)).",
                    "Pays +\(points) once, on any band and any mode.",
                    "unworked")

        case .perQSO:
            let count = worked.count
            return ("\(call) pays +\(points) every contact"
                        + (count > 0 ? " — \(count) so far." : "."),
                    "This bonus has no ceiling: every valid contact with \(call) pays again.",
                    "perQSO")

        case .perMode:
            let open = party.allowedModeClasses.filter { mode in
                !worked.contains { $0.modeClass == mode }
            }
            guard !open.isEmpty else { return nil }
            let done = party.allowedModeClasses.filter { mode in
                worked.contains { $0.modeClass == mode }
            }
            let headline = done.isEmpty
                ? "Bonus \(call) not yet worked (+\(points) per mode)."
                : "\(call) worked on \(list(done.map(\.displayName))) — "
                    + "\(list(open.map(\.displayName))) bonus open."
            return (headline,
                    "Pays +\(points) once per mode class.",
                    "perMode|" + open.map(\.rawValue).sorted().joined(separator: ","))

        case .perBandMode:
            let slots = party.validBands.flatMap { band in
                party.allowedModeClasses.map { BonusSlot(band: band, modeClass: $0) }
            }
            let open = slots.filter { !worked.contains($0) }
            guard !open.isEmpty else { return nil }
            let headline = worked.isEmpty
                ? "Bonus \(call) not yet worked (+\(points) per band per mode)."
                : "\(call) worked in \(worked.count) of \(slots.count) band/mode slots — "
                    + "\(open.count) still pay."
            return (headline,
                    "Pays +\(points) once per band per mode class.",
                    "perBandMode|\(open.count)")
        }
    }

    // MARK: 5 — the party's own clock

    private static func scheduleEdge(party: PartyDefinition, now: Date) -> [Advisory] {
        guard let schedule = party.schedule?.sorted(by: { $0.start < $1.start }),
              !schedule.isEmpty else { return [] }

        if let open = schedule.first(where: { $0.start <= now && now <= $0.end }) {
            let left = open.end.timeIntervalSince(now)
            guard left <= windowWarn else { return [] }
            return [Advisory(
                id: "scheduleEdge|closing|\(Int(open.end.timeIntervalSince1970))",
                kind: .scheduleEdge,
                headline: "\(UTCTime.minutes(left)) left in this window.",
                detail: "This operating window closes at \(UTCTime.zulu(open.end)). "
                    + "Contacts after it do not count."
            )]
        }

        guard let next = schedule.first(where: { $0.start > now }) else { return [] }
        let until = next.start.timeIntervalSince(now)
        guard until <= windowNextWithin else { return [] }
        return [Advisory(
            id: "scheduleEdge|opening|\(Int(next.start.timeIntervalSince1970))",
            kind: .scheduleEdge,
            headline: "Next window opens \(UTCTime.zulu(next.start)) (in \(UTCTime.span(until))).",
            detail: "The party is between operating windows. It runs "
                + "\(UTCTime.zulu(next.start)) to \(UTCTime.zulu(next.end))."
        )]
    }

    // MARK: Shared

    private static func position(_ input: Input) -> (latitude: Double, longitude: Double)? {
        input.gridLocator.flatMap { Maidenhead.center(of: $0) }
    }

    /// `40 m and 80 m`, `CW, SSB and RTTY` — an Oxford-free English list,
    /// because these read as sentences rather than as fields.
    private static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }
}
