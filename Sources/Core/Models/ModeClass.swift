import Foundation

/// Scoring class of a mode. Parties score by class; the concrete mode (SSB, RTTY…)
/// is kept separately on the QSO as `rawMode` for export.
enum ModeClass: String, Codable, CaseIterable, Sendable, Identifiable {
    case phone
    case cw
    case digital

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phone: "Phone"
        case .cw: "CW"
        case .digital: "Digital"
        }
    }

    /// Default RST for the class (599 for keyed modes, 59 for phone).
    var defaultRST: String {
        self == .phone ? "59" : "599"
    }

    /// Classify an ADIF-style mode string.
    static func classify(rawMode: String) -> ModeClass {
        switch rawMode.uppercased() {
        case "CW": .cw
        case "SSB", "USB", "LSB", "AM", "FM", "PH": .phone
        default: .digital
        }
    }
}
