import Foundation

/// Band map geometry that does not vary with the label size.
///
/// Here rather than private to `BandMapView` so `SpotLabelSize` can derive its
/// minimum panel width from the same numbers the view lays out with, instead of
/// restating them somewhere they can drift.
enum BandMapMetrics {
    /// The frequency ruler gutter down the left edge.
    static let rulerWidth: Double = 46
    /// Gap between the ruler and the first label column.
    static let labelInset: Double = 8
    /// Narrowest the panel is allowed to be at any label size.
    static let floorPanelWidth: Double = 190
}

/// How big spot labels are drawn on the band map.
///
/// A label size is never only a font size. The column pitch, the row clearance
/// and the centring offset are all statements about how wide and how tall a
/// callsign is drawn — grow the font and leave them behind and the labels
/// overlap. So each preset carries its own, and the view reads all of them off
/// the size rather than holding constants of its own.
///
/// The numbers are a literal table, not a formula. They do hold consistent
/// ratios — pitch is six times the call size, clearance about 1.3 times, the
/// county badge about 0.8 — but `small` has to reproduce what `BandMapView`
/// hardcoded before this setting existed, exactly, and a formula manages that
/// only by coincidence of rounding. Written out, "the default changes nothing"
/// is a fact a test can assert.
///
/// Raw values are the persisted UserDefaults tokens. They are storage, never
/// display: renaming one silently resets an operator's chosen size on next
/// launch. Labels come from `segmentLabel` and `displayName`.
enum SpotLabelSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case huge

    var id: String { rawValue }

    /// One preset's numbers, resolved together so the four accessors below
    /// cannot fall out of step with each other.
    private struct Metrics {
        let call: Double
        let county: Double
        let columnWidth: Double
        let rowHeight: Double
    }

    private var metrics: Metrics {
        switch self {
        case .small:  Metrics(call: 10, county: 8,  columnWidth: 60, rowHeight: 13)
        case .medium: Metrics(call: 12, county: 10, columnWidth: 72, rowHeight: 16)
        case .large:  Metrics(call: 14, county: 11, columnWidth: 84, rowHeight: 18)
        case .huge:   Metrics(call: 16, county: 13, columnWidth: 96, rowHeight: 21)
        }
    }

    /// Callsign font size.
    var callPointSize: Double { metrics.call }

    /// County badge font size — only hub spots carry a county.
    var countyPointSize: Double { metrics.county }

    /// Horizontal pitch between label columns: a six-character call at this
    /// size plus its dot, with room to breathe.
    var columnWidth: Double { metrics.columnWidth }

    /// Vertical clearance one label needs before the next may share a column.
    var rowHeight: Double { metrics.rowHeight }

    /// Half a row of clearance less half a point — the relation the original
    /// `- 6` against a 13 pt row already encoded. Labels are drawn from their
    /// top-left corner, so this lifts one onto its own frequency line.
    var verticalOffset: Double { rowHeight / 2 - 0.5 }

    /// Narrowest the panel may be at this size.
    ///
    /// Two label columns always have to fit. At one column every collision
    /// falls through to `BandMapLayout`'s push-down branch and labels leave
    /// their true frequency — the exact failure sideways stacking was built to
    /// prevent. A 96 pt pitch in the panel's original 230 pt would do it.
    var minimumPanelWidth: Double {
        max(BandMapMetrics.floorPanelWidth,
            BandMapMetrics.rulerWidth + BandMapMetrics.labelInset + 2 * columnWidth)
    }

    /// Segmented-picker label — terse, to match the span picker beside it.
    var segmentLabel: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .huge: "XL"
        }
    }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }
}
