import Foundation

/// The super check strip's one ranking, over its two sources: the MASTER.SCP
/// database and the active party's N1MM call history file — for the Skeeter
/// Hunt, the roster of Skeeter numbers.
///
/// N1MM's Check window draws from both (and the log, and telnet spots) in
/// separate panes. This app has one line, so the history's calls join the
/// database's *marked* (`Match.inHistory`), and rank first inside each tier:
/// a roster call is the one most likely to be on the air in this party, and
/// the one the eye is looking for (2026-08-16).
///
/// **Hint data, never authority** (constitution Article 1), like both of its
/// sources: nothing here reaches scoring, validation, or export.
enum SuperCheck {
    /// One call the strip shows, and whether the party's history file has it.
    struct Match: Equatable, Hashable, Sendable {
        let call: String
        let inHistory: Bool
    }

    /// What the strip shows: the capped, ranked list plus the honest counts,
    /// so the view can say "SCP 12 · HIST 3" and "+N more" truthfully.
    struct Matches: Equatable, Sendable {
        let calls: [Match]
        /// Every match, both sources together, a call in both counted once.
        let total: Int
        /// Matches the database has.
        let scpTotal: Int
        /// Matches the history file has.
        let historyTotal: Int
        static let none = Matches(calls: [], total: 0, scpTotal: 0, historyTotal: 0)
    }

    /// Matching starts here — two characters match thousands of calls and
    /// mean nothing yet.
    static let minimumFragmentLength = SCPDatabase.minimumFragmentLength

    /// Containment match over both sources, ranked: the exact call first (the
    /// eye's "known call" confirmation), then calls starting with the
    /// fragment, then the rest containing it — and inside each tier the
    /// history's calls before the database's, alphabetical within each
    /// because both inputs are sorted (`SCPDatabase.calls` is; the flow sorts
    /// the history's once per download).
    ///
    /// A linear scan of ~50k short strings is single-digit milliseconds and
    /// runs once per call-field change, never per render.
    static func matches(
        for fragment: String, scpCalls: [String], historyCalls: [String], limit: Int
    ) -> Matches {
        let needle = fragment.trimmingCharacters(in: .whitespaces).uppercased()
        guard needle.count >= minimumFragmentLength else { return .none }

        var exact: [Match] = []
        var starts: [Match] = []
        var contains: [Match] = []
        var seen = Set<String>()
        var scpTotal = 0
        var historyTotal = 0

        func place(_ call: String, inHistory: Bool) {
            let match = Match(call: call, inHistory: inHistory)
            if call == needle { exact.append(match) }
            else if call.hasPrefix(needle) { starts.append(match) }
            else { contains.append(match) }
        }

        // The history first, so a call in both sources takes its mark and its
        // place at the head of the tier.
        for call in historyCalls where call.contains(needle) {
            historyTotal += 1
            guard seen.insert(call).inserted else { continue }
            place(call, inHistory: true)
        }
        // Then the database — every match counts toward its total, and the
        // ones the history already placed are not placed again.
        for call in scpCalls where call.contains(needle) {
            scpTotal += 1
            guard seen.insert(call).inserted else { continue }
            place(call, inHistory: false)
        }

        let ranked = exact + starts + contains
        return Matches(
            calls: Array(ranked.prefix(max(0, limit))),
            total: ranked.count,
            scpTotal: scpTotal,
            historyTotal: historyTotal
        )
    }
}
