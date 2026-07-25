import Foundation

/// One row of the dashboard's upcoming list.
struct UpcomingContest: Equatable, Sendable, Identifiable {
    enum DateSource: Equatable, Sendable {
        /// Sponsor-verified `PartyDefinition.schedule` — always wins.
        case partyDefinition
        /// The challenge's calendar (display data for contests this app has
        /// no definition for; the UI labels it).
        case challengeCalendar
    }

    let name: String
    let partyID: String?
    let windows: [PartyDefinition.ScheduleWindow]
    let nextWindow: PartyDefinition.ScheduleWindow
    let isLive: Bool
    let dateSource: DateSource
    let isApproved: Bool
    let enteredThisYear: Bool

    var id: String { name }
}

enum UpcomingContests {
    /// Remaining contests as of `now`, soonest next-window first. Installed
    /// parties (bundled or user) supply their own schedules; calendar rows
    /// cover the rest, deduplicated by contest name — so the calendar's
    /// known-wrong NJQP date can never shadow the sponsor's.
    static func upcoming(
        now: Date,
        parties: [PartyDefinition],
        calendar: ChallengeCalendar?,
        records: [ContestRecord]
    ) -> [UpcomingContest] {
        var claimedNames = Set<String>()
        var out: [UpcomingContest] = []
        let enteredKeys = Set(records.map { "\($0.partyID)|\($0.year)" })

        for party in parties {
            guard let schedule = party.schedule, !schedule.isEmpty else { continue }
            // A party with a definition owns its name outright: even when its
            // windows have all passed, the calendar must not resurrect it.
            claimedNames.insert(party.name.lowercased())
            let windows = schedule.sorted { $0.start < $1.start }
            guard let next = windows.first(where: { $0.end > now }) else { continue }
            let isApproved = calendar.map {
                $0.contest(partyID: party.id) != nil || $0.contest(named: party.name) != nil
            } ?? false
            out.append(UpcomingContest(
                name: party.name,
                partyID: party.id,
                windows: windows,
                nextWindow: next,
                isLive: next.start <= now,
                dateSource: .partyDefinition,
                isApproved: isApproved,
                enteredThisYear: enteredKeys.contains("\(party.id)|\(next.start.utcYear)")
            ))
        }

        for contest in calendar?.approvedContests ?? []
        where !claimedNames.contains(contest.name.lowercased()) {
            guard let next = contest.windows.first(where: { $0.end > now }) else { continue }
            out.append(UpcomingContest(
                name: contest.name,
                partyID: nil,
                windows: contest.windows,
                nextWindow: next,
                isLive: next.start <= now,
                dateSource: .challengeCalendar,
                isApproved: true,
                enteredThisYear: false
            ))
        }

        return out.sorted {
            if $0.nextWindow.start != $1.nextWindow.start {
                return $0.nextWindow.start < $1.nextWindow.start
            }
            return $0.name < $1.name
        }
    }
}
