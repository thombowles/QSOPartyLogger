import Foundation

/// Where a spot came from. The two feeds differ in more than origin: a hub
/// spot carries a county and stays useful for far longer, so lifetime and
/// multiplier handling both key off this.
enum SpotSource: String, Codable, Sendable {
    /// A DX cluster node — the historical source, and still the high-volume one.
    case cluster
    /// qsopartyhub.com, the board several QSO party sponsors point operators at.
    case hub
}

/// One spot. Identity is call + band, so a re-spot of the same station
/// replaces the older entry instead of stacking up.
struct Spot: Identifiable, Equatable, Sendable {
    var call: String
    var freqKHz: Double
    var spotter: String
    var comment: String
    var receivedAt: Date
    /// County abbreviation, when the source knew one. Cluster spots never do;
    /// hub spots usually do, and it is the multiplier the party is scored on.
    var county: String?
    var source: SpotSource = .cluster

    var band: Band? {
        Band.from(freqKHz: Int(freqKHz.rounded()))
    }

    var id: String {
        "\(call)|\(band?.rawValue ?? "?")"
    }
}
