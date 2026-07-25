import SwiftUI

/// Radio connection, live frequency/mode, WPM, and keying backend. Control
/// clusters sit in a wrapping FlowLayout, so narrowing the window (or
/// widening the score panel) reflows them onto more rows instead of
/// clipping or truncating.
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
            if descriptor?.supportsDirectKeying ?? true {
                keyerGroup
            }
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

    private var connectButton: some View {
        Button(radio.isConnected ? "Disconnect" : "Connect") {
            if radio.isConnected {
                radio.disconnect()
            } else {
                radio.connectManually(settings: settings)
            }
        }
        .fixedSize()
        .tint(radio.isConnected ? .red : .accentColor)
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

    private var keyerGroup: some View {
        captioned("Keyer") {
            Picker("", selection: $settings.keyerBackend) {
                ForEach(AppSettings.KeyerBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName(for: radio.connectedDescriptor)).tag(backend)
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
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

    @ViewBuilder
    private var frequencyDisplay: some View {
        if let state = radio.radioState {
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
        } else {
            Text("No radio")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
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
