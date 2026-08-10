import SwiftUI

/// Radio connection (with inline status and errors), live frequency/mode,
/// WPM, and keying backend. Control clusters sit in a wrapping FlowLayout,
/// so narrowing the window (or widening the score panel) reflows them onto
/// more rows instead of clipping or truncating.
struct RadioBar: View {
    @Bindable var settings: AppSettings
    var radio: RadioController
    let party: PartyDefinition?

    @Binding var manualBand: Band
    @Binding var manualRawMode: String

    private var descriptor: RadioDescriptor? {
        RadioRegistry.descriptor(id: settings.radioID)
    }

    private var isNetworkRadio: Bool {
        if case .network = descriptor?.connection { true } else { false }
    }

    /// The selected radio's own CAT port, quoted from its descriptor — the
    /// number itself never appears in this layer (Article 10).
    private var portHelp: String {
        if let port = descriptor?.defaultNetworkPort {
            "TCP port — \(port) unless you've changed it"
        } else {
            "TCP port for the radio's CAT interface"
        }
    }

    var body: some View {
        FlowLayout(horizontalSpacing: 10, verticalSpacing: 6) {
            radioGroup
            if isNetworkRadio {
                hostGroup
            } else {
                portGroup
                baudGroup
            }
            connectButton
            frequencyDisplay
            if radio.radioState == nil {
                bandGroup
                modeGroup
            }
            wpmStepper
            if let sending = radio.nowSending {
                sendingIndicator(sending)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    // MARK: Control clusters (flow items)

    private var radioGroup: some View {
        captioned("Radio") {
            Picker("", selection: $settings.radioID) {
                ForEach(RadioRegistry.all) { desc in
                    Text(desc.displayName).tag(desc.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
            .disabled(radio.isConnected)
            // Only reachable while disconnected — picking a different radio
            // retires the previous attempt's inline error.
            .onChange(of: settings.radioID) {
                radio.clearError()
            }
        }
    }

    private var hostGroup: some View {
        captioned("Host") {
            HStack(spacing: 2) {
                TextField("192.168.1.100", text: $settings.tcpHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .disabled(radio.isConnected)
                    .help("Radio IP address or hostname")
                TextField("Port", value: $settings.tcpPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 54)
                    .disabled(radio.isConnected)
                    .help(portHelp)
            }
        }
    }

    private var portGroup: some View {
        captioned("Port") {
            HStack(spacing: 2) {
                Picker("", selection: $settings.portPath) {
                    Text("No port").tag("")
                    ForEach(radio.availablePorts) { port in
                        Text(port.displayName).tag(port.path)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 130, maxWidth: 210)
                .disabled(radio.isConnected)

                Button {
                    radio.refreshPorts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(radio.isConnected)
                .help("Rescan serial ports")
            }
        }
    }

    private var baudGroup: some View {
        captioned("Baud") {
            Picker("", selection: $settings.baudRate) {
                ForEach(descriptor?.baudRates ?? [], id: \.self) { rate in
                    Text(String(rate)).tag(rate)
                }
            }
            .labelsHidden()
            .frame(width: 84)
            .disabled(radio.isConnected)
        }
    }

    /// What the bar's status slot should show — pure, so the truth table is
    /// testable without rendering.
    enum ConnectionStatus: Equatable {
        /// Disconnected, nothing to report: "No radio".
        case idle
        /// Transport up, first answer still pending: progress + text.
        case waiting
        /// Something is wrong: inline summary, full story in the tooltip.
        case trouble(summary: String, detail: String)
        /// The radio is talking: show the frequency display.
        case live
    }

    /// The connect button's label per phase — "Disconnect" is reserved for a
    /// link the radio has actually answered on; an unproven link offers
    /// "Cancel" instead of implying success.
    static func connectButtonTitle(for phase: RadioConnectionPhase) -> String {
        switch phase {
        case .disconnected: "Connect"
        case .waitingForRadio, .unresponsive: "Cancel"
        case .connected: "Disconnect"
        }
    }

    static func status(
        phase: RadioConnectionPhase, error: RadioConnectionError?
    ) -> ConnectionStatus {
        switch phase {
        case .connected:
            .live
        case .waitingForRadio:
            .waiting
        case .unresponsive:
            // The stored error normally exists here; the fallback keeps the
            // warning honest if it was somehow cleared.
            .trouble(summary: error?.summary ?? "Radio not answering", detail: error?.detail ?? "")
        case .disconnected:
            if let error {
                .trouble(summary: error.summary, detail: error.detail)
            } else {
                .idle
            }
        }
    }

    private var connectButton: some View {
        Button(Self.connectButtonTitle(for: radio.connectionPhase)) {
            if radio.isConnected {
                radio.disconnect()
            } else {
                radio.connect(settings: settings)
            }
        }
        .fixedSize()
        .tint(radio.connectionPhase == .connected ? .red : .accentColor)
    }

    private var bandGroup: some View {
        captioned("Band") {
            Picker("", selection: $manualBand) {
                ForEach(party?.validBands ?? Band.allCases) { band in
                    Text(band.rawValue).tag(band)
                }
            }
            .labelsHidden()
            .frame(width: 84)
        }
    }

    private var modeGroup: some View {
        captioned("Mode") {
            Picker("", selection: $manualRawMode) {
                ForEach(Self.rawModes(for: party), id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 84)
        }
    }

    private var wpmStepper: some View {
        Stepper(value: $settings.wpm, in: 8...50) {
            Text("\(settings.wpm) WPM")
                .monospacedDigit()
                .fixedSize()
        }
        .fixedSize()
        .onChange(of: settings.wpm) {
            radio.syncWPM(settings.wpm, settings: settings)
        }
        .help("CW speed — ⌘= / ⌘- adjusts by 2 WPM; syncs with the radio's speed knob")
    }

    private func sendingIndicator(_ sending: String) -> some View {
        HStack(spacing: 6) {
            Label(sending, systemImage: "dot.radiowaves.left.and.right")
                .font(.callout.monospaced())
                .foregroundStyle(.red)
                .lineLimit(1)
                .frame(maxWidth: 260)
            Button("Esc") { radio.abortCW(settings: settings) }
                .controlSize(.small)
                .fixedSize()
        }
    }

    /// The status slot after the connect button: live frequency when the
    /// radio is talking, otherwise what is happening with the link — where
    /// the modal "Radio error" alert used to interrupt instead.
    @ViewBuilder
    private var frequencyDisplay: some View {
        switch Self.status(phase: radio.connectionPhase, error: radio.lastError) {
        case .live:
            if let state = radio.radioState {
                liveDisplay(state)
            }
        case .idle:
            Text("No radio")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
        case .waiting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for radio…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        case .trouble(let summary, let detail):
            Label(summary, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize()
                .help(detail)
                .accessibilityHint(Text(detail))
        }
    }

    private func liveDisplay(_ state: RadioState) -> some View {
        HStack(spacing: 8) {
            Text(state.displayFrequency)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .fixedSize()
            Text(state.rawMode)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            if radio.isTransmitting {
                Text("TX")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            if let band = state.band, let party, !party.validBands.contains(band) {
                Label("\(band.rawValue) not valid for \(party.name)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Manual raw-mode options limited to the party's legal mode classes.
    static func rawModes(for party: PartyDefinition?) -> [String] {
        let classes = party?.allowedModeClasses ?? ModeClass.allCases
        return classes.map { cls in
            switch cls {
            case .cw: "CW"
            case .phone: "SSB"
            case .digital: "RTTY"
            }
        }
    }

    private func captioned(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            content()
        }
    }
}
