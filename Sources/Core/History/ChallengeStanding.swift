import Foundation

/// Estimated State QSO Party Challenge standing for one season, computed by
/// the sponsor's published formula (docs/research/sqp_challenge_rules.md).
/// An estimate by construction: the official score is what 3830scores.com
/// computes from actual submissions.
struct ChallengeStanding: Equatable, Sendable {

    struct AwardLevel: Equatable, Sendable {
        let name: String
        let points: Int
    }

    /// One approved (or logged-but-not-approved) party's contribution.
    struct PartyLine: Equatable, Sendable, Identifiable {
        let partyID: String
        let contestName: String
        let validQSOs: Int
        /// "Entrants must make at least two contacts in a QSO party for it
        /// to count as a multiplier."
        let qualifies: Bool

        var id: String { partyID }
    }

    /// "Diamond 100,000 | Platinum 25,000 | Gold 10,000 | Silver 5,000 |
    /// Bronze 500" — ascending here for progress math.
    static let awardLevels: [AwardLevel] = [
        AwardLevel(name: "Bronze", points: 500),
        AwardLevel(name: "Silver", points: 5_000),
        AwardLevel(name: "Gold", points: 10_000),
        AwardLevel(name: "Platinum", points: 25_000),
        AwardLevel(name: "Diamond", points: 100_000),
    ]

    let year: Int
    let lines: [PartyLine]
    /// Logged parties not on the approved list (MEQP in 2026) — shown, never
    /// silently dropped, contributing nothing.
    let notApproved: [PartyLine]
    /// Σ valid QSOs over approved parties — including sub-2-QSO entries,
    /// whose QSOs sum even though they don't multiply (PDF formula counts
    /// QSOs and submissions separately).
    let qsoSum: Int
    /// Approved parties with ≥ 2 valid QSOs.
    let multiplier: Int

    var points: Int { qsoSum * multiplier }

    /// "the participant must have participated in at least two state QSO
    /// party contest. Each ... entry must include at least TWO valid QSOs."
    var qualifiedForAwards: Bool { multiplier >= 2 }

    var level: AwardLevel? {
        guard qualifiedForAwards else { return nil }
        return Self.awardLevels.last { points >= $0.points }
    }

    var nextLevel: AwardLevel? {
        Self.awardLevels.first { points < $0.points }
    }

    /// Aggregates the year's records by party. Records under different
    /// callsigns fold together — the challenge itself is per callsign on
    /// 3830scores, but this dashboard tracks one operator's season.
    /// `partyNames` (party id → display name) lets a user-installed party
    /// match an approved contest by name when the generated mapping doesn't
    /// know its id.
    static func compute(
        records: [ContestRecord],
        calendar: ChallengeCalendar,
        year: Int,
        partyNames: [String: String] = [:]
    ) -> ChallengeStanding {
        var qsosByParty: [String: Int] = [:]
        for record in records where record.year == year {
            qsosByParty[record.partyID, default: 0] += record.snapshot.validQSOs
        }

        var lines: [PartyLine] = []
        var notApproved: [PartyLine] = []
        for (partyID, qsos) in qsosByParty {
            let contest = calendar.contest(partyID: partyID)
                ?? partyNames[partyID].flatMap { calendar.contest(named: $0) }
            if let contest {
                lines.append(PartyLine(
                    partyID: partyID,
                    contestName: contest.name,
                    validQSOs: qsos,
                    qualifies: qsos >= 2
                ))
            } else {
                notApproved.append(PartyLine(
                    partyID: partyID,
                    contestName: partyNames[partyID] ?? partyID.uppercased(),
                    validQSOs: qsos,
                    qualifies: false
                ))
            }
        }
        lines.sort { $0.contestName < $1.contestName }
        notApproved.sort { $0.contestName < $1.contestName }

        return ChallengeStanding(
            year: year,
            lines: lines,
            notApproved: notApproved,
            qsoSum: lines.reduce(0) { $0 + $1.validQSOs },
            multiplier: lines.filter(\.qualifies).count
        )
    }
}
