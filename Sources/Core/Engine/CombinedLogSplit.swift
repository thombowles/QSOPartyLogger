import Foundation

/// A combined entry's log as each of its member sponsors sees it.
///
/// Four sponsors share the first weekend of May and accept one shared log —
/// *"You may submit a single log that combines all of your QSOs from the New
/// England, 7th Call Area, Indiana and Delaware QSO parties. QSOs not
/// applicable to the NEQP will be ignored."* The State QSO Party Challenge then
/// counts each of the four **separately**, and needs two valid QSOs in one
/// before it multiplies, so "how many would Delaware count?" is a question the
/// operator has to be able to answer while there is still time to fix it.
///
/// Nothing here reimplements a sponsor's rules, which would be exactly the
/// model recall Article 1 forbids. Each member's rows are narrowed to the
/// contacts that sponsor would look at, and the member's **own** definition
/// scores them through `ScoreEngine` — its modes, its points, its dupe scope.
enum CombinedLogSplit {

    /// One member contest's view of the combined log.
    struct MemberLine: Identifiable, Equatable, Sendable {
        let party: PartyDefinition
        let validQSOs: Int
        let countiesWorked: Set<String>
        /// Contacts made in this member's counties that it will not count at
        /// all: a band or a mode this sponsor does not run. Dupes are not
        /// counted here — a dupe is a contact the sponsor saw and refused,
        /// which is a different thing from one it never looks at.
        let ignored: Int

        var id: String { party.id }

        /// The Challenge's own bar: *"Entrants must make at least two contacts
        /// in a QSO party for it to count as a multiplier."*
        var qualifiesForChallenge: Bool { validQSOs >= 2 }
    }

    // MARK: Scoping

    /// The rows this member's sponsor would look at: a contact in one of its
    /// own counties, on a band it runs.
    ///
    /// The county filter is applied **whatever `myLocation` says**. The
    /// combined entry is for an operator outside all four regions and
    /// `PartyCatalog.suggestedParty` steers them there, but nothing stops an
    /// in-region operator picking it — and for an in-state log
    /// `ScoreEngine.inScopeRows` does no filtering, which would hand every
    /// contact to all four members at once.
    ///
    /// The band filter lives here rather than in `ScoreEngine`, which has never
    /// enforced `validBands` — bands are an entry-UI constraint (`RadioBar`,
    /// `EditQSOSheet`). Moving that into the engine would change scoring for
    /// every party at once, which belongs in its own party-free commit.
    private static func rows(
        of log: ContestLog, for member: PartyDefinition, counties: Set<String>
    ) -> [QSO] {
        let bands = Set(member.validBands)
        return log.qsos.filter {
            counties.contains($0.theirLoc.uppercased()) && bands.contains($0.band)
        }
    }

    /// The same log narrowed to one member, ready for that member's own rules.
    ///
    /// `myLocation` is left as the operator logged it, which is right for the
    /// member they are inside and wrong for the other three — an Indiana
    /// operator is in-state for Indiana alone. Nothing read from the result
    /// depends on it: valid QSOs are the scoped rows less dupes, and
    /// `inScopeRows` is already satisfied by the county filter above. **A
    /// per-member score would depend on it**, which is one more reason this
    /// reports counts rather than scores.
    private static func log(
        _ log: ContestLog, scopedTo member: PartyDefinition, counties: Set<String>
    ) -> ContestLog {
        var scoped = log
        scoped.partyID = member.id
        scoped.qsos = rows(of: log, for: member, counties: counties)
        return scoped
    }

    private static func abbrs(_ member: PartyDefinition) -> Set<String> {
        Set(member.counties.map(\.abbr))
    }

    // MARK: The split

    /// One line per member the combined entry declares, in its declared order.
    /// Empty for an ordinary party, so a caller can ask without checking first.
    static func split(
        log: ContestLog,
        combined: PartyDefinition,
        members: [PartyDefinition]
    ) -> [MemberLine] {
        let byID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return combined.combines.compactMap { id in
            guard let member = byID[id] else { return nil }
            return line(log: log, member: member)
        }
    }

    private static func line(log: ContestLog, member: PartyDefinition) -> MemberLine {
        let counties = abbrs(member)
        let scoped = self.log(log, scopedTo: member, counties: counties)
        let score = ScoreEngine.score(log: scoped, party: member)

        // Counties come from the rows rather than from the multiplier keys:
        // a member whose rules don't make counties a multiplier class still
        // has counties worth showing (the sidebar's own award tracking).
        let allowedModes = Set(member.allowedModeClasses)
        let counted = scoped.qsos.filter { allowedModes.contains($0.modeClass) }
        let inRegion = log.qsos.filter { counties.contains($0.theirLoc.uppercased()) }

        return MemberLine(
            party: member,
            validQSOs: score.validQSOs,
            countiesWorked: Set(counted.map { $0.theirLoc.uppercased() }),
            ignored: inRegion.count - counted.count
        )
    }

    // MARK: The archive

    /// Replaces every combined record with one record per member it actually
    /// worked, leaving ordinary records untouched.
    ///
    /// The Challenge tracks contests, and a combined entry is not one: `in7qpne`
    /// is not on the approved list and never will be, so an unsplit record
    /// counts for nothing. Split, the same weekend is what the four sponsors
    /// say it is — up to four entries, each qualifying on its own two QSOs.
    ///
    /// A member with nothing to show produces no record at all, rather than a
    /// zero the dashboard would have to explain.
    static func expand(
        records: [ContestRecord],
        parties: [PartyDefinition]
    ) -> [ContestRecord] {
        let byID = Dictionary(parties.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return records.flatMap { record -> [ContestRecord] in
            guard let combined = byID[record.partyID], !combined.combines.isEmpty else {
                return [record]
            }
            var log = ContestLog(partyID: record.partyID)
            log.station = record.station
            log.myLocation = record.myLocation
            log.qsos = record.qsos

            return combined.combines.compactMap { id -> ContestRecord? in
                guard let member = byID[id] else { return nil }
                let scoped = self.log(log, scopedTo: member, counties: abbrs(member))
                let snapshot = ScoreSnapshot.make(log: scoped, party: member)
                guard snapshot.validQSOs > 0 else { return nil }
                return ContestRecord.make(
                    from: scoped,
                    snapshot: snapshot,
                    updatedAt: record.updatedAt,
                    sourceFileName: record.sourceFileName
                )
            }
        }
    }
}
