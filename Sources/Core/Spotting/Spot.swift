import Foundation

/// One DX cluster spot. Identity is call + band, so a re-spot of the same
/// station replaces the older entry instead of stacking up.
struct Spot: Identifiable, Equatable, Sendable {
    var call: String
    var freqKHz: Double
    var spotter: String
    var comment: String
    var receivedAt: Date

    var band: Band? {
        Band.from(freqKHz: Int(freqKHz.rounded()))
    }

    var id: String {
        "\(call)|\(band?.rawValue ?? "?")"
    }
}
