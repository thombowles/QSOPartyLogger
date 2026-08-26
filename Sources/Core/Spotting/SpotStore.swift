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
        // Your own log ages with the cluster, on the operator's one "Age out
        // after" setting — N1MM has a single spot timeout for the whole map,
        // and a station worked twenty minutes ago has very likely moved.
        // POTA board spots are `replace`d wholesale per poll while the feed
        // runs; this age only fades them once polling stops.
        case .cluster, .local, .pota: maxAge
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

    /// Add only when that call is not already on the map for that band.
    ///
    /// This is how a station you worked but nobody spotted gets there. A spot
    /// that already exists keeps its own reported frequency and simply greys
    /// out: having worked someone is no reason to move another operator's spot
    /// of him, and his frequency is where the spotter says it is.
    func addIfAbsent(_ spot: Spot) {
        guard !all.contains(where: { $0.id == spot.id }) else { return }
        add(spot)
    }

    /// The POTA board is authoritative per poll: a row gone from the feed
    /// is QRT or expired, so its spots are replaced wholesale rather than
    /// aged individually. Other sources are untouched.
    func replace(source: SpotSource, with spots: [Spot]) {
        all.removeAll { $0.source == source }
        for spot in spots { add(spot) }
    }

    func purge(now: Date) {
        all.removeAll { now.timeIntervalSince($0.receivedAt) > maxAge(for: $0.source) }
    }

    /// Drop everything a spotting network provided, keeping the contacts that
    /// came from the operator's own log. Used when an entry declares itself
    /// NON-ASSISTED mid-contest: closing the connection is not enough on its
    /// own, because the spots already drawn would keep the assistance in
    /// front of the operator after the claim says there is none.
    func removeNetworkSpots() {
        all.removeAll { $0.source != .local }
    }

    /// Spots on one band, sorted by frequency (the band-map order).
    func spots(band: Band) -> [Spot] {
        all.filter { $0.band == band }.sorted { $0.freqKHz < $1.freqKHz }
    }

    enum Direction {
        case up, down
    }

    /// Next spot from a frequency within a frequency-sorted list, wrapping at
    /// the band edges (⌘↑ / ⌘↓ navigation). The tolerance skips the spot the
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

    /// The spot the VFO is sitting on: the nearest within `withinHz`, or nil.
    /// This is N1MM's call frame — "if a station on the Bandmap is within
    /// the tuning tolerance, its call will be placed in the Entry window's
    /// call-frame" (Entry window, fetched 2026-08-15).
    ///
    /// Worked stations are included — N1MM shows a dupe in grey so "You can
    /// tune by them more quickly" — but lose a tie to an unworked one. A
    /// superseded call is skipped outright, as `next` skips it. The last
    /// tie-break is the call, so two polls at one frequency agree.
    nonisolated static func nearest(
        in spots: [Spot],
        toKHz vfoKHz: Double,
        withinHz toleranceHz: Int,
        workedCalls: Set<String> = [],
        workedCallCounties: Set<String> = []
    ) -> Spot? {
        // 0.1 Hz of slack: 14040.3 − 14040.0 is 0.30000000000068 in binary.
        let toleranceKHz = Double(toleranceHz) / 1000 + 0.0001
        func distance(_ spot: Spot) -> Double { abs(spot.freqKHz - vfoKHz) }
        func worked(_ spot: Spot) -> Bool {
            SpotFilter.isWorked(spot, workedCalls: workedCalls, workedCallCounties: workedCallCounties)
        }
        return spots
            .filter { !$0.isSuperseded && distance($0) <= toleranceKHz }
            .min { a, b in
                let da = distance(a), db = distance(b)
                if abs(da - db) > 0.0001 { return da < db }
                let aWorked = worked(a), bWorked = worked(b)
                if aWorked != bWorked { return !aWorked }
                return a.call < b.call
            }
    }
}
