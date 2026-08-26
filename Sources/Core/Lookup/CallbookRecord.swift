import Foundation

/// One callbook answer — advisory data about a station, from exactly one
/// service (spec 2026-08-25 decision 6: no merging; a record's provenance is
/// one service). Never scored, never written into a received exchange field.
struct CallbookRecord: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case qrz, hamqth
        var label: String {
            switch self {
            case .qrz: "QRZ"
            case .hamqth: "HamQTH"
            }
        }
    }

    let call: String
    let name: String?
    /// City — QRZ `addr2`, HamQTH `qth`.
    let qth: String?
    let state: String?
    let county: String?
    let grid: String?
    /// The DXCC entity name — QRZ `land` (its `country` is the QSL mailing
    /// address, a banked gotcha), HamQTH `country`.
    let country: String?
    let dxccID: Int?
    let source: Source
    let fetchedAt: Date
}
