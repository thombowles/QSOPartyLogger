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

    var availablePorts: [SerialPortInfo] = []

    private var port: SerialPort?
    private var driver: (any RadioDriver)?
    private var directKeyer: CWKeyer?
    private var internalKeyer: K3InternalKeyer?

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
        nowSending = nil
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
    }

    func abortCW(settings: AppSettings) {
        activeSender(settings)?.abort()
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
