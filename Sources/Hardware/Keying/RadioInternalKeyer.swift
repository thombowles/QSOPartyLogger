import Foundation

/// CW via the radio's own keyer — the radio does the element timing.
/// Radio-neutral: it drives whatever driver it is handed through
/// `sendInternalKeyerText` / `stopInternalKeyer`, and is named for those
/// members rather than for any one model's command.
///
/// This path exists only for radios with no control lines to key from
/// (Article 11), which is why it takes an `InternalKeyerDriver` rather than
/// any driver: a radio that *can* be keyed directly is, and never reaches
/// here. Speed changes still have to reach a message already sending, so the
/// `wpm` setter forwards to the radio immediately rather than waiting for the
/// next `send`.
final class RadioInternalKeyer: CWSender, @unchecked Sendable {

    private let driver: any InternalKeyerDriver
    private let lock = NSLock()
    private var _wpm: Int

    var wpm: Int {
        get { lock.withLock { _wpm } }
        set {
            let clamped = min(50, max(8, newValue))
            lock.withLock { _wpm = clamped }
            driver.setKeyerSpeed(wpm: clamped)
        }
    }

    init(driver: any InternalKeyerDriver, wpm: Int = 20) {
        self.driver = driver
        self._wpm = wpm
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        driver.sendInternalKeyerText(trimmed)
    }

    func abort() {
        driver.stopInternalKeyer()
    }
}
