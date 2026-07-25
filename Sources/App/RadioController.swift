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
    /// Keyer speed the radio last reported (its front-panel speed knob) —
    /// observed by the UI to sync `AppSettings.wpm`.
    private(set) var radioReportedWPM: Int?

    var availablePorts: [SerialPortInfo] = []

    private var transport: (any SerialTransport)?
    private var driver: (any RadioDriver)?
    private var directKeyer: CWKeyer?
    private var internalKeyer: RadioInternalKeyer?
    private var sendingClearTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    private(set) var connectedDescriptor: RadioDescriptor?

    /// True while the radio reports TX, or while the app is sending a macro.
    /// A rig in QSK drops its TX flag between CW elements — first seen on a K3,
    /// but a property of QSK rather than of that model — which made the badge
    /// flicker mid-macro. Holding it for the estimated send duration is
    /// unconditional: no radio is special-cased here, and one that reports TX
    /// continuously is unaffected, since it is transmitting either way.
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
        guard let descriptor = RadioRegistry.descriptor(id: settings.radioID) else {
            lastError = "Unknown radio '\(settings.radioID)'."
            return
        }

        let newTransport: any SerialTransport
        switch descriptor.connection {
        case .serial:
            guard !settings.portPath.isEmpty else {
                lastError = "Choose a serial port first."
                return
            }
            let newPort = SerialPort(path: settings.portPath)
            do {
                try newPort.open(baudRate: settings.baudRate)
            } catch {
                lastError = error.localizedDescription
                return
            }
            newTransport = newPort

        case .network(let defaultPort):
            let host = settings.tcpHost.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else {
                lastError = "Enter the radio's IP address or hostname."
                return
            }
            let port = (1...65535).contains(settings.tcpPort) ? UInt16(settings.tcpPort) : defaultPort
            let tcp = TCPTransport(host: host, port: port)
            tcp.onDisconnect = { [weak self] reason in
                Task { @MainActor [weak self] in
                    guard let self, self.isConnected else { return }
                    self.lastError = "Radio connection lost: \(reason)"
                    self.disconnect()
                }
            }
            try? tcp.open(baudRate: 0)  // connects asynchronously; validation reports failures
            newTransport = tcp
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
        newDriver.start(transport: newTransport)

        // Direct DTR/RTS keying only exists on serial radios; network radios
        // always key through the radio's internal keyer.
        if descriptor.supportsDirectKeying {
            let keyer = CWKeyer(transport: newTransport, config: settings.keyerLineConfig, wpm: settings.wpm)
            keyer.onSending = { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.nowSending = text
                }
            }
            directKeyer = keyer
        }

        transport = newTransport
        driver = newDriver
        internalKeyer = RadioInternalKeyer(driver: newDriver, wpm: settings.wpm)
        connectedDescriptor = descriptor
        isConnected = true
    }

    /// Auto-connect on document open. Silently does nothing when the target
    /// isn't configured (or a serial port isn't currently present); otherwise
    /// connects and then verifies the radio actually answers within a few
    /// seconds, surfacing an error if it doesn't.
    func connectAndValidate(settings: AppSettings) {
        guard !isConnected else { return }
        guard let descriptor = RadioRegistry.descriptor(id: settings.radioID) else { return }
        switch descriptor.connection {
        case .serial:
            refreshPorts()
            guard !settings.portPath.isEmpty,
                  availablePorts.contains(where: { $0.path == settings.portPath }) else { return }
        case .network:
            guard !settings.tcpHost.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        }

        connect(settings: settings)
        startValidation(settings: settings)
    }

    /// Manual Connect button. Network radios get the response check too —
    /// a TCP connection to the wrong IP "succeeds" silently otherwise.
    func connectManually(settings: AppSettings) {
        connect(settings: settings)
        if case .network = connectedDescriptor?.connection {
            startValidation(settings: settings)
        }
    }

    private func startValidation(settings: AppSettings) {
        guard isConnected else { return }
        let target: String = switch connectedDescriptor?.connection {
        case .network:
            "\(settings.tcpHost.trimmingCharacters(in: .whitespaces)):\(settings.tcpPort)"
        default:
            (settings.portPath as NSString).lastPathComponent
        }

        validationTask?.cancel()
        validationTask = Task { [weak self] in
            // Serial radios: first poll at +0.2 s, repeating 0.5 s. Network
            // radios: status arrives right after the subscribe. 4 s is
            // generous for both, and is app-layer policy — how long to wait
            // before warning the operator — not a per-radio constant.
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, !Task.isCancelled, self.isConnected else { return }
                if self.radioState != nil { return }  // validated — radio is talking
            }
            guard let self, !Task.isCancelled, self.isConnected, self.radioState == nil else { return }
            let networkHint = if case .network = self.connectedDescriptor?.connection {
                " If macOS asked about finding devices on the local network, allow it (System "
                    + "Settings → Privacy & Security → Local Network → QSO Party Logger)."
            } else {
                ""
            }
            self.lastError = "Connected to \(target), but the radio isn't answering. "
                + "Check power, cable/network, and settings. The connection stays up — the "
                + "frequency display will light up as soon as the radio responds.\(networkHint)"
        }
    }

    func disconnect() {
        validationTask?.cancel()
        validationTask = nil
        directKeyer?.shutdown()
        directKeyer = nil
        internalKeyer = nil
        driver?.stop()
        driver = nil
        transport?.close()
        transport = nil
        connectedDescriptor = nil
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
        // A radio with no control lines has no direct keyer, so it falls back
        // to its own keyer — `supportsDirectKeying` decided that at connect.
        case .direct: directKeyer ?? internalKeyer
        case .radioInternal: internalKeyer
        }
    }

    // MARK: Frequency / mode control (spots, typed QSY commands)

    func setFrequency(kHz: Double) {
        driver?.setFrequency(hz: Int((kHz * 1000).rounded()))
    }

    func setMode(rawMode: String) {
        driver?.setMode(rawMode: rawMode)
    }

    func sendCW(_ text: String, settings: AppSettings) {
        guard isConnected else { return }
        guard let sender = activeSender(settings) else { return }
        sender.wpm = settings.wpm
        sender.send(text)

        // Show "sending" (and hold the TX badge) for the estimated on-air
        // time — works identically for direct keying and the radio's keyer.
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
