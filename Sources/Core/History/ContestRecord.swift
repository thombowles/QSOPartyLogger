import Foundation

/// One archived contest entry. Identity is the sponsor's own notion of an
/// entry — one log per callsign per running of a party — so a two-window
/// weekend is naturally one record, and the same contest edited on two Macs
/// merges instead of duplicating.
struct ContestRecord: Codable, Equatable, Sendable, Identifiable {

    struct Identity: Hashable, Sendable {
        let partyID: String
        let year: Int
        let callsign: String
    }

    var partyID: String
    var year: Int
    var callsign: String
    var station: StationProfile
    var myLocation: MyLocation
    var qsos: [QSO]
    var snapshot: ScoreSnapshot
    var updatedAt: Date
    var sourceFileName: String?
    /// Fields written by newer builds, preserved verbatim (see `JSONValue`).
    var extras: [String: JSONValue] = [:]

    var id: String { "\(partyID)|\(year)|\(callsign)" }

    var identity: Identity {
        Identity(partyID: partyID, year: year, callsign: callsign)
    }

    var earliestQSO: Date? {
        qsos.map(\.timestampUTC).min()
    }

    /// UTC year of the log's earliest QSO; nil for an empty log.
    static func year(of log: ContestLog) -> Int? {
        log.qsos.map(\.timestampUTC).min()?.utcYear
    }

    /// nil when the log can't be archived yet: no QSOs (nothing to track)
    /// or no callsign (no identity).
    static func make(
        from log: ContestLog,
        snapshot: ScoreSnapshot,
        updatedAt: Date,
        sourceFileName: String?
    ) -> ContestRecord? {
        let callsign = log.station.callsign
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        guard !callsign.isEmpty, let year = year(of: log) else { return nil }
        return ContestRecord(
            partyID: log.partyID,
            year: year,
            callsign: callsign,
            station: log.station,
            myLocation: log.myLocation,
            qsos: canonicalOrder(log.qsos),
            snapshot: snapshot,
            updatedAt: updatedAt,
            sourceFileName: sourceFileName
        )
    }

    /// Union with another record of the same identity (the two-Mac story):
    /// QSOs union by id, the later-saved side winning any per-QSO conflict
    /// and supplying station/location/snapshot. Commutative whenever the two
    /// `updatedAt` stamps differ; an exact tie resolves toward `other`.
    func merging(_ other: ContestRecord) -> ContestRecord {
        let (winner, loser) = updatedAt > other.updatedAt ? (self, other) : (other, self)
        var byID = Dictionary(uniqueKeysWithValues: loser.qsos.map { ($0.id, $0) })
        for qso in winner.qsos {
            byID[qso.id] = qso
        }
        var merged = winner
        merged.qsos = Self.canonicalOrder(Array(byID.values))
        merged.updatedAt = max(updatedAt, other.updatedAt)
        merged.extras = loser.extras.merging(winner.extras) { _, winnerValue in winnerValue }
        return merged
    }

    /// Deterministic row order so merged archives compare equal regardless
    /// of merge direction.
    static func canonicalOrder(_ qsos: [QSO]) -> [QSO] {
        qsos.sorted {
            if $0.timestampUTC != $1.timestampUTC {
                return $0.timestampUTC < $1.timestampUTC
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: Codable (unknown fields preserved)

    private enum KnownKeys: String, CodingKey, CaseIterable {
        case partyID, year, callsign, station, myLocation, qsos, snapshot
        case updatedAt, sourceFileName
    }

    init(
        partyID: String,
        year: Int,
        callsign: String,
        station: StationProfile,
        myLocation: MyLocation,
        qsos: [QSO],
        snapshot: ScoreSnapshot,
        updatedAt: Date,
        sourceFileName: String?,
        extras: [String: JSONValue] = [:]
    ) {
        self.partyID = partyID
        self.year = year
        self.callsign = callsign
        self.station = station
        self.myLocation = myLocation
        self.qsos = qsos
        self.snapshot = snapshot
        self.updatedAt = updatedAt
        self.sourceFileName = sourceFileName
        self.extras = extras
    }

    init(from decoder: Decoder) throws {
        let known = try decoder.container(keyedBy: KnownKeys.self)
        partyID = try known.decode(String.self, forKey: .partyID)
        year = try known.decode(Int.self, forKey: .year)
        callsign = try known.decode(String.self, forKey: .callsign)
        station = try known.decode(StationProfile.self, forKey: .station)
        myLocation = try known.decode(MyLocation.self, forKey: .myLocation)
        qsos = try known.decode([QSO].self, forKey: .qsos)
        snapshot = try known.decode(ScoreSnapshot.self, forKey: .snapshot)
        updatedAt = try known.decode(Date.self, forKey: .updatedAt)
        sourceFileName = try known.decodeIfPresent(String.self, forKey: .sourceFileName)

        let unknown = try decoder.container(keyedBy: UnknownCodingKey.self)
        extras = try unknown.decodeUnknownFields(
            besides: Set(KnownKeys.allCases.map(\.rawValue))
        )
    }

    func encode(to encoder: Encoder) throws {
        var known = encoder.container(keyedBy: KnownKeys.self)
        try known.encode(partyID, forKey: .partyID)
        try known.encode(year, forKey: .year)
        try known.encode(callsign, forKey: .callsign)
        try known.encode(station, forKey: .station)
        try known.encode(myLocation, forKey: .myLocation)
        try known.encode(qsos, forKey: .qsos)
        try known.encode(snapshot, forKey: .snapshot)
        try known.encode(updatedAt, forKey: .updatedAt)
        try known.encodeIfPresent(sourceFileName, forKey: .sourceFileName)

        var unknown = encoder.container(keyedBy: UnknownCodingKey.self)
        try unknown.encodeUnknownFields(extras)
    }
}
