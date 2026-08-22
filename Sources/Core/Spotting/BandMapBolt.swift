import Foundation

/// The band map fastened to the side of its log window — the geometry, which
/// is Foundation only. The AppKit relationship that keeps it there is
/// `BandMapBolt.Attachment`, in the UI layer.
///
/// Why: one floating map per log window is two identical panels the moment a
/// second log opens — both restore to the same autosaved frame, both float
/// above both logs, and neither moves with its own window. Bolted, each map
/// sits against its own window's edge, at its level, and goes where it goes.
enum BandMapBolt {
    /// Which side of the log window the map is fastened to.
    enum Side: String, CaseIterable, Identifiable, Sendable {
        case left, right

        var id: String { rawValue }

        /// The picker's word.
        var label: String {
            switch self {
            case .left: "Left"
            case .right: "Right"
            }
        }
    }

    /// Between the window's edge and the map's — the distance the first-open
    /// placement has always used.
    static let gap: CGFloat = 8

    /// Where a map of `panelWidth` goes when bolted to `side` of a window whose
    /// frame is `host`: flush against that edge, top-aligned, the window's
    /// height — or `minimumHeight`, hanging below, when the window is shorter
    /// than the map may be. Both rectangles are window frames in screen
    /// coordinates, title bars included, so the two title bars line up.
    static func frame(
        host: CGRect, side: Side, panelWidth: CGFloat, minimumHeight: CGFloat
    ) -> CGRect {
        let height = max(host.height, minimumHeight)
        let x: CGFloat = switch side {
        case .right: host.maxX + gap
        case .left: host.minX - gap - panelWidth
        }
        return CGRect(x: x, y: host.maxY - height, width: panelWidth, height: height)
    }
}
