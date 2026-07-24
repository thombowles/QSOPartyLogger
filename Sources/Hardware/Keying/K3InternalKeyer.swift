import Foundation

/// CW via the K3's internal keyer (`KY` command) — zero extra wiring; the
/// radio does the element timing.
final class K3InternalKeyer: CWSender, @unchecked Sendable {

    private let driver: any RadioDriver
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

    init(driver: any RadioDriver, wpm: Int = 20) {
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
