import SwiftUI

/// State QSO Party Challenge standing: the sponsor's formula shown working,
/// the award-level ladder, and per-party qualification. Only contests the
/// Challenge counts appear — what it won't count (POTA, an unapproved
/// party) is not this card's business and lives in the season's own
/// widgets and tables (Tom, 2026-08-26; previously shown greyed).
struct DashboardChallengeSection: View {
    let standing: ChallengeStanding
    /// Set when a combined entry was split into its member contests to build
    /// this standing, so four lines the operator never opened separately are
    /// explained rather than left to be discovered.
    var includesSplitEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("State QSO Party Challenge", systemImage: "rosette")
                    .font(.title3.weight(.semibold))
                Text(String(standing.year))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("estimate — official score comes from your 3830scores.com submissions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                formulaAndLevels
                Divider()
                partyLines
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Score + ladder

    private var formulaAndLevels: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(DashboardFormat.points(standing.points))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("points")
                    .foregroundStyle(.secondary)
                if let level = standing.level {
                    LevelBadge(name: level.name, achieved: true)
                }
            }

            Text("\(DashboardFormat.points(standing.qsoSum)) QSOs × \(standing.multiplier) parties")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)

            if !standing.qualifiedForAwards {
                Label(
                    "Awards need two parties with at least two QSOs each.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            ladder

            if let next = standing.nextLevel {
                Text(progressText(to: next))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Diamond — the top of the ladder. Congratulations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Season: Feb 1 – Nov 30 · report each party to 3830scores.com")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 320, alignment: .leading)
    }

    private var ladder: some View {
        HStack(spacing: 6) {
            ForEach(ChallengeStanding.awardLevels, id: \.name) { level in
                LevelBadge(
                    name: "\(level.name) \(DashboardFormat.points(level.points))",
                    achieved: standing.qualifiedForAwards && standing.points >= level.points
                )
            }
        }
    }

    private func progressText(to next: ChallengeStanding.AwardLevel) -> String {
        let needed = next.points - standing.points
        var text = "\(DashboardFormat.points(needed)) points to \(next.name)"
        if standing.multiplier > 0 {
            // With the multiplier fixed, points come QSOs-at-a-time.
            let qsos = (needed + standing.multiplier - 1) / standing.multiplier
            text += " (≈ \(DashboardFormat.points(qsos)) more QSOs at ×\(standing.multiplier))"
        }
        return text
    }

    // MARK: Per-party lines

    private var partyLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Parties entered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if standing.lines.isEmpty {
                Text("None yet this season.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if includesSplitEntry {
                Text("A combined entry is listed as the contests it is made of — the Challenge counts each sponsor separately, and each takes its own log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(standing.lines) { line in
                HStack(spacing: 8) {
                    Image(systemName: line.qualifies ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(line.qualifies ? .green : .orange)
                    Text(line.contestName)
                    Spacer()
                    Text("\(line.validQSOs) QSOs")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if !line.qualifies {
                        Text("1 more QSO to count")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LevelBadge: View {
    let name: String
    let achieved: Bool

    var body: some View {
        Text(name)
            .font(.caption.weight(achieved ? .bold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                achieved ? AnyShapeStyle(.yellow.opacity(0.35)) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
    }
}
