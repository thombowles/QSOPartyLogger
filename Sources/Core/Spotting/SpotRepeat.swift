import Foundation

/// The guard every outgoing spot passes: an identical spot repeated inside
/// this window is a stuck key, not news, and every network a spot goes to is
/// public. A changed frequency, county or park is never a repeat — those are
/// precisely the moments a re-spot matters, and a rover changing county is
/// the thing most often forgotten.
enum SpotRepeat {
    static let window: TimeInterval = 5 * 60

    static func isRepeat<Payload: Equatable>(
        _ payload: Payload, of previous: Payload?, lastSentAt: Date?, now: Date
    ) -> Bool {
        guard let previous, let lastSentAt else { return false }
        guard now.timeIntervalSince(lastSentAt) < window else { return false }
        return payload == previous
    }
}
