import Foundation

/// Cabrillo header data plus category selections.
struct StationProfile: Codable, Equatable, Hashable, Sendable {
    var callsign: String = ""
    var name: String = ""
    var email: String = ""
    var address: String = ""
    var city: String = ""
    var stateProvince: String = ""
    var postalCode: String = ""
    var country: String = "USA"
    var club: String = ""
    /// Space-separated operator calls for multi-op; empty = just `callsign`.
    var operators: String = ""
    var categoryOperator: CategoryOperator = .singleOp
    var categoryPower: CategoryPower = .low
    var categoryStation: CategoryStation = .fixed
    var categoryTransmitter: CategoryTransmitter = .one

    enum CategoryOperator: String, Codable, CaseIterable, Sendable {
        case singleOp = "SINGLE-OP"
        case multiOp = "MULTI-OP"
        case checklog = "CHECKLOG"
    }

    enum CategoryPower: String, Codable, CaseIterable, Sendable {
        case high = "HIGH"
        case low = "LOW"
        case qrp = "QRP"
    }

    enum CategoryStation: String, Codable, CaseIterable, Sendable {
        case fixed = "FIXED"
        case mobile = "MOBILE"
        case portable = "PORTABLE"
        case rover = "ROVER"
        case expedition = "EXPEDITION"
        case school = "SCHOOL"
    }

    enum CategoryTransmitter: String, Codable, CaseIterable, Sendable {
        case one = "ONE"
        case two = "TWO"
        case limited = "LIMITED"
        case unlimited = "UNLIMITED"
    }
}
