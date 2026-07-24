import Foundation
import Observation

/// Live spot collection: the newest spot per call+band, aged out after
/// 15 minutes (contest spots go stale fast).
@MainActor
@Observable
final class SpotStore {

    static let maxAge: TimeInterval = 15 * 60

    private(set) var all: [Spot] = []

    func add(_ spot: Spot) {
        all.removeAll { $0.id == spot.id }
        all.append(spot)
        purge(now: spot.receivedAt)
    }

    func purge(now: Date) {
        all.removeAll { now.timeIntervalSince($0.receivedAt) > Self.maxAge }
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
