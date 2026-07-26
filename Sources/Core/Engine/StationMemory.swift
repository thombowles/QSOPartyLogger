import Foundation

/// What the app already knows a station sends, and where it learned it.
///
/// The rule the archive fallback rests on: a county abbreviation means nothing
/// outside the party that defines it. Kansas counties are Kansas QSO Party
/// vocabulary — offering one in an Alabama log would be a wrong exchange with a
/// confident face on it. A state, province or DX is stable across sponsors, so
/// it carries over.
enum StationMemory {

    /// Where a candidate came from, for the operator to judge it by.
    enum Source: Equatable, Sendable {
        case thisLog
        case archive(partyID: String, year: Int)
    }

    struct Candidate: Equatable, Sendable {
        let text: String
        let source: Source
    }

    /// One archived contact, flattened for lookup by call.
    struct ArchiveEntry: Equatable, Sendable {
        let call: String
        let theirLoc: String
        let partyID: String
        let year: Int
        let timestampUTC: Date
        /// Whether `theirLoc` was a county of the party that recorded it.
        let isCountyOfItsParty: Bool
    }

    /// Calls → their archived contacts, newest first. Built once, off the main
    /// actor; a value, so handing it across an actor boundary copies nothing
    /// that can change underneath.
    struct Index: Equatable, Sendable {
        var byCall: [String: [ArchiveEntry]] = [:]

        static let empty = Index()

        init(byCall: [String: [ArchiveEntry]] = [:]) {
            self.byCall = byCall
        }

        func entries(for call: String) -> [ArchiveEntry] {
            byCall[call.trimmingCharacters(in: .whitespaces).uppercased()] ?? []
        }

        /// `countiesByParty` maps a party id to its county abbreviations. Passed
        /// in rather than looked up so this stays a pure function — and so the
        /// bundle is read once per party instead of once per QSO.
        static func build(
            _ archive: ContestArchive,
            countiesByParty: [String: Set<String>]
        ) -> Index {
            var byCall: [String: [ArchiveEntry]] = [:]
            for record in archive.records {
                let counties = countiesByParty[record.partyID] ?? []
                for qso in record.qsos {
                    let call = qso.call.uppercased()
                    byCall[call, default: []].append(
                        ArchiveEntry(
                            call: call,
                            theirLoc: qso.theirLoc,
                            partyID: record.partyID,
                            year: record.year,
                            timestampUTC: qso.timestampUTC,
                            isCountyOfItsParty: counties.contains(qso.theirLoc.uppercased())
                        )
                    )
                }
            }
            for (call, entries) in byCall {
                byCall[call] = entries.sorted { $0.timestampUTC > $1.timestampUTC }
            }
            return Index(byCall: byCall)
        }
    }

    /// The best exchange to offer for `call`, or nil when nothing is known that
    /// the current party can accept.
    ///
    /// Order: this log, then the archive under the same sponsor, then the
    /// archive under any sponsor where the value was not a county. Every
    /// candidate must survive the current party's own parser — belt and braces
    /// against an abbreviation that collides across two counties lists.
    static func candidate(
        call: String,
        log: [QSO],
        index: Index,
        party: PartyDefinition,
        role: ExchangeParser.Role
    ) -> Candidate? {
        let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
        guard !wanted.isEmpty else { return nil }

        if let recent = DupeChecker.workedContacts(call: wanted, log: log).first,
           parses(recent.theirLoc, party: party, role: role) {
            return Candidate(text: recent.theirLoc, source: .thisLog)
        }

        let archived = index.entries(for: wanted)
        for entry in archived
        where entry.partyID == party.id && parses(entry.theirLoc, party: party, role: role) {
            return Candidate(
                text: entry.theirLoc,
                source: .archive(partyID: entry.partyID, year: entry.year)
            )
        }
        for entry in archived
        where entry.partyID != party.id
            && !entry.isCountyOfItsParty
            && parses(entry.theirLoc, party: party, role: role) {
            return Candidate(
                text: entry.theirLoc,
                source: .archive(partyID: entry.partyID, year: entry.year)
            )
        }
        return nil
    }

    private static func parses(
        _ text: String, party: PartyDefinition, role: ExchangeParser.Role
    ) -> Bool {
        if case .success = ExchangeParser.parse(text, party: party, role: role) {
            return true
        }
        return false
    }
}
