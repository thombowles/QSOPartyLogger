import Foundation

/// CW via the radio's own keyer — zero extra wiring; the radio does the
/// element timing. Radio-neutral: it drives whatever driver it is handed
/// through `sendInternalKeyerText` / `stopInternalKeyer`, so the same class
/// serves a K3's `KY` buffer and a Flex's CWX. This is the fallback path:
/// direct DTR/RTS keying is preferred wherever control lines exist
/// (Article 11).
final class RadioInternalKeyer: CWSender, @unchecked Sendable {

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
