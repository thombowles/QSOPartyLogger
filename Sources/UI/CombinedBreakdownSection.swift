import SwiftUI

/// Per-contest QSO counts for a combined entry — one line per sponsor sharing
/// the weekend, with the State QSO Party Challenge's two-QSO bar marked.
///
/// The combined log's own total answers "how did the weekend go". It cannot
/// answer "will Delaware count", and Delaware is three counties, so that is the
/// one you finish the weekend without. Shown live because the answer is only
/// useful while there is still time to act on it.
///
/// Driven entirely by `members`, which the caller resolves from `combines` —
/// nothing here knows a sponsor's name.
struct CombinedBreakdownSection: View {
    let log: ContestLog
    let party: PartyDefinition
    let members: [PartyDefinition]

    private var lines: [CombinedLogSplit.MemberLine] {
        CombinedLogSplit.split(log: log, combined: party, members: members)
    }

    var body: some View {
        if !lines.isEmpty {
            let qualified = lines.filter(\.qualifiesForChallenge).count
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("QSOs BY PARTY")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(qualified) of \(lines.count) qualified")
                        .font(.caption2)
                        .foregroundStyle(qualified == lines.count ? .green : .secondary)
                }

                ForEach(lines) { line in
                    row(line)
                }

                Text("The Challenge counts each party separately and needs two QSOs in each. Scores come from each sponsor — this entry cannot give you one.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ line: CombinedLogSplit.MemberLine) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: line.qualifiesForChallenge ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(line.qualifiesForChallenge ? .green : .orange)
                Text(line.party.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(line.validQSOs)")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 6) {
                Text("\(line.countiesWorked.count)/\(line.party.counties.count) counties")
                if !line.qualifiesForChallenge {
                    Text("· needs \(2 - line.validQSOs) more")
                        .foregroundStyle(.orange)
                }
                if line.ignored > 0 {
                    Text("· \(line.ignored) on a band or mode it doesn't run")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.leading, 18)
        }
        .help(helpText(line))
    }

    private func helpText(_ line: CombinedLogSplit.MemberLine) -> String {
        var text = "\(line.party.name): \(line.validQSOs) valid QSO"
            + (line.validQSOs == 1 ? "" : "s")
            + ", \(line.countiesWorked.count) of \(line.party.counties.count) counties."
        if !line.qualifiesForChallenge {
            text += " Two are needed before it counts as a Challenge multiplier."
        }
        if line.ignored > 0 {
            text += " \(line.ignored) logged contact"
                + (line.ignored == 1 ? " is" : "s are")
                + " on a band or mode this sponsor does not run, so it ignores "
                + (line.ignored == 1 ? "it." : "them.")
        }
        return text
    }
}
