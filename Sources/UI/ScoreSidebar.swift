import SwiftUI

/// Running score, multiplier tracker, bonus status, and (KSQP) 1x1 words.
struct ScoreSidebar: View {
    let log: ContestLog
    let party: PartyDefinition?
    let score: ScoreEngine.ScoreBreakdown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                totalsCard
                if let party {
                    bonusSection(party)
                    multiplierSection(party)
                    oneByOneSection(party)
                }
            }
            .padding(12)
        }
        .frame(minWidth: 230, idealWidth: 260)
        .background(.background.secondary)
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
                    case .workStation(let call, let points):
                        let worked = log.qsos.contains { $0.call.uppercased() == call.uppercased() }
                        Label(
                            "\(call) +\(points)",
                            systemImage: worked ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(worked ? .green : .secondary)
                    case .mobileCountyCount(let per, let points):
                        Label(
                            "+\(points) per \(per) counties/mobile",
                            systemImage: score.bonusPoints > 0 ? "car.fill" : "car"
                        )
                        .foregroundStyle(score.bonusPoints > 0 ? .green : .secondary)
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
            Text("MULTIPLIERS — \(score.multiplierCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if rule.classes.contains(.county) {
                countyGrid(party)
            }
            ForEach(nonCountyClasses(rule), id: \.self) { multClass in
                let values = score.multipliers[multClass, default: []]
                if !values.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(for: multClass) + " (\(values.count))")
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
        case .dx: "DX"
        }
    }

    private func countyGrid(_ party: PartyDefinition) -> some View {
        let worked = score.multipliers[.county, default: []]
        let columns = [GridItem(.adaptive(minimum: 40), spacing: 3)]
        return VStack(alignment: .leading, spacing: 3) {
            Text("Counties \(worked.count)/\(party.counties.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(party.counties) { county in
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
