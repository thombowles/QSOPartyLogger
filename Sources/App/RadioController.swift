import Foundation
import Observation

/// Where the radio link stands, as one value the radio bar can render.
/// Top-level (not nested in `RadioController`) so nonisolated UI helpers can
/// touch it — a type nested in a `@MainActor` class inherits the isolation.
enum RadioConnectionPhase: Sendable {
    /// No transport. The button reads "Connect".
    case disconnected
    /// Transport is up, nothing heard yet, validation clock still running.
    case waitingForRadio
    /// The validation window elapsed without a word from the radio. The
    /// link stays up — a late answer still promotes to `.connected`.
    case unresponsive
    /// The radio has actually answered — the only state that earns
    /// a "Disconnect" button.
    case connected
}

/// A connection problem, shaped for the radio bar: `summary` fits inline,
/// `detail` feeds the tooltip.
struct RadioConnectionError: Equatable, Sendable {
    var summary: String
    var detail: String
}

/// Glue between the hardware layer and SwiftUI: connection lifecycle, live
/// radio state, and CW sending over the selected backend.
@MainActor
@Observable
final class RadioController {

    typealias ConnectionPhase = RadioConnectionPhase
    typealias ConnectionError = RadioConnectionError

    private(set) var isConnected = false
    private(set) var radioState: RadioState?
    private(set) var lastError: ConnectionError?
    /// How long a silent radio gets before `.unresponsive` — app-layer
    /// policy, not a per-radio constant. Tunable so tests need not wait 4 s.
    var validationWindow: TimeInterval = 4
    /// Set by the validation task when the window closes unanswered.
    private var validationExpired = false

    /// The error shown when the validation window closes unanswered —
    /// separated out so the wording is testable without a transport.
    static func unresponsiveError(target: String, isNetwork: Bool) -> ConnectionError {
        let networkHint = isNetwork
            ? " If macOS asked about finding devices on the local network, allow it (System "
                + "Settings → Privacy & Security → Local Network → QSO Party Logger)."
            : ""
        return ConnectionError(
            summary: "Radio not answering",
            detail: "Connected to \(target), but the radio isn't answering. "
                + "Check power, cable/network, and settings. The connection stays up — the "
                + "frequency display will light up as soon as the radio responds.\(networkHint)"
        )
    }

    /// Pure phase derivation — the truth table behind `connectionPhase`.
    /// A radio that has answered is connected even if the validation clock
    /// ran out first: a late answer wins.
    static func phase(
        transportUp: Bool, radioAnswered: Bool, validationExpired: Bool
    ) -> ConnectionPhase {
        guard transportUp else { return .disconnected }
        if radioAnswered { return .connected }
        return validationExpired ? .unresponsive : .waitingForRadio
    }

    var connectionPhase: ConnectionPhase {
        Self.phase(
            transportUp: isConnected,
            radioAnswered: radioState != nil,
            validationExpired: validationExpired
        )
    }
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
        guard let descriptor = RadioRegistry.descriptor(id: settings.radioID) else {
            lastError = ConnectionError(
                summary: "Unknown radio",
                detail: "No radio matches the saved id '\(settings.radioID)'. "
                    + "Pick a radio in the radio bar and connect again."
            )
            return
        }

        let newTransport: any SerialTransport
        switch descriptor.connection {
        case .serial:
            guard !settings.portPath.isEmpty else {
                lastError = ConnectionError(
                    summary: "No serial port selected",
                    detail: "Choose a serial port in the radio bar, then Connect. "
                        + "The ⟳ button rescans if the adapter was just plugged in."
                )
                return
            }
            let newPort = SerialPort(path: settings.portPath)
            do {
                try newPort.open(baudRate: settings.baudRate)
            } catch {
                lastError = ConnectionError(
                    summary: "Couldn't open port",
                    detail: error.localizedDescription
                )
                return
            }
            newTransport = newPort

        case .network(let defaultPort):
            let host = settings.tcpHost.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else {
                lastError = ConnectionError(
                    summary: "No radio address",
                    detail: "Enter the radio's IP address or hostname in the radio bar, "
                        + "then Connect."
                )
                return
            }
            let port = (1...65535).contains(settings.tcpPort) ? UInt16(settings.tcpPort) : defaultPort
            let tcp = TCPTransport(host: host, port: port)
            tcp.onDisconnect = { [weak self] reason in
                Task { @MainActor [weak self] in
                    self?.transportDidDisconnect(reason: reason)
                }
            }
            try? tcp.open(baudRate: 0)  // connects asynchronously; validation reports failures
            newTransport = tcp
        }

        let newDriver = descriptor.makeDriver()
        newDriver.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.driverDidReportState(state)
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

        // Every connect gets the response check. A TCP connection to the
        // wrong IP "succeeds" silently, and an opened serial port with a
        // powered-off radio looks identical — the phase (and the bar) must
        // say which link actually proved out.
        startValidation(settings: settings)
    }

    /// Auto-connect on document open. Silently does nothing when the target
    /// isn't configured (or a serial port isn't currently present); otherwise
    /// connects — and `connect` verifies the radio actually answers.
    func autoConnect(settings: AppSettings) {
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
    }

    /// The transport dropped out from under us (TCP reset, remote close).
    /// Tear down first, then record why: `disconnect()` wipes the slate, and
    /// an involuntary drop is the one story that must survive it. A late
    /// callback after a deliberate disconnect is not news and stays silent.
    func transportDidDisconnect(reason: String) {
        guard isConnected else { return }
        disconnect()
        lastError = ConnectionError(
            summary: "Connection lost",
            detail: "Radio connection lost: \(reason)"
        )
    }

    /// Single funnel for driver state updates. The first word from the radio
    /// is what "connected" means, so it also retires any silence warning.
    /// Updates already in flight when the link went down are dropped — they
    /// must not resurrect the frequency display or wipe a loss error.
    func driverDidReportState(_ state: RadioState) {
        guard isConnected else { return }
        radioState = state
        lastError = nil
    }

    private func startValidation(settings: AppSettings) {
        guard isConnected else { return }
        let target: String = switch connectedDescriptor?.connection {
        case .network:
            "\(settings.tcpHost.trimmingCharacters(in: .whitespaces)):\(settings.tcpPort)"
        default:
            (settings.portPath as NSString).lastPathComponent
        }
        let isNetwork = if case .network = connectedDescriptor?.connection { true } else { false }

        validationTask?.cancel()
        // Serial radios: first poll at +0.2 s, repeating 0.5 s. Network
        // radios: status arrives right after the subscribe. The default 4 s
        // window is generous for both.
        let deadline = Date().addingTimeInterval(validationWindow)
        validationTask = Task { [weak self] in
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, !Task.isCancelled, self.isConnected else { return }
                if self.radioState != nil { return }  // validated — radio is talking
            }
            guard let self, !Task.isCancelled, self.isConnected, self.radioState == nil else { return }
            self.validationExpired = true
            self.lastError = Self.unresponsiveError(target: target, isNetwork: isNetwork)
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
        // A deliberate disconnect is a clean slate — Cancel on a silent radio
        // must not leave its warning behind. Involuntary drops re-set their
        // error *after* calling this (`transportDidDisconnect`).
        lastError = nil
        validationExpired = false
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
