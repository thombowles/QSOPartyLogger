import Foundation

/// The parsed MASTER.SCP super check partial database — the community's
/// roster of calls seen in contest logs, from supercheckpartial.com.
///
/// **Hint data, never authority** (constitution Article 1): nothing here
/// reaches scoring, validation, or export. It draws the strip of known
/// calls under the entry row, and that is all it can do.
///
/// File shape, observed 2026-08-04 (`docs/research/scp_masterfile.md`):
/// an `!!Order,1,1` directive line, `#` comments — one of them
/// `# Release 2026.07.31` — then one uppercase call per CRLF line.
struct SCPDatabase: Equatable, Sendable {
    /// Every call in the file: uppercased, deduplicated, sorted.
    let calls: [String]
    /// The file's own `# Release …` stamp, when it carries one. Display
    /// only — freshness is judged by the server's `Last-Modified`, which a
    /// HEAD can read without the body.
    let release: String?

    var recordCount: Int { calls.count }

    /// The floor an installed file must clear. The real file carries ~50k
    /// calls; an error page, truncation, or lookalike will not produce a
    /// thousand tokens that scan as callsigns.
    static let minimumRecords = 1000

    /// Matching starts here — two characters match thousands of calls and
    /// mean nothing yet.
    static let minimumFragmentLength = 3

    /// A call is letters, digits and `/`, at least three long. This is what
    /// drops the `!!Order` directive and `#` comments without special cases.
    private static let callCharacters =
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/")

    static func parse(data: Data) -> SCPDatabase? {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var seen = Set<String>()
        var release: String?
        for rawLine in text.split(omittingEmptySubsequences: true,
                                  whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if release == nil, line.hasPrefix("#") {
                let comment = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if comment.hasPrefix("Release") {
                    let stamp = comment.dropFirst("Release".count)
                        .trimmingCharacters(in: .whitespaces)
                    if !stamp.isEmpty { release = stamp }
                }
                continue
            }
            let call = line.uppercased()
            guard call.count >= minimumFragmentLength,
                  call.unicodeScalars.allSatisfy(callCharacters.contains)
            else { continue }
            seen.insert(call)
        }
        return SCPDatabase(calls: seen.sorted(), release: release)
    }

    /// What the strip shows: the capped list plus the real total, so the
    /// view can say "+N more" truthfully.
    struct Matches: Equatable, Sendable {
        let calls: [String]
        let total: Int
        static let none = Matches(calls: [], total: 0)
    }

    /// Containment match over the whole database, ranked: the exact call
    /// first (the eye's "known call" confirmation), then calls starting
    /// with the fragment, then the rest containing it — alphabetical
    /// within each tier, because `calls` is sorted. `SuperCheck` is the one
    /// ranking; this is it with no history file alongside.
    ///
    /// A linear scan of ~50k short strings is single-digit milliseconds
    /// and runs once per call-field change, never per render.
    func matches(for fragment: String, limit: Int) -> Matches {
        let merged = SuperCheck.matches(
            for: fragment, scpCalls: calls, historyCalls: [], limit: limit
        )
        return Matches(calls: merged.calls.map(\.call), total: merged.total)
    }
}
