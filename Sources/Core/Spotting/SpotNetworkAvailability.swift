import Foundation

/// Which networks the spot sheet offers right now, and — when one is not on
/// offer — the thing to change, named. A greyed checkbox that does not say
/// why is a bug report. Pure, so every reason is assertable and no view
/// decides policy.
enum SpotNetworkAvailability {

    enum Availability: Equatable, Sendable {
        /// On offer, with where it goes — the host the operator recognises.
        case available(String)
        /// Not on offer, and why.
        case unavailable(String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }

        var text: String {
            switch self {
            case .available(let destination): destination
            case .unavailable(let reason): reason
            }
        }
    }

    /// Who the spot is for — the two cases `SpotCommand` already draws.
    enum Target: Equatable, Sendable {
        case myself
        case station
    }

    struct Context: Equatable, Sendable {
        var clusterConnected: Bool
        var clusterHost: String
        /// The spotting policy's reason when the declared category forbids a
        /// cluster at all; `nil` when it does not. Passed in rather than read,
        /// so this file owes nothing to the layer that owns the policy.
        var clusterBlockedReason: String?
        /// The hub's host when the party has a page there; `nil` when not.
        var hubHost: String?
        var target: Target
        var myParks: [String]
        /// The park reference in the draft — for another station, the only
        /// way POTA becomes available is the operator typing one.
        var draftPark: String
    }

    static let clusterNotConnected = "Not connected — Spots ▸ Connect"
    static let noHubPage = "This party has no page on qsopartyhub.com"
    static let noOwnPark = "Set your park in Contest Setup to spot yourself on POTA"
    static let noTheirPark = "Enter their park to spot them on POTA"
    static let potaHost = "pota.app"

    static func availability(of network: SpotNetwork, in context: Context) -> Availability {
        switch network {
        case .cluster:
            if let reason = context.clusterBlockedReason { return .unavailable(reason) }
            return context.clusterConnected
                ? .available(context.clusterHost.trimmingCharacters(in: .whitespaces))
                : .unavailable(clusterNotConnected)
        case .hub:
            return context.hubHost.map { .available($0) } ?? .unavailable(noHubPage)
        case .pota:
            switch context.target {
            case .myself:
                guard let park = context.myParks.first else { return .unavailable(noOwnPark) }
                return .available("\(potaHost) · \(park)")
            case .station:
                return PotaSpot.reference(from: context.draftPark) != nil
                    ? .available(potaHost)
                    : .unavailable(noTheirPark)
            }
        }
    }

    static func available(in context: Context) -> Set<SpotNetwork> {
        Set(SpotNetwork.allCases.filter { availability(of: $0, in: context).isAvailable })
    }

    /// Whether ⇧⌘S has anywhere to go. For another station the sheet opens
    /// even with nothing on offer yet, because its POTA row carries the park
    /// field and typing one is the way in; for yourself there is nothing to
    /// type, so nothing on offer means no sheet.
    static func canOpenSheet(in context: Context) -> Bool {
        context.target == .station || !available(in: context).isEmpty
    }
}
