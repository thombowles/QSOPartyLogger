import Foundation

/// Converts Morse elements into a key-down/key-up schedule.
/// Standard (PARIS) timing: dit = 1200 / WPM ms; dah = 3 dits;
/// element gap 1, character gap 3, word gap 7.
///
/// Schedules are denominated in **dit units, never milliseconds**. A schedule
/// that cannot name a speed cannot bind a stale one, which is what lets
/// `CWKeyer` change speed part-way through a message (Article 11). Speed is
/// applied at playback, one element at a time.
enum KeyerTiming {

    struct KeyEvent: Equatable {
        let keyDown: Bool
        /// Length in dit units. Multiply by `ditMs(wpm:)` to get milliseconds.
        let dits: Double
    }

    static func ditMs(wpm: Int) -> Double {
        1200.0 / Double(max(1, wpm))
    }

    /// Schedule for a text. Consecutive gaps merge into one up-period.
    static func schedule(text: String) -> [KeyEvent] {
        var out: [KeyEvent] = []

        func appendUp(_ dits: Double) {
            if let last = out.last, !last.keyDown {
                out[out.count - 1] = KeyEvent(keyDown: false, dits: last.dits + dits)
            } else {
                out.append(KeyEvent(keyDown: false, dits: dits))
            }
        }

        for element in MorseCode.elements(for: text) {
            switch element {
            case .dit: out.append(KeyEvent(keyDown: true, dits: 1))
            case .dah: out.append(KeyEvent(keyDown: true, dits: 3))
            case .elementGap: appendUp(1)
            case .charGap: appendUp(3)
            case .wordGap: appendUp(7)
            }
        }
        return out
    }

    /// What a schedule would take at one fixed speed. Only honest for a
    /// message whose speed does not change — used for the repeat-CQ interval,
    /// never for deciding when a transmission actually ended.
    static func durationMs(_ events: [KeyEvent], wpm: Int) -> Double {
        events.reduce(0) { $0 + $1.dits } * ditMs(wpm: wpm)
    }

    static func totalDurationMs(text: String, wpm: Int) -> Double {
        durationMs(schedule(text: text), wpm: wpm)
    }
}
