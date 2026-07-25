import SwiftUI

/// What's next on the calendar: live contests first, then everything left
/// this season — sponsor-dated where a definition is installed, challenge-
/// calendar-dated (and labeled) where not.
struct DashboardUpcomingSection: View {
    @Bindable var model: DashboardModel

    private static let visibleCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Upcoming", systemImage: "calendar")
                .font(.title3.weight(.semibold))

            let upcoming = model.upcoming
            if upcoming.isEmpty {
                Text("The season is over — no state QSO parties left this year. See you February 1st.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming.prefix(Self.visibleCount)) { contest in
                    row(contest)
                }
                if upcoming.count > Self.visibleCount {
                    Text("…and \(upcoming.count - Self.visibleCount) more this season.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ contest: UpcomingContest) -> some View {
        HStack(spacing: 10) {
            if contest.isLive {
                Text("ON AIR")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
            } else {
                Text(DashboardFormat.countdown(to: contest.nextWindow.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
            }

            Text(contest.name)
                .fontWeight(contest.isLive ? .semibold : .regular)

            if contest.enteredThisYear {
                Label("entered", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }

            if contest.partyID == nil {
                Text("no rules installed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(contest.windows.map(DashboardFormat.window).joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if contest.dateSource == .challengeCalendar {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.tertiary)
                    .help(
                        "Dates from the SQP Challenge calendar — this app has no rules file " +
                        "for this party, so verify with the sponsor before operating."
                    )
            }
        }
        .font(.callout)
    }
}
