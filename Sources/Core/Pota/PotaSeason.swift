import Foundation

/// A year of POTA as the dashboard tells it, computed pure from program
/// records (`ContestRecord`s whose contest family is `.program`) and from
/// party records worked from a park: one row per outing — a log file — with
/// its park-days, and a season rollup that unions distinct things (parks,
/// states, entities) and sums the rest. A program log is POTA end to end,
/// hunting from home included; a party log is POTA only on the rows that
/// carry the park — the hour before the park was set is the contest's alone.
/// The ten-QSO validity is `PotaStats`' strict unique reading; the open
/// question is banked in docs/research/pota/SOURCES.md.
struct PotaSeason: Equatable, Sendable {

    /// One park × UTC day with contacts from it — POTA's own unit of
    /// activation ("within a single UTC day", docs.pota.app rules).
    struct ParkDay: Equatable, Sendable, Identifiable {
        let park: String
        /// Start of the UTC day, for display.
        let day: Date
        /// Unique (call, band, mode class) contacts at this park this day.
        let unique: Int

        var valid: Bool { unique >= PotaStats.validationTarget }
        var id: String { "\(park)|\(day.timeIntervalSince1970)" }
    }

    /// One outing — one log file in the folder.
    struct Outing: Equatable, Sendable, Identifiable {
        let record: ContestRecord
        /// The outing's POTA contacts: a program log's every valid contact,
        /// a party log's park contacts.
        let qsos: Int
        /// Distinct parks activated, sorted; empty for a hunter log.
        let parks: [String]
        /// Ordered by day, then park.
        let parkDays: [ParkDay]
        let p2pContacts: Int
        let states: Int
        let dxEntities: Int

        var id: String { record.id }
        var date: Date { record.earliestQSO ?? .distantPast }
        var minutes: Int { record.snapshot.operatingMinutes }
        /// A party record worked from a park, as against a program log.
        var isContest: Bool { record.outing == nil }
        var validParkDays: Int { parkDays.filter(\.valid).count }
    }

    let year: Int
    /// The year's outings in season order.
    let outings: [Outing]
    /// Σ park-days — how many activations were attempted.
    let activations: Int
    let validActivations: Int
    /// Distinct parks activated across the season.
    let parksActivated: Int
    /// Σ valid QSOs over the year's POTA logs.
    let qsos: Int
    /// Valid QSOs keyed by `ModeClass` raw value.
    let qsosByMode: [String: Int]
    let p2pContacts: Int
    /// Distinct parks on the other side — hunted, or park-to-park.
    let parksHunted: Int
    /// Distinct states worked (typed beats callbook, as everywhere).
    let states: Int
    /// Distinct DXCC entities that are not the operator's own.
    let dxEntities: Int
    let minutes: Int

    static let empty = PotaSeason(
        year: 0, outings: [], activations: 0, validActivations: 0,
        parksActivated: 0, qsos: 0, qsosByMode: [:], p2pContacts: 0,
        parksHunted: 0, states: 0, dxEntities: 0, minutes: 0
    )

    static func compute(
        records: [ContestRecord],
        year: Int,
        entityCode: (String) -> Int? = { CTYTable.shared?.match(callsign: $0)?.entity.entityCode }
    ) -> PotaSeason {
        let rows = ContestArchive.canonicalOrder(records.filter { $0.year == year })

        struct Triple: Hashable { let call: String; let band: Band; let mode: ModeClass }
        struct Key: Hashable { let park: String; let day: Date }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        var outings: [Outing] = []
        var seasonParks = Set<String>()
        var seasonHunted = Set<String>()
        var seasonStates = Set<String>()
        var seasonEntities = Set<Int>()
        var byMode: [String: Int] = [:]
        var qsos = 0, minutes = 0, p2p = 0

        for record in rows {
            var unique: [Key: Set<Triple>] = [:]
            var p2pGroups = Set<UUID>()
            var hunted = Set<String>()
            var states = Set<String>()
            var entities = Set<Int>()
            let myEntity = entityCode(record.callsign.uppercased())
            let program = record.outing != nil
            let contacts = program
                ? record.qsos
                : record.qsos.filter { !($0.myPotaRefs ?? []).isEmpty }

            for q in contacts {
                let day = utc.startOfDay(for: q.timestampUTC)
                for park in q.myPotaRefs ?? [] {
                    unique[Key(park: park.uppercased(), day: day), default: []]
                        .insert(Triple(call: q.call.uppercased(), band: q.band, mode: q.modeClass))
                }
                if let theirs = q.theirPotaRefs {
                    p2pGroups.insert(q.groupID)
                    for park in theirs { hunted.insert(park.uppercased()) }
                }
                let state = (q.theirState ?? q.callbook?.state ?? "")
                    .trimmingCharacters(in: .whitespaces).uppercased()
                if !state.isEmpty { states.insert(state) }
                if let code = entityCode(q.call.uppercased()), code != myEntity {
                    entities.insert(code)
                }
            }

            let parkDays = unique
                .map { ParkDay(park: $0.key.park, day: $0.key.day, unique: $0.value.count) }
                .sorted { ($0.day, $0.park) < ($1.day, $1.park) }
            let potaQSOs = program ? record.snapshot.validQSOs : contacts.count
            outings.append(Outing(
                record: record,
                qsos: potaQSOs,
                parks: Set(unique.keys.map(\.park)).sorted(),
                parkDays: parkDays,
                p2pContacts: p2pGroups.count,
                states: states.count,
                dxEntities: entities.count
            ))

            seasonParks.formUnion(unique.keys.map(\.park))
            seasonHunted.formUnion(hunted)
            seasonStates.formUnion(states)
            seasonEntities.formUnion(entities)
            if program {
                for (mode, count) in record.snapshot.qsosByMode {
                    byMode[mode, default: 0] += count
                }
            } else {
                for q in contacts { byMode[q.modeClass.rawValue, default: 0] += 1 }
            }
            qsos += potaQSOs
            minutes += record.snapshot.operatingMinutes
            p2p += p2pGroups.count
        }

        let parkDays = outings.flatMap(\.parkDays)
        return PotaSeason(
            year: year,
            outings: outings,
            activations: parkDays.count,
            validActivations: parkDays.filter(\.valid).count,
            parksActivated: seasonParks.count,
            qsos: qsos,
            qsosByMode: byMode,
            p2pContacts: p2p,
            parksHunted: seasonHunted.count,
            states: seasonStates.count,
            dxEntities: seasonEntities.count,
            minutes: minutes
        )
    }
}
