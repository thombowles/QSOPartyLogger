import Foundation
import Observation

/// Live spot collection: the newest spot per call+band, aged out after
/// 15 minutes (contest spots go stale fast).
@MainActor
@Observable
final class SpotStore {

    /// How long a cluster spot stays before ageing out, in minutes (operator
    /// setting).
    var maxAgeMinutes: Int = 15

    /// The same for hub spots, which are hand-posted rather than skimmer-fed
    /// and stay useful much longer — the hub itself keeps them 60 minutes.
    var hubMaxAgeMinutes: Int = 60

    private var maxAge: TimeInterval { Double(max(1, maxAgeMinutes)) * 60 }

    private func maxAge(for source: SpotSource) -> TimeInterval {
        switch source {
        case .cluster: maxAge
        case .hub: Double(max(1, hubMaxAgeMinutes)) * 60
        }
    }

    private(set) var all: [Spot] = []

    func add(_ spot: Spot) {
        var spot = spot
        // A cluster re-spot of a station the hub already placed in a county
        // must not strip that county: it is what un-hides a rover that has
        // moved, so losing it silently re-hides the best multiplier on the
        // band. The newer report still wins on everything it actually knows.
        if spot.county == nil, let known = all.first(where: { $0.id == spot.id })?.county {
            spot.county = known
        }
        all.removeAll { $0.id == spot.id }
        all.append(spot)
        // Age out relative to the newest spot we know about, not this one —
        // a bulk sh/dx reply arrives with older spots mixed in.
        purge(now: all.map(\.receivedAt).max() ?? spot.receivedAt)
    }

    func purge(now: Date) {
        all.removeAll { now.timeIntervalSince($0.receivedAt) > maxAge(for: $0.source) }
    }

    /// Spots on one band, sorted by frequency (the band-map order).
    func spots(band: Band) -> [Spot] {
        all.filter { $0.band == band }.sorted { $0.freqKHz < $1.freqKHz }
    }

    enum Direction {
        case up, down
    }

    /// Next spot from a frequency within a frequency-sorted list, wrapping at
    /// the band edges (⌘→ / ⌘← navigation). The tolerance skips the spot the
    /// operator is already sitting on.
    ///
    /// Worked stations are stepped over — they stay on the band map, greyed,
    /// but there is nothing left to work on them so the keys do not stop
    /// there. When every spot in the list is worked the result is `nil` and
    /// the radio stays put.
    ///
    /// A spot reporting a county is judged on call+county, so a rover that has
    /// moved comes back into the rotation. A call the board has already
    /// corrected is skipped outright — it is not somewhere to send the radio.
    nonisolated static func next(
        in sorted: [Spot],
        afterKHz: Double,
        direction: Direction,
        workedCalls: Set<String> = [],
        workedCallCounties: Set<String> = []
    ) -> Spot? {
        let workable = sorted.filter {
            !$0.isSuperseded
                && !SpotFilter.isWorked($0, workedCalls: workedCalls,
                                        workedCallCounties: workedCallCounties)
        }
        guard !workable.isEmpty else { return nil }
        let tolerance = 0.05
        switch direction {
        case .up:
            return workable.first { $0.freqKHz > afterKHz + tolerance } ?? workable.first
        case .down:
            return workable.last { $0.freqKHz < afterKHz - tolerance } ?? workable.last
        }
    }
}
