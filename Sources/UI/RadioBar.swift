import SwiftUI

/// Radio connection, live frequency/mode, WPM, keying backend, and the
/// manual band/mode pickers used when no radio is attached.
struct RadioBar: View {
    @Bindable var settings: AppSettings
    var radio: RadioController
    let party: PartyDefinition?

    @Binding var manualBand: Band
    @Binding var manualRawMode: String

    var body: some View {
        HStack(spacing: 12) {
            portPicker
            baudPicker
            connectButton

            Divider().frame(height: 22)

            frequencyDisplay

            Divider().frame(height: 22)

            wpmControl
            keyerPicker

            Spacer()

            if let sending = radio.nowSending {
                Label(sending, systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout.monospaced())
                    .foregroundStyle(.red)
                Button("Esc") { radio.abortCW(settings: settings) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    private var portPicker: some View {
        HStack(spacing: 4) {
            Picker("Port", selection: $settings.portPath) {
                Text("No port").tag("")
                ForEach(radio.availablePorts) { port in
                    Text(port.displayName).tag(port.path)
                }
            }
            .frame(maxWidth: 220)
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

    private var baudPicker: some View {
        Picker("Baud", selection: $settings.baudRate) {
            ForEach(RadioRegistry.descriptor(id: settings.radioID)?.baudRates ?? [38400], id: \.self) { rate in
                Text("\(rate)").tag(rate)
            }
        }
        .frame(width: 110)
        .disabled(radio.isConnected)
    }

    private var connectButton: some View {
        Button(radio.isConnected ? "Disconnect" : "Connect") {
            if radio.isConnected {
                radio.disconnect()
            } else {
                radio.connect(settings: settings)
            }
        }
        .tint(radio.isConnected ? .red : .accentColor)
    }

    @ViewBuilder
    private var frequencyDisplay: some View {
        if let state = radio.radioState {
            HStack(spacing: 8) {
                Text(state.displayFrequency)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                Text(state.mode.rawMode)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                if state.isTransmitting {
                    Text("TX")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
                if let band = state.band, let party, !party.validBands.contains(band) {
                    Label("\(band.rawValue) not valid for \(party.name)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            HStack(spacing: 6) {
                Picker("Band", selection: $manualBand) {
                    ForEach(party?.validBands ?? Band.allCases) { band in
                        Text(band.rawValue).tag(band)
                    }
                }
                .frame(width: 100)
                Picker("Mode", selection: $manualRawMode) {
                    ForEach(Self.rawModes(for: party), id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .frame(width: 96)
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

    private var wpmControl: some View {
        Stepper(value: $settings.wpm, in: 8...50) {
            Text("\(settings.wpm) WPM").monospacedDigit()
        }
        .onChange(of: settings.wpm) {
            radio.syncWPM(settings.wpm, settings: settings)
        }
    }

    private var keyerPicker: some View {
        Picker("Keyer", selection: $settings.keyerBackend) {
            ForEach(AppSettings.KeyerBackend.allCases, id: \.self) { backend in
                Text(backend.rawValue).tag(backend)
            }
        }
        .frame(width: 190)
    }
}
