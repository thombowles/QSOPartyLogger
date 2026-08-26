import Foundation

/// The activation panel's figures, computed pure from the log rows —
/// `ScoreEngine` never sees parks. Spec 2026-08-25 §activation panel.
struct PotaStats: Equatable, Sendable {
    struct ParkDay: Equatable, Sendable, Identifiable {
        let park: String
        /// Unique (call, band, mode class) contacts at this park this UTC
        /// day — the stricter reading of POTA's ten-QSO validity rule; the
        /// open question is banked in docs/research/pota/SOURCES.md.
        let uniqueToday: Int
        var id: String { park }
    }

    /// "A successful activation requires a minimum of 10 QSOs from a park in
    /// the designated list within a single UTC day (Zulu day)" —
    /// docs.pota.app/docs/rules.html, fetched 2026-08-25 (SOURCES.md).
    static let validationTarget = 10

    let parks: [ParkDay]
    /// Contacts (not rows) carrying a their-park, over the whole log.
    let p2pContacts: Int
    let p2pDistinctParks: Int
    /// Distinct states worked over the whole outing — the typed field
    /// first, the callbook's where nothing was typed (operator report 3,
    /// 2026-08-25).
    let distinctStates: Int
    /// Distinct DXCC entities that are not the operator's own, resolved
    /// from the calls the way the ADIF export resolves them. A call CTY
    /// cannot place claims nothing.
    let dxEntities: Int

    static func compute(
        qsos: [QSO], ownParks: [String], now: Date,
        myCall: String = "",
        entityCode: (String) -> Int? = { CTYTable.shared?.match(callsign: $0)?.entity.entityCode }
    ) -> PotaStats {
        let today = DupeChecker.utcDayIndex(now)

        struct Triple: Hashable { let call: String; let band: Band; let mode: ModeClass }
        var perPark: [String: Set<Triple>] = [:]
        for q in qsos where DupeChecker.utcDayIndex(q.timestampUTC) == today {
            for park in q.myPotaRefs ?? [] where ownParks.contains(park) {
                perPark[park, default: []].insert(
                    Triple(call: q.call.uppercased(), band: q.band, mode: q.modeClass))
            }
        }
        let parks = ownParks.map {
            ParkDay(park: $0, uniqueToday: perPark[$0]?.count ?? 0)
        }

        var p2pGroups = Set<UUID>()
        var p2pParks = Set<String>()
        for q in qsos {
            guard let theirs = q.theirPotaRefs else { continue }
            p2pGroups.insert(q.groupID)
            for p in theirs { p2pParks.insert(p.uppercased()) }
        }

        let myEntity = entityCode(myCall.uppercased())
        var states = Set<String>()
        var entities = Set<Int>()
        for q in qsos {
            let state = (q.theirState ?? q.callbook?.state ?? "")
                .trimmingCharacters(in: .whitespaces).uppercased()
            if !state.isEmpty { states.insert(state) }
            if let code = entityCode(q.call.uppercased()), code != myEntity {
                entities.insert(code)
            }
        }

        return PotaStats(parks: parks, p2pContacts: p2pGroups.count,
                         p2pDistinctParks: p2pParks.count,
                         distinctStates: states.count,
                         dxEntities: entities.count)
    }

    /// Seconds until the UTC day rolls — the one clock an activator must
    /// not miss.
    static func secondsToUTCMidnight(now: Date) -> Int {
        let t = now.timeIntervalSince1970
        let nextMidnight = (floor(t / 86_400) + 1) * 86_400
        return Int(nextMidnight - t)
    }
}
