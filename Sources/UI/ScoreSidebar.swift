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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                totalsCard
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
        // the entry/log side holds layout priority and takes the slack.
        .frame(minWidth: 230, idealWidth: 270, maxWidth: 400)
        .background(.background.secondary)
    }

    // MARK: QSOs by band/mode

    private func bandModeSection(_ party: PartyDefinition) -> some View {
        let counts = ScoreEngine.bandModeCounts(log: log, party: party)
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
                            Text(shortLabel(mode)).foregroundStyle(.secondary)
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

    private func shortLabel(_ mode: ModeClass) -> String {
        switch mode {
        case .cw: "CW"
        case .phone: "PH"
        case .digital: "DIG"
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCORE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("\(score.total.formatted())")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("QSOs")
                    Text("\(score.validQSOs)").gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("Points")
                    Text("\(score.qsoPoints)")
                }
                GridRow {
                    Text("Mults")
                    Text("\(score.multiplierCount)")
                }
                GridRow {
                    Text("Bonus")
                    Text("+\(score.bonusPoints)")
                }
                if score.categoryFactor != 1 {
                    GridRow {
                        Text("Category ×")
                        Text("\(score.categoryFactor)")
                    }
                }
                if score.dupeCount > 0 {
                    GridRow {
                        Text("Dupes").foregroundStyle(.orange)
                        Text("\(score.dupeCount)").foregroundStyle(.orange)
                    }
                }
            }
            .font(.callout.monospacedDigit())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
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
                    }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func multiplierSection(_ party: PartyDefinition) -> some View {
        let rule = log.myLocation.isInState ? party.multipliers.inState : party.multipliers.outState

        VStack(alignment: .leading, spacing: 6) {
            Text("MULTIPLIERS — \(score.multiplierCount)\(scopeSuffix(rule.countScope))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            // Always show the county grid: when counties aren't a multiplier
            // class (e.g. KSQP in-state), they still matter for county-sweep
            // awards like Worked All Kansas.
            countyGrid(party, isMultClass: rule.classes.contains(.county))
            ForEach(nonCountyClasses(rule), id: \.self) { multClass in
                let values = score.workedValues(multClass)
                if !values.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(for: multClass) + " (\(score.classCounts[multClass] ?? 0))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(values.sorted().joined(separator: " "))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
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

    private func nonCountyClasses(_ rule: PartyDefinition.MultRule) -> [MultClass] {
        var classes = rule.classes.filter { $0 != .county }
        if rule.homeStateCountsViaCounty && !classes.contains(.state) {
            classes.append(.state)
        }
        return classes
    }

    private func label(for multClass: MultClass) -> String {
        switch multClass {
        case .county: "Counties"
        case .state: "States"
        case .province: "Provinces"
        case .section: "Sections"
        case .dx: "DX"
        }
    }

    private func countyGrid(_ party: PartyDefinition, isMultClass: Bool) -> some View {
        // When counties don't score as mults, derive worked-county tracking
        // straight from the log.
        let worked: Set<String> = isMultClass
            ? score.workedValues(.county)
            : {
                let abbrs = Set(party.counties.map(\.abbr))
                return Set(log.qsos.map { $0.theirLoc.uppercased() }).intersection(abbrs)
            }()
        // By member contest, then by state. A single-state party that combines
        // nothing comes back as one unnamed, single-state group, which draws
        // exactly the grid it always has.
        let groups = CountyGrouping.groups(for: party, members: members)

        return VStack(alignment: .leading, spacing: 3) {
            Text("Counties \(worked.count)/\(party.counties.count)\(isMultClass ? "" : " (award tracking)")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(groups) { group in
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
                        chips(state.counties, worked: worked)
                    }
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

    private func chips(_ counties: [County], worked: Set<String>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 3)], spacing: 3) {
            ForEach(counties) { county in
                Text(county.abbr)
                    .font(.system(size: 9, design: .monospaced).weight(.medium))
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background(
                        worked.contains(county.abbr) ? Color.green.opacity(0.35) : Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                    .help(county.name)
            }
        }
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
