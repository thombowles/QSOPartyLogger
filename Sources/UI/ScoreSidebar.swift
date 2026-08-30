import AppKit
import SwiftUI

/// Running score, per-band QSO matrix, multiplier tracker, bonus status, and
/// (KSQP) 1x1 words. Spots live in the band map window (⌘B), not here.
struct ScoreSidebar: View {
    let log: ContestLog
    let party: PartyDefinition?
    let score: ScoreEngine.ScoreBreakdown
    /// The definitions of whatever `party` combines — empty for every ordinary
    /// party. Drives the per-contest QSO breakdown and the county grouping.
    var members: [PartyDefinition] = []
    /// Built with the evaluation's own `now` — see `AdvisorSection`. `nil`
    /// leaves the advisor out entirely, which is what the dashboard's
    /// read-only uses of this sidebar want.
    var advisorInput: ((Date) -> Advisor.Input)?
    var onTune: (Spot) -> Void = { _ in }
    /// Valid-QSO counts per band and mode, supplied by the window's
    /// `LiveScore` so this sidebar never folds the log itself. The
    /// dashboard's read-only uses leave it nil and compute as before.
    var bandModeCounts: [Band: [ModeClass: Int]]? = nil

    /// Which multiplier lists the operator has collapsed, remembered per party.
    @State private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                copyShortcut
                if let advisorInput {
                    AdvisorSection(input: advisorInput, onTune: onTune)
                }
                totalsCard
                // Data-driven, not contest-driven: any log activating a park
                // shows the panel — a QSO party worked from one included
                // (spec 2026-08-25 decision 2; one log, both submissions).
                if !log.myPotaRefs.isEmpty {
                    PotaActivationSection(log: log)
                }
                if let party {
                    CombinedBreakdownSection(log: log, party: party, members: members)
                    bandModeSection(party)
                    bonusSection(party)
                    multiplierSection(party)
                    oneByOneSection(party)
                }
            }
            .padding(12)
        }
        // Capped so a fresh launch can't hand the sidebar half the window —
        // the entry/log side holds layout priority and takes the slack. The
        // floor is 250 rather than 230 because the score card now carries two
        // columns of figures, and a rate the operator reads at a glance can
        // neither shrink nor truncate.
        .frame(minWidth: 250, idealWidth: 270, maxWidth: 400)
        .background(.background.secondary)
    }

    // MARK: QSOs by band/mode

    private func bandModeSection(_ party: PartyDefinition) -> some View {
        let counts = bandModeCounts ?? ScoreEngine.bandModeCounts(log: log, party: party)
        let modes = party.allowedModeClasses
        let bands = Band.allCases.filter { counts[$0] != nil }

        func bandTotal(_ band: Band) -> Int {
            counts[band]?.values.reduce(0, +) ?? 0
        }
        func modeTotal(_ mode: ModeClass) -> Int {
            bands.reduce(0) { $0 + (counts[$1]?[mode] ?? 0) }
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text("QSOs BY BAND")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if bands.isEmpty {
                Text("No contacts yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(modes, id: \.self) { mode in
                            Text(mode.shortLabel).foregroundStyle(.secondary)
                        }
                        Text("All").foregroundStyle(.secondary)
                    }
                    ForEach(bands, id: \.self) { band in
                        GridRow {
                            Text(band.rawValue).gridColumnAlignment(.leading)
                            ForEach(modes, id: \.self) { mode in
                                Text("\(counts[band]?[mode] ?? 0)")
                            }
                            Text("\(bandTotal(band))").fontWeight(.semibold)
                        }
                    }
                    if bands.count > 1 {
                        GridRow {
                            Text("All").fontWeight(.semibold).gridColumnAlignment(.leading)
                            ForEach(modes, id: \.self) { mode in
                                Text("\(modeTotal(mode))").fontWeight(.semibold)
                            }
                            Text("\(bands.reduce(0) { $0 + bandTotal($1) })").fontWeight(.bold)
                        }
                    }
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    private struct Figure {
        var label: String
        var value: String
        var tint: Color?
    }

    /// The score rows, in the order they are drawn. Category and dupes are
    /// conditional; the four above them never are, which is what lets the rate
    /// figures line up against them without any special-casing.
    private var scoreFigures: [Figure] {
        var figures = [
            Figure(label: "QSOs", value: "\(score.validQSOs)"),
            Figure(label: "Points", value: "\(score.qsoPoints)"),
            Figure(label: "Mults", value: "\(score.multiplierCount)"),
            Figure(label: "Bonus", value: "+\(score.bonusPoints)"),
        ]
        // A member party's summary email wants the three-way split ("Skeeter
        // QSOs - 23 / Non-Skeeter QRP QSOs - 5 / Non-Skeeter QRO QSOs"), so
        // the sidebar keeps it on screen. Appended after the fixed four so
        // the rate figures still line up against those.
        if let member = party?.memberExchange {
            // "Skeeters", not "Skeeter #" — this row counts stations, and the
            // short term beside a number reads as somebody's number.
            figures.append(Figure(label: member.memberPlural, value: "\(score.memberQSOs)"))
            figures.append(
                Figure(label: "QRP / QRO", value: "\(score.qrpQSOs) / \(score.otherQSOs)")
            )
        }
        if !score.categoryFactor.isOne {
            figures.append(Figure(label: "Category ×", value: score.categoryFactor.displayString))
        }
        if score.dupeCount > 0 {
            figures.append(
                Figure(label: "Dupes", value: "\(score.dupeCount)", tint: .orange)
            )
        }
        return figures
    }

    /// Timestamps of the rows the score counts. Dupes, wrong-mode and
    /// out-of-scope rows are not contest QSOs, so they are not rate either —
    /// and a county-line contact contributes all of its rows, because the
    /// `QSOs` figure beside it counts them that way.
    private var scoredTimestamps: [Date] {
        let excluded = score.dupeRowIDs
            .union(score.invalidRowIDs)
            .union(score.outOfScopeRowIDs)
        return log.qsos.filter { !excluded.contains($0.id) }.map(\.timestampUTC)
    }

    /// Score on the left, rate on the right.
    ///
    /// The tick is what makes the rate figures honest: without it every
    /// time-based window freezes between QSOs, and a run that died twenty
    /// minutes ago goes on reporting the rate it had when it was alive. 15
    /// seconds is finer than any figure's resolution, and only this card
    /// redraws — the rosters and county chips below are outside it.
    private var totalsCard: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            totalsGrid(
                rate: RateColumn.rows(
                    RateMeter.reading(timestamps: scoredTimestamps, now: context.date)
                )
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Copy Score Summary") { copySummary() }
        }
        .shortcutHint("⇧⌘C copy")
    }

    /// The keyboard half of the same action (⇧⌘C) — constitution rule 9.
    ///
    /// Zero-sized rather than a visible control in the SCORE heading row: that
    /// grid's four columns and their cell anchors are load-bearing, and a
    /// button dropped into it moves the rate column off the baselines the
    /// figures share.
    private var copyShortcut: some View {
        Button("Copy Score Summary") { copySummary() }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
    }

    /// The whole summary, not just the total: score components, the band matrix
    /// and — for a combined entry — the per-sponsor counts, which is what N1MM's
    /// "Copy all" means by all.
    private func copySummary() {
        let text = ScoreSummaryText.make(
            log: log, party: party, score: score, members: members
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// One `Grid`, not two stacks side by side: the rate rows have to sit on
    /// the same baselines as the score rows, and aligning independent stacks
    /// means hardcoding an offset for the 30pt total that breaks at any other
    /// font size. Four columns — label, value, label, value.
    private func totalsGrid(rate: [RateColumn.Row]) -> some View {
        let figures = scoreFigures
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                heading("SCORE").gridCellColumns(2)
            }
            GridRow {
                Text("\(score.total.formatted())")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .gridCellColumns(2)
                // Alongside SCORE this sat a whole 30pt total above the
                // figures it names, reading as a heading for the card rather
                // than for the column. Anchored to the bottom of the total's
                // row it lands directly on top of them.
                heading("RATE")
                    .padding(.leading, gutter)
                    .gridCellAnchor(.bottomLeading)
                heading("/hr")
                    .gridCellAnchor(.bottomTrailing)
            }
            ForEach(0..<max(figures.count, rate.count), id: \.self) { index in
                GridRow {
                    let figure = figures.indices.contains(index) ? figures[index] : nil
                    Text(figure?.label ?? "")
                        .foregroundStyle(figure?.tint ?? .primary)
                    Text(figure?.value ?? "")
                        .foregroundStyle(figure?.tint ?? .primary)
                        .gridColumnAlignment(.trailing)

                    let row = rate.indices.contains(index) ? rate[index] : nil
                    Text(row?.label ?? "")
                        .foregroundStyle(.secondary)
                        .padding(.leading, gutter)
                        .help(row?.help ?? "")
                    Text(row?.value ?? "")
                        .gridColumnAlignment(.trailing)
                        .help(row?.help ?? "")
                }
            }
        }
        .font(.callout.monospacedDigit())
    }

    /// Keeps the two halves of the card from reading as one run of columns.
    private let gutter: CGFloat = 10

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func bonusSection(_ party: PartyDefinition) -> some View {
        if !party.bonuses.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("BONUS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(Array(party.bonuses.enumerated()), id: \.offset) { _, bonus in
                    switch bonus {
                    case .workStation(let call, let points, let scope):
                        let worked = log.qsos.contains { $0.call.uppercased() == call.uppercased() }
                        Label(
                            "\(call) +\(points)\(scopeLabel(scope))",
                            systemImage: worked ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(worked ? .green : .secondary)
                    case .mobileCountyCount(let per, let points):
                        Label(
                            "+\(points) per \(per) counties/mobile",
                            systemImage: score.bonusPoints > 0 ? "car.fill" : "car"
                        )
                        .foregroundStyle(score.bonusPoints > 0 ? .green : .secondary)
                    case .activatedCountyCount(let minQSOs, let points):
                        Label(
                            "+\(points) per county activated (\(minQSOs)+ QSOs)",
                            systemImage: "flag.checkered"
                        )
                        .foregroundStyle(.secondary)
                    case .sweepTiers(let tiers):
                        let worked = score.workedValues(.county).count
                        ForEach(Array(tiers.enumerated()), id: \.offset) { _, tier in
                            Label(
                                "+\(tier.points) at \(tier.count) jurisdictions (\(worked)/\(tier.count))",
                                systemImage: worked >= tier.count ? "checkmark.seal.fill" : "seal"
                            )
                            .foregroundStyle(worked >= tier.count ? .green : .secondary)
                        }
                    case .designatedCountySweep(let counties, let need, let points):
                        // Counted through the engine's own predicate, so the
                        // progress shown is the set the bonus is paid on.
                        let worked = ScoreEngine
                            .designatedCountiesWorked(counties, log: log, party: party).count
                        Label(
                            "+\(points) at \(need) of \(counties.count) designated"
                                + " (\(worked)/\(need))",
                            systemImage: worked >= need ? "checkmark.seal.fill" : "seal"
                        )
                        .foregroundStyle(worked >= need ? .green : .secondary)
                    case .callAreaSum(let target, let points):
                        // The engine's own predicate again — the badge flips
                        // exactly when the score pays. The sponsor requires
                        // listing the qualifying calls in the summary email;
                        // picking them stays the operator's job.
                        let achieved = ScoreEngine.callAreaSumAchieved(
                            target: target, log: log, party: party)
                        Label(
                            "+\(points) when call areas sum to exactly \(target)",
                            systemImage: achieved ? "checkmark.seal.fill" : "seal"
                        )
                        .foregroundStyle(achieved ? .green : .secondary)
                    }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func multiplierSection(_ party: PartyDefinition) -> some View {
        let rule = log.myLocation.isInState ? party.multipliers.inState : party.multipliers.outState
        let rosters = MultiplierRoster.classes(party: party, rule: rule)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("MULTIPLIERS — \(score.multiplierCount)\(scopeSuffix(rule.countScope))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    toggleAllSections(party, rosters: rosters)
                } label: {
                    Image(systemName: allCollapsed(party, rosters: rosters)
                          ? "chevron.down.square" : "chevron.up.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Expand or collapse every multiplier list (⇧⌘M)")
                .shortcutHint("⇧⌘M")
            }

            // Every class the party counts, drawn whole — worked and still
            // needed — because a tracker that shows only what is done cannot
            // answer the question the operator is actually asking.
            ForEach(rosters) { roster in
                rosterSection(roster, party: party)
            }

            // DX has no roster to draw: under prefix style any plausible
            // prefix is a multiplier, so worked tokens are all there is.
            if rule.classes.contains(.dx) {
                let worked = score.workedValues(.dx)
                if !worked.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DX (\(score.classCounts[.dx] ?? 0))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(worked.sorted().joined(separator: " "))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: One roster

    @ViewBuilder
    private func rosterSection(
        _ roster: MultiplierRoster.ClassRoster, party: PartyDefinition
    ) -> some View {
        let key = sectionKey(party, roster.multClass)
        let isCollapsed = settings.collapsedMultSections.contains(key)
        let worked = workedTokens(roster)

        VStack(alignment: .leading, spacing: 3) {
            Button {
                toggleSection(key)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8))
                    Text(rosterTitle(roster, party: party))
                    Spacer(minLength: 4)
                    Text(rosterCounts(roster, worked: worked))
                        .monospacedDigit()
                        .foregroundStyle(
                            worked.count == roster.entries.count ? .green : .secondary
                        )
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if roster.multClass == .county {
                    // Counties keep their by-contest, by-state grouping — a
                    // combined log's 300 counties are unreadable as one grid.
                    countyGroups(roster, party: party, worked: worked)
                } else {
                    chips(roster, entries: roster.entries, worked: worked)
                }
            }
        }
    }

    private func rosterTitle(
        _ roster: MultiplierRoster.ClassRoster, party: PartyDefinition
    ) -> String {
        let name = label(for: roster.multClass, party: party)
        return roster.isMultClass ? name : "\(name) (award tracking)"
    }

    /// `12/51 · 34/306` — multipliers touched, then band/mode slots filled.
    /// The second figure is dropped where a multiplier counts only once, since
    /// it would repeat the first.
    private func rosterCounts(
        _ roster: MultiplierRoster.ClassRoster, worked: Set<String>
    ) -> String {
        let head = "\(worked.count)/\(roster.entries.count)"
        guard roster.slots.count > 1 else { return head }
        let filled = roster.entries.reduce(0) {
            $0 + MultiplierRoster.workedSlots($1, in: roster, score: score).count
        }
        return "\(head) · \(filled)/\(roster.entries.count * roster.slots.count)"
    }

    /// Tokens with at least one slot held. A roster the party does not score
    /// has no multiplier keys to read, so it comes from the log instead.
    private func workedTokens(_ roster: MultiplierRoster.ClassRoster) -> Set<String> {
        guard roster.isMultClass else {
            return MultiplierRoster.awardWorkedTokens(log: log, roster: roster)
        }
        return Set(
            roster.entries
                .filter { !MultiplierRoster.workedSlots($0, in: roster, score: score).isEmpty }
                .map(\.token)
        )
    }

    private func sectionKey(_ party: PartyDefinition, _ multClass: MultClass) -> String {
        "\(party.id).\(multClass.rawValue)"
    }

    private func toggleSection(_ key: String) {
        if settings.collapsedMultSections.contains(key) {
            settings.collapsedMultSections.remove(key)
        } else {
            settings.collapsedMultSections.insert(key)
        }
    }

    private func allCollapsed(
        _ party: PartyDefinition, rosters: [MultiplierRoster.ClassRoster]
    ) -> Bool {
        !rosters.isEmpty && rosters.allSatisfy {
            settings.collapsedMultSections.contains(sectionKey(party, $0.multClass))
        }
    }

    private func toggleAllSections(
        _ party: PartyDefinition, rosters: [MultiplierRoster.ClassRoster]
    ) {
        let keys = rosters.map { sectionKey(party, $0.multClass) }
        if allCollapsed(party, rosters: rosters) {
            settings.collapsedMultSections.subtract(keys)
        } else {
            settings.collapsedMultSections.formUnion(keys)
        }
    }

    private func scopeLabel(_ scope: BonusRule.WorkStationScope) -> String {
        switch scope {
        case .once: ""
        case .perMode: "/mode"
        case .perBandMode: "/band/mode"
        case .perQSO: "/QSO"
        }
    }

    private func scopeSuffix(_ scope: PartyDefinition.CountScope) -> String {
        switch scope {
        case .once: ""
        case .perMode: " (per mode)"
        case .perBand: " (per band)"
        case .perBandMode: " (per band/mode)"
        }
    }

    /// The county class is named by the party — its slot holds whatever the
    /// sponsor enumerates, which is not always a county.
    private func label(for multClass: MultClass, party: PartyDefinition) -> String {
        switch multClass {
        case .county: party.countyTermPlural.sentenceCased
        case .state: "States"
        case .province: "Provinces"
        case .section: "Sections"
        case .dx: "DX"
        // A member party names its own members ("Bumblebees"); the fallback
        // is never reached by a bundled party, since the class only counts
        // where a member exchange exists.
        case .member: party.memberExchange?.memberPlural ?? "Members"
        }
    }

    /// Counties by member contest, then by state. A single-state party that
    /// combines nothing comes back as one unnamed, single-state group, which
    /// draws exactly the grid it always has.
    private func countyGroups(
        _ roster: MultiplierRoster.ClassRoster, party: PartyDefinition, worked: Set<String>
    ) -> some View {
        let byAbbr = Dictionary(
            roster.entries.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return ForEach(CountyGrouping.groups(for: party, members: members)) { group in
            VStack(alignment: .leading, spacing: 3) {
                if let name = group.partyName {
                    heading(name, worked: worked, of: group.counties, weight: .bold)
                        .padding(.top, 2)
                }
                ForEach(group.states) { state in
                    // A single-state group is already named by the heading
                    // above it — "Delaware QSO Party" then "DE 1/3" is the
                    // same fact twice — and for an ordinary party the
                    // "Counties 12/105" line above says it.
                    if !group.isSingleState {
                        heading(state.state, worked: worked, of: state.counties, weight: .semibold)
                            .padding(.leading, 4)
                    }
                    chips(
                        roster,
                        entries: state.counties.compactMap { byAbbr[$0.abbr] },
                        worked: worked
                    )
                }
            }
        }
    }

    private func heading(
        _ text: String, worked: Set<String>, of counties: [County], weight: Font.Weight
    ) -> some View {
        let hit = counties.filter { worked.contains($0.abbr) }.count
        return HStack(spacing: 4) {
            Text(text)
            Spacer(minLength: 4)
            Text("\(hit)/\(counties.count)")
                .monospacedDigit()
                .foregroundStyle(hit == counties.count ? .green : .secondary)
        }
        .font(.caption2.weight(weight))
        .foregroundStyle(.secondary)
    }

    /// One chip per multiplier. Where the party counts a multiplier more than
    /// once — per band, per mode — the chip carries a strip of blocks below
    /// it, one per band, filled as that band is worked. N1MM's Multipliers
    /// window in a 270pt column.
    private func chips(
        _ roster: MultiplierRoster.ClassRoster,
        entries: [MultiplierRoster.Entry],
        worked: Set<String>
    ) -> some View {
        let columns = roster.columns
        let perBand = columns.count > 1
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: perBand ? 46 : 40), spacing: 3)], spacing: 3
        ) {
            ForEach(entries) { entry in
                // An award-tracking list holds no multiplier keys, so its
                // worked set is the one already derived from the log.
                let held = roster.isMultClass
                    ? MultiplierRoster.workedSlots(entry, in: roster, score: score)
                    : (worked.contains(entry.token) ? [""] : [])
                VStack(spacing: 1) {
                    Text(entry.token)
                        .font(.system(size: 9, design: .monospaced).weight(.medium))
                        .frame(maxWidth: .infinity)
                    if perBand {
                        HStack(spacing: 1) {
                            ForEach(columns) { column in
                                let hit = column.slots.filter { held.contains($0.scope) }.count
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(blockFill(hit: hit, of: column.slots.count))
                                    .frame(height: 3)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.vertical, 2)
                .background(
                    chipFill(held: held.count, of: roster.slots.count),
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .help(chipHelp(entry, roster: roster, held: held))
            }
        }
    }

    /// Grey when nothing is worked, full green when every band is, and a
    /// half-tint in between — so a chip never reads "done" while multipliers
    /// remain on it, which is the whole failure of a worked-only list.
    private func chipFill(held: Int, of total: Int) -> Color {
        if held == 0 { return Color.gray.opacity(0.12) }
        return held >= total ? Color.green.opacity(0.35) : Color.green.opacity(0.16)
    }

    private func blockFill(hit: Int, of total: Int) -> Color {
        if hit == 0 { return Color.gray.opacity(0.25) }
        return hit >= total ? Color.green : Color.green.opacity(0.5)
    }

    private func chipHelp(
        _ entry: MultiplierRoster.Entry,
        roster: MultiplierRoster.ClassRoster,
        held: Set<String>
    ) -> String {
        var parts: [String] = []
        if let name = entry.name { parts.append(name) }
        if entry.granted {
            parts.append("credited by the rules — nothing to work")
        } else if roster.slots.count > 1 {
            let needed = roster.slots.filter { !held.contains($0.scope) }
            parts.append(needed.isEmpty
                ? "worked on every band"
                : "still needed: " + needed.map(\.scope).joined(separator: ", "))
        } else {
            parts.append(held.isEmpty ? "not yet worked" : "worked")
        }
        return parts.joined(separator: " — ")
    }

    @ViewBuilder
    private func oneByOneSection(_ party: PartyDefinition) -> some View {
        if let config = party.oneByOne {
            let progress = OneByOneTracker.progress(calls: log.qsos.map(\.call), config: config)
            VStack(alignment: .leading, spacing: 6) {
                Text("1×1 WORDS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(progress, id: \.word) { wordProgress in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 1.5) {
                            ForEach(Array(wordProgress.word.enumerated()), id: \.offset) { i, letter in
                                Text(String(letter))
                                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                                    .frame(width: 13, height: 15)
                                    .background(
                                        wordProgress.assignments[i] != nil
                                            ? Color.green.opacity(0.4)
                                            : Color.gray.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 2)
                                    )
                                    .help(wordProgress.assignments[i] ?? "needed")
                            }
                            if wordProgress.complete {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
    }
}
