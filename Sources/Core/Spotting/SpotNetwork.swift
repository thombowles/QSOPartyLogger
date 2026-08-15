import Foundation

/// A place a spot can be *sent*. (`SpotSource` is where one *came from*; the
/// two lists differ — nothing is read from POTA, and `.local` is never a
/// destination.)
enum SpotNetwork: String, CaseIterable, Codable, Sendable, Identifiable {
    case cluster
    case hub
    case pota

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cluster: "DX cluster"
        case .hub: "QSO Party Hub"
        case .pota: "POTA"
        }
    }

    /// The word the receipt uses — short, because three of them share a line.
    var shortName: String {
        switch self {
        case .cluster: "Cluster"
        case .hub: "Hub"
        case .pota: "POTA"
        }
    }

    /// ⌘1, ⌘2, ⌘3 tick and untick the rows in the sheet, in list order.
    var shortcutDigit: Character {
        switch self {
        case .cluster: "1"
        case .hub: "2"
        case .pota: "3"
        }
    }

    /// What the sheet opens ticked: whatever is on offer that the operator
    /// kept ticked last time.
    static func initialSelection(
        available: Set<SpotNetwork>, preferred: Set<SpotNetwork>
    ) -> Set<SpotNetwork> {
        available.intersection(preferred)
    }

    /// The remembered choice after a post. Only the networks the sheet
    /// actually offered move; one that was unavailable keeps its old bit, so
    /// a home weekend never un-ticks POTA for the next park.
    static func updatedPreference(
        preferred: Set<SpotNetwork>, available: Set<SpotNetwork>, selected: Set<SpotNetwork>
    ) -> Set<SpotNetwork> {
        preferred.subtracting(available).union(selected.intersection(available))
    }
}
