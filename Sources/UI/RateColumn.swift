import Foundation

/// How a `RateMeter.Reading` reads in the score card's right-hand column —
/// four labels, four values, four tooltips, and no SwiftUI, so the wording is
/// testable and `ScoreSidebar` stays a layout.
///
/// The one rule the whole column obeys: **a count always shows a number; an
/// extrapolation with nothing behind it shows an em dash and says why.** Zero
/// QSOs in the last hour is the most actionable thing this column can report,
/// so it is never blanked — while a confident figure derived from one contact
/// is not a measurement, and printing it anyway is the failure that makes a
/// rate meter worse than none.
enum RateColumn {

    struct Row: Identifiable, Equatable {
        var id: String { label }
        var label: String
        var value: String
        var help: String
    }

    /// Shown wherever there is not yet enough to extrapolate from.
    static let noFigure = "—"

    static func rows(_ reading: RateMeter.Reading) -> [Row] {
        [
            lastTen(reading.lastTen),
            trailingHour(reading.lastHour),
            clockHour(reading.thisHour),
            onAir(reading.onAir),
        ]
    }

    private static func lastTen(_ rate: Int?) -> Row {
        Row(
            label: "Last 10",
            value: rate.map(String.init) ?? noFigure,
            help: rate.map {
                "\($0)/hr across the last ten QSOs, measured to now — so it falls "
                    + "away while you are off the air rather than reporting a run "
                    + "that has already died."
            } ?? "Rate across the last ten QSOs. Needs at least two contacts to measure."
        )
    }

    private static func trailingHour(_ count: Int) -> Row {
        Row(
            label: "60 min",
            value: String(count),
            help: "\(count) QSO\(count == 1 ? "" : "s") in the last 60 minutes — "
                + "a count of what happened, not a projection."
        )
    }

    private static func clockHour(_ hour: RateMeter.ThisHour) -> Row {
        var help = "\(hour.count) QSO\(hour.count == 1 ? "" : "s") so far this UTC "
            + "clock hour, \(hour.minutesElapsed) minutes in"
        if let projected = hour.projected {
            help += " — on pace for \(projected)."
        } else {
            help += ". Too early in the hour to project a finish."
        }
        return Row(
            label: "Hour",
            value: hour.projected.map { "\(hour.count)→\($0)" } ?? String(hour.count),
            help: help
        )
    }

    private static func onAir(_ rate: Int?) -> Row {
        Row(
            label: "On air",
            value: rate.map(String.init) ?? noFigure,
            help: rate.map {
                "\($0)/hr averaged across time on the air, with breaks of "
                    + "30 minutes or more excluded."
            } ?? "Average across time on the air, with breaks of 30 minutes or more "
                + "excluded. Needs five minutes on the air to measure."
        )
    }
}
