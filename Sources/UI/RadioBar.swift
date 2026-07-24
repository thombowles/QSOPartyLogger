import SwiftUI

/// Radio connection, live frequency/mode, WPM, and keying backend — laid out
/// as two compact rows so controls never wrap or truncate at normal widths.
struct RadioBar: View {
    @Bindable var settings: AppSettings
    var radio: RadioController
    let party: PartyDefinition?

    @Binding var manualBand: Band
    @Binding var manualRawMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            connectionRow
            operatingRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    // MARK: Row 1 — connection + live radio state

    private var connectionRow: some View {
        HStack(spacing: 8) {
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

            captioned("Baud") {
                Picker("", selection: $settings.baudRate) {
                    ForEach(RadioRegistry.descriptor(id: settings.radioID)?.baudRates ?? [38400], id: \.self) { rate in
                        Text(String(rate)).tag(rate)
                    }
                }
                .labelsHidden()
                .frame(width: 84)
                .disabled(radio.isConnected)
            }

            Button(radio.isConnected ? "Disconnect" : "Connect") {
                if radio.isConnected {
                    radio.disconnect()
                } else {
                    radio.connect(settings: settings)
                }
            }
            .fixedSize()
            .tint(radio.isConnected ? .red : .accentColor)

            Divider().frame(height: 24)

            frequencyDisplay

            Spacer(minLength: 8)

            if let sending = radio.nowSending {
                Label(sending, systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button("Esc") { radio.abortCW(settings: settings) }
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }

    // MARK: Row 2 — band/mode + keyer

    private var operatingRow: some View {
        HStack(spacing: 8) {
            if radio.radioState == nil {
                captioned("Band") {
                    Picker("", selection: $manualBand) {
                        ForEach(party?.validBands ?? Band.allCases) { band in
                            Text(band.rawValue).tag(band)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 84)
                }
                captioned("Mode") {
                    Picker("", selection: $manualRawMode) {
                        ForEach(Self.rawModes(for: party), id: \.self) { mode in
                            Text(mode).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 84)
                }
                Divider().frame(height: 24)
            }

            Stepper(value: $settings.wpm, in: 8...50) {
                Text("\(settings.wpm) WPM")
                    .monospacedDigit()
                    .fixedSize()
            }
            .fixedSize()
            .onChange(of: settings.wpm) {
                radio.syncWPM(settings.wpm, settings: settings)
            }
            .help("CW speed — ⌘= / ⌘- adjusts by 2 WPM; syncs with the K3 knob")

            captioned("Keyer") {
                Picker("", selection: $settings.keyerBackend) {
                    ForEach(AppSettings.KeyerBackend.allCases, id: \.self) { backend in
                        Text(backend.rawValue).tag(backend)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var frequencyDisplay: some View {
        if let state = radio.radioState {
            HStack(spacing: 8) {
                Text(state.displayFrequency)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .fixedSize()
                Text(state.mode.rawMode)
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
