import Foundation

/// The State QSO Party Challenge's approved-contest list and calendar for a
/// season, generated from the challenge's own publications by
/// `docs/research/gen_sqp_challenge.py` (never hand-typed). Bundled parties
/// keep their sponsor-verified schedules; these windows date only the
/// contests this app has no definition for.
struct ChallengeCalendar: Codable, Equatable, Sendable {

    struct Contest: Codable, Equatable, Sendable, Identifiable {
        let name: String
        /// Bundled party id when this contest is one of ours; nil otherwise.
        let partyID: String?
        let windows: [PartyDefinition.ScheduleWindow]

        var id: String { name }
    }

    let schemaVersion: Int
    let year: Int
    let source: String
    let approvedContests: [Contest]

    static func loadBundled(bundle: Bundle = .main, year: Int = 2026) -> ChallengeCalendar? {
        guard let url = bundle.url(
            forResource: "sqp_challenge_\(year)",
            withExtension: "json",
            subdirectory: "Challenge"
        ), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChallengeCalendar.self, from: data)
    }

    func contest(partyID: String) -> Contest? {
        approvedContests.first { $0.partyID == partyID }
    }

    func contest(named name: String) -> Contest? {
        approvedContests.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

extension Date {
    /// Calendar year in UTC — the year a contest belongs to.
    var utcYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.component(.year, from: self)
    }
}
