import Foundation
import Observation

/// Live spot collection: the newest spot per call+band, aged out after
/// 15 minutes (contest spots go stale fast).
@MainActor
@Observable
final class SpotStore {

    /// How long a spot stays before ageing out, in minutes (operator setting).
    var maxAgeMinutes: Int = 15

    private var maxAge: TimeInterval { Double(max(1, maxAgeMinutes)) * 60 }

    private(set) var all: [Spot] = []

    func add(_ spot: Spot) {
        all.removeAll { $0.id == spot.id }
        all.append(spot)
        // Age out relative to the newest spot we know about, not this one —
        // a bulk sh/dx reply arrives with older spots mixed in.
        purge(now: all.map(\.receivedAt).max() ?? spot.receivedAt)
    }

    func purge(now: Date) {
        all.removeAll { now.timeIntervalSince($0.receivedAt) > maxAge }
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
    nonisolated static func next(in sorted: [Spot], afterKHz: Double, direction: Direction) -> Spot? {
        guard !sorted.isEmpty else { return nil }
        let tolerance = 0.05
        switch direction {
        case .up:
            return sorted.first { $0.freqKHz > afterKHz + tolerance } ?? sorted.first
        case .down:
            return sorted.last { $0.freqKHz < afterKHz - tolerance } ?? sorted.last
        }
    }
}
