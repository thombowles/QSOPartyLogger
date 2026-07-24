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
