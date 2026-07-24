import Foundation
import Observation

/// Glue between the hardware layer and SwiftUI: connection lifecycle, live
/// radio state, and CW sending over the selected backend.
@MainActor
@Observable
final class RadioController {

    private(set) var isConnected = false
    private(set) var radioState: RadioState?
    private(set) var lastError: String?
    private(set) var nowSending: String?
    /// Keyer speed the radio last reported (K3 front-panel knob) — observed
    /// by the UI to sync `AppSettings.wpm`.
    private(set) var radioReportedWPM: Int?

    var availablePorts: [SerialPortInfo] = []

    private var port: SerialPort?
    private var driver: (any RadioDriver)?
    private var directKeyer: CWKeyer?
    private var internalKeyer: K3InternalKeyer?
    private var sendingClearTask: Task<Void, Never>?

    /// The K3 drops its TX flag between CW elements (QSK), which made the TX
    /// badge flicker during macros. Treat "app is sending a macro" as
    /// transmitting for the whole estimated duration.
    var isTransmitting: Bool {
        (radioState?.isTransmitting ?? false) || nowSending != nil
    }

    init() {
        refreshPorts()
    }

    func refreshPorts() {
        availablePorts = SerialPortEnumerator.availablePorts()
    }

    func clearError() {
        lastError = nil
    }

    func connect(settings: AppSettings) {
        disconnect()
        lastError = nil
        guard !settings.portPath.isEmpty else {
            lastError = "Choose a serial port first."
            return
        }
        guard let descriptor = RadioRegistry.descriptor(id: settings.radioID) else {
            lastError = "Unknown radio '\(settings.radioID)'."
            return
        }

        let newPort = SerialPort(path: settings.portPath)
        do {
            try newPort.open(baudRate: settings.baudRate)
        } catch {
            lastError = error.localizedDescription
            return
        }

        let newDriver = descriptor.makeDriver()
        newDriver.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.radioState = state
            }
        }
        newDriver.onKeyerSpeedChange = { [weak self] wpm in
            Task { @MainActor [weak self] in
                self?.radioReportedWPM = wpm
            }
        }
        newDriver.start(transport: newPort)

        let keyer = CWKeyer(transport: newPort, config: settings.keyerLineConfig, wpm: settings.wpm)
        keyer.onSending = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.nowSending = text
            }
        }

        port = newPort
        driver = newDriver
        directKeyer = keyer
        internalKeyer = K3InternalKeyer(driver: newDriver, wpm: settings.wpm)
        isConnected = true
    }

    func disconnect() {
        directKeyer?.shutdown()
        directKeyer = nil
        internalKeyer = nil
        driver?.stop()
        driver = nil
        port?.close()
        port = nil
        isConnected = false
        radioState = nil
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = nil
        radioReportedWPM = nil
    }

    /// Estimated on-air duration of a message at the current speed — used to
    /// schedule the next repeat-CQ transmission for either keyer backend.
    func estimatedSendDuration(_ text: String, settings: AppSettings) -> TimeInterval {
        KeyerTiming.totalDurationMs(text: text, wpm: settings.wpm) / 1000.0
    }

    private func activeSender(_ settings: AppSettings) -> (any CWSender)? {
        switch settings.keyerBackend {
        case .direct: directKeyer
        case .radioInternal: internalKeyer
        }
    }

    func sendCW(_ text: String, settings: AppSettings) {
        guard isConnected else { return }
        guard let sender = activeSender(settings) else { return }
        sender.wpm = settings.wpm
        sender.send(text)

        // Show "sending" (and hold the TX badge) for the estimated on-air
        // time — works identically for direct keying and the K3's KY keyer.
        nowSending = text
        sendingClearTask?.cancel()
        let duration = estimatedSendDuration(text, settings: settings) + 0.2
        sendingClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.nowSending = nil
        }
    }

    func abortCW(settings: AppSettings) {
        activeSender(settings)?.abort()
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = nil
    }

    func syncWPM(_ wpm: Int, settings: AppSettings) {
        directKeyer?.wpm = wpm
        driver?.setKeyerSpeed(wpm: wpm)
    }

    func updateKeyerConfig(settings: AppSettings) {
        directKeyer?.updateConfig(settings.keyerLineConfig)
    }
}
