import Foundation

/// The one-file contest history (`Contest History.qphistory`): every archived
/// contest with its full QSO rows and score snapshot. Record merge is a
/// commutative union, which is what turns iCloud conflict copies into a
/// mechanical fold instead of a data-loss hazard.
struct ContestArchive: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var records: [ContestRecord] = []
    /// Envelope fields written by newer builds, preserved verbatim.
    var extras: [String: JSONValue] = [:]

    static let empty = ContestArchive()

    /// Replace-or-append by record identity. `rebuildSnapshot` runs when the
    /// merged QSO set differs from the surviving snapshot's basis (the union
    /// outgrew what the winning side described); return nil to keep it.
    func upserting(
        _ record: ContestRecord,
        rebuildSnapshot: (ContestRecord) -> ScoreSnapshot? = { _ in nil }
    ) -> ContestArchive {
        var next = self
        if let index = next.records.firstIndex(where: { $0.identity == record.identity }) {
            next.records[index] = Self.resolve(
                next.records[index], record, rebuildSnapshot: rebuildSnapshot
            )
        } else {
            next.records.append(record)
        }
        next.records = Self.canonicalOrder(next.records)
        return next
    }

    /// Union of two archives (the two-Mac / conflict-version story).
    func merging(
        _ other: ContestArchive,
        rebuildSnapshot: (ContestRecord) -> ScoreSnapshot? = { _ in nil }
    ) -> ContestArchive {
        var next = self
        var byIdentity = Dictionary(
            uniqueKeysWithValues: next.records.map { ($0.identity, $0) }
        )
        for incoming in other.records {
            if let existing = byIdentity[incoming.identity] {
                byIdentity[incoming.identity] = Self.resolve(
                    existing, incoming, rebuildSnapshot: rebuildSnapshot
                )
            } else {
                byIdentity[incoming.identity] = incoming
            }
        }
        next.records = Self.canonicalOrder(Array(byIdentity.values))
        next.extras = other.extras.merging(extras) { _, mine in mine }
        return next
    }

    private static func resolve(
        _ existing: ContestRecord,
        _ incoming: ContestRecord,
        rebuildSnapshot: (ContestRecord) -> ScoreSnapshot?
    ) -> ContestRecord {
        let winner = existing.updatedAt > incoming.updatedAt ? existing : incoming
        var merged = existing.merging(incoming)
        if Set(merged.qsos.map(\.id)) != Set(winner.qsos.map(\.id)),
           let rebuilt = rebuildSnapshot(merged) {
            merged.snapshot = rebuilt
        }
        return merged
    }

    func record(for identity: ContestRecord.Identity) -> ContestRecord? {
        records.first { $0.identity == identity }
    }

    /// Distinct years present, newest first.
    var years: [Int] {
        Set(records.map(\.year)).sorted(by: >)
    }

    /// Records for a year, earliest contest first.
    func records(year: Int) -> [ContestRecord] {
        records.filter { $0.year == year }
    }

    /// Stable file order: chronological, then party/callsign.
    static func canonicalOrder(_ records: [ContestRecord]) -> [ContestRecord] {
        records.sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            let first = $0.earliestQSO ?? .distantPast
            let second = $1.earliestQSO ?? .distantPast
            if first != second { return first < second }
            if $0.partyID != $1.partyID { return $0.partyID < $1.partyID }
            return $0.callsign < $1.callsign
        }
    }

    static func decode(from data: Data) throws -> ContestArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContestArchive.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Codable (unknown fields preserved)

    private enum KnownKeys: String, CodingKey, CaseIterable {
        case schemaVersion, records
    }

    init(schemaVersion: Int = 1, records: [ContestRecord] = [], extras: [String: JSONValue] = [:]) {
        self.schemaVersion = schemaVersion
        self.records = records
        self.extras = extras
    }

    init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKeys.self)
        schemaVersion = try known.decode(Int.self, forKey: .schemaVersion)
        records = try known.decode([ContestRecord].self, forKey: .records)

        let unknown = try decoder.container(keyedBy: UnknownCodingKey.self)
        extras = try unknown.decodeUnknownFields(
            besides: Set(KnownKeys.allCases.map(\.rawValue))
        )
    }

    func encode(to encoder: Encoder) throws {
        var known = encoder.container(keyedBy: KnownKeys.self)
        try known.encode(schemaVersion, forKey: .schemaVersion)
        try known.encode(records, forKey: .records)

        var unknown = encoder.container(keyedBy: UnknownCodingKey.self)
        try unknown.encodeUnknownFields(extras)
    }
}
