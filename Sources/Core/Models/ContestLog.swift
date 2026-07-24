import Foundation

/// The persisted document payload (`.qplog` = JSON of this).
struct ContestLog: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    /// PartyDefinition id, e.g. "ksqp".
    var partyID: String
    var station: StationProfile
    var myLocation: MyLocation
    var qsos: [QSO]

    init(
        partyID: String,
        station: StationProfile = StationProfile(),
        myLocation: MyLocation = .outOfState(location: ""),
        qsos: [QSO] = []
    ) {
        self.partyID = partyID
        self.station = station
        self.myLocation = myLocation
        self.qsos = qsos
    }

    static func decode(from data: Data) throws -> ContestLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContestLog.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
