import Foundation

/// Duplicate detection. The key includes both location contexts:
/// a station worked from a different county (theirs or mine) is a new contact
/// (KSQP rule 10: a Kansas station that changes counties is a new station).
enum DupeChecker {

    struct DupeKey: Hashable {
        let call: String
        let myLoc: String
        let theirLoc: String
        let band: Band
        let modeClass: ModeClass
    }

    static func key(_ q: QSO) -> DupeKey {
        DupeKey(
            call: q.call.uppercased(),
            myLoc: q.myLoc.uppercased(),
            theirLoc: q.theirLoc.uppercased(),
            band: q.band,
            modeClass: q.modeClass
        )
    }

    /// IDs of the chronologically-first row for each key; later rows are dupes.
    static func firstOccurrenceIDs(_ log: [QSO]) -> Set<UUID> {
        var seen = Set<DupeKey>()
        var firsts = Set<UUID>()
        for q in log.sortedChronologically() where seen.insert(key(q)).inserted {
            firsts.insert(q.id)
        }
        return firsts
    }

    /// Live pre-log check: would a contact with these parameters duplicate an
    /// existing row for any (myLoc, theirLoc) pair?
    static func existingDupePairs(
        call: String,
        band: Band,
        modeClass: ModeClass,
        myLocs: [String],
        theirLocs: [String],
        log: [QSO]
    ) -> [(myLoc: String, theirLoc: String)] {
        let logged = Set(log.map(key))
        var dupes: [(String, String)] = []
        for mine in myLocs {
            for theirs in theirLocs {
                let k = DupeKey(
                    call: call.uppercased(),
                    myLoc: mine.uppercased(),
                    theirLoc: theirs.uppercased(),
                    band: band,
                    modeClass: modeClass
                )
                if logged.contains(k) { dupes.append((mine, theirs)) }
            }
        }
        return dupes
    }

    /// The general key: call, plus band and/or mode class per `rule.scope`,
    /// plus both locations when the rule is location-sensitive. With
    /// `.partyDefault` this is exactly `key(_:)`.
    struct RuleKey: Hashable {
        let call: String
        let band: Band?
        let modeClass: ModeClass?
        let myLoc: String?
        let theirLoc: String?
    }

    static func key(_ q: QSO, rule: DupeRule) -> RuleKey {
        RuleKey(
            call: q.call.uppercased(),
            band: rule.scope == .contest ? nil : q.band,
            modeClass: rule.scope == .bandMode ? q.modeClass : nil,
            myLoc: rule.locationSensitive ? q.myLoc.uppercased() : nil,
            theirLoc: rule.locationSensitive ? q.theirLoc.uppercased() : nil
        )
    }

    /// IDs of the chronologically-first row for each `RuleKey`; later rows are dupes.
    static func firstOccurrenceIDs(_ log: [QSO], rule: DupeRule) -> Set<UUID> {
        var seen = Set<RuleKey>()
        var firsts = Set<UUID>()
        for q in log.sortedChronologically() where seen.insert(key(q, rule: rule)).inserted {
            firsts.insert(q.id)
        }
        return firsts
    }

    /// One prior on-air contact with a station, for the worked-before table.
    ///
    /// A county-line contact produced several log rows from one contact, so it
    /// is one entry here and carries both counties — a table that answers
    /// "which bands and modes is he already in my log on" must not count one
    /// QSO twice.
    struct WorkedContact: Equatable, Identifiable, Sendable {
        /// The contact's `groupID` — stable, and unique per contact.
        let id: UUID
        let band: Band
        let modeClass: ModeClass
        let timestampUTC: Date
        /// Their location, county-line pairs joined the way the exchange
        /// parser accepts them.
        let theirLoc: String
    }

    /// Every prior contact with `call`, most recent first, across all bands and
    /// modes. Empty for a call that is blank or never worked.
    static func workedContacts(call: String, log: [QSO]) -> [WorkedContact] {
        let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
        guard !wanted.isEmpty else { return [] }

        var byGroup: [UUID: [QSO]] = [:]
        for q in log where q.call.uppercased() == wanted {
            byGroup[q.groupID, default: []].append(q)
        }

        return byGroup.values
            .compactMap { rows -> WorkedContact? in
                let ordered = rows.sortedChronologically()
                guard let first = ordered.first else { return nil }
                return WorkedContact(
                    id: first.groupID,
                    band: first.band,
                    modeClass: first.modeClass,
                    timestampUTC: first.timestampUTC,
                    theirLoc: ordered.map(\.theirLoc).joined(separator: "/")
                )
            }
            .sorted { $0.timestampUTC > $1.timestampUTC }
    }
}

extension [QSO] {
    /// Chronological order; ties keep insertion order (stable sort).
    func sortedChronologically() -> [QSO] {
        enumerated()
            .sorted { a, b in
                a.element.timestampUTC != b.element.timestampUTC
                    ? a.element.timestampUTC < b.element.timestampUTC
                    : a.offset < b.offset
            }
            .map(\.element)
    }
}
