import Foundation

/// Amateur bands supported by QSO parties. Raw value doubles as the ADIF band string.
enum Band: String, Codable, CaseIterable, Sendable, Identifiable {
    case m160 = "160m"
    case m80 = "80m"
    case m60 = "60m"
    case m40 = "40m"
    case m30 = "30m"
    case m20 = "20m"
    case m17 = "17m"
    case m15 = "15m"
    case m12 = "12m"
    case m10 = "10m"
    case m6 = "6m"
    case m2 = "2m"
    case cm70 = "70cm"

    var id: String { rawValue }

    /// US band edges in kHz (inclusive).
    private static let edges: [(Band, ClosedRange<Int>)] = [
        (.m160, 1800...2000),
        (.m80, 3500...4000),
        (.m60, 5330...5410),
        (.m40, 7000...7300),
        (.m30, 10100...10150),
        (.m20, 14000...14350),
        (.m17, 18068...18168),
        (.m15, 21000...21450),
        (.m12, 24890...24990),
        (.m10, 28000...29700),
        (.m6, 50000...54000),
        (.m2, 144000...148000),
        (.cm70, 420000...450000),
    ]

    static func from(freqKHz: Int) -> Band? {
        edges.first { $0.1.contains(freqKHz) }?.0
    }

    /// US band edges in kHz — the band map's vertical extent.
    var rangeKHz: ClosedRange<Int> {
        Self.edges.first { $0.0 == self }!.1
    }

    /// Fallback frequency for Cabrillo rows logged without CAT data.
    var defaultFreqKHz: Int {
        switch self {
        case .m160: 1815
        case .m80: 3550
        case .m60: 5332
        case .m40: 7040
        case .m30: 10110
        case .m20: 14040
        case .m17: 18080
        case .m15: 21040
        case .m12: 24900
        case .m10: 28040
        case .m6: 50095
        case .m2: 144200
        case .cm70: 432100
        }
    }

    var adif: String { rawValue }
}
