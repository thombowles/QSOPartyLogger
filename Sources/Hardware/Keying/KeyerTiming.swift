import Foundation

/// Converts Morse elements into a key-down/key-up schedule.
/// Standard (PARIS) timing: dit = 1200 / WPM ms; dah = 3 dits;
/// element gap 1, character gap 3, word gap 7.
enum KeyerTiming {

    struct KeyEvent: Equatable {
        let keyDown: Bool
        let durationMs: Double
    }

    static func ditMs(wpm: Int) -> Double {
        1200.0 / Double(max(1, wpm))
    }

    /// Schedule for a text at a speed. Consecutive gaps merge into one up-period.
    static func schedule(text: String, wpm: Int) -> [KeyEvent] {
        let dit = ditMs(wpm: wpm)
        var out: [KeyEvent] = []

        func appendUp(_ ms: Double) {
            if let last = out.last, !last.keyDown {
                out[out.count - 1] = KeyEvent(keyDown: false, durationMs: last.durationMs + ms)
            } else {
                out.append(KeyEvent(keyDown: false, durationMs: ms))
            }
        }

        for element in MorseCode.elements(for: text) {
            switch element {
            case .dit: out.append(KeyEvent(keyDown: true, durationMs: dit))
            case .dah: out.append(KeyEvent(keyDown: true, durationMs: dit * 3))
            case .elementGap: appendUp(dit)
            case .charGap: appendUp(dit * 3)
            case .wordGap: appendUp(dit * 7)
            }
        }
        return out
    }

    static func totalDurationMs(text: String, wpm: Int) -> Double {
        schedule(text: text, wpm: wpm).reduce(0) { $0 + $1.durationMs }
    }
}
