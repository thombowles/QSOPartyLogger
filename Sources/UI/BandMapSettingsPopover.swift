import SwiftUI

/// The band map's settings in three short pages — which spots, how the knob
/// is followed, where the window is — instead of one tall popover that had
/// to be dragged to be read. The page is remembered.
enum BandMapSettingsTab: String, CaseIterable, Identifiable {
    case spots, tuning, window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spots: "Spots"
        case .tuning: "Tuning"
        case .window: "Window"
        }
    }

    static let defaultTab: BandMapSettingsTab = .spots
}

/// A popover rather than a Menu: macOS dismisses a menu on every click, so
/// ticking three bands meant reopening it three times, and a Picker inside
/// a menu hides its current value. Each page is its own seam for the
/// type-checker's budget, like the sections were.
struct BandMapSettingsPopover: View {
    let model: BandMapModel
    @Binding var isPresented: Bool
    @AppStorage("bandMapSettingsTab") private var tab: BandMapSettingsTab = BandMapSettingsTab.defaultTab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Band Map")
                .font(.headline)
            Picker("", selection: $tab) {
                ForEach(BandMapSettingsTab.allCases) { page in
                    Text(page.label).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Spots — which spots the map shows. Tuning — how the map follows the knob. "
                  + "Window — labels, and where the map's window is.")

            Divider()
            switch tab {
            case .spots: spotsPage
            case .tuning: tuningPage
            case .window: windowPage
            }

            Divider()
            HStack {
                resetButton
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(width: 330)
    }

    // MARK: Spots

    @ViewBuilder
    private var spotsPage: some View {
        @Bindable var settings = model.settings
        Text("SPOT FILTERS")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        Toggle("North American stations only", isOn: $settings.northAmericanStationsOnly)
            .help("Hide spots of DX stations — a state QSO party exchange comes from NA")
        Toggle("North American spotters only", isOn: $settings.northAmericanSpottersOnly)
            .help("Hide spots posted from outside North America")
        Toggle("Hide stations already worked", isOn: $settings.hideWorkedSpots)
            .help("Drop worked calls from the map entirely — off, they stay greyed out and ⌘↑ / ⌘↓ steps over them")
        Toggle("Hide RBN / skimmer spots", isOn: $settings.hideSkimmerSpots)
            .help("Drop automated skimmer spots (\"-#\" nodes and dB/WPM reports)")
        Toggle("QSO Party Hub spots only", isOn: hubOnlyBinding(settings: settings))
            .help("A cluster carries hundreds of spots against the hub's handful — "
                + "this isolates the ones that name a county when you're hunting multipliers")
        Toggle("POTA spots in contest logs", isOn: $settings.potaSpotsInParties)
            .help("The POTA activator board as a spot source while a party log is "
                + "front — a POTA log always hunts and ignores this. Receiving "
                + "spots is assistance; the assisted-category rules apply.")
        Toggle("Offer the spotted county as the exchange",
               isOn: $settings.prefillExchangeFromSpots)
            .help("Tuning to a hub spot puts its county in the exchange field, shown "
                + "as unconfirmed until you copy it yourself — a spotter's county is "
                + "their claim, and a wrong one is cross-checked against the other log")

        Divider()
        modesAndBands

        Divider()
        HStack {
            Text("Age out after")
            Spacer()
            Picker("", selection: $settings.spotMaxAgeMinutes) {
                ForEach(Self.ageChoices, id: \.self) { minutes in
                    Text(Self.ageLabel(minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .frame(width: 96)
        }
    }

    @ViewBuilder
    private var modesAndBands: some View {
        @Bindable var settings = model.settings
        Text("MODES")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        HStack(spacing: 14) {
            ForEach(ModeClass.allCases) { mode in
                Toggle(mode.displayName, isOn: modeBinding(mode, settings: settings))
            }
        }

        Divider()
        HStack {
            Text("BANDS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("All") { settings.spotBands = [] }
                .controlSize(.small)
                .disabled(settings.spotBands.isEmpty)
        }
        FlowLayout(horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(model.partyBands) { band in
                Toggle(band.rawValue, isOn: bandBinding(band, settings: settings))
            }
        }
    }

    // MARK: Tuning

    @ViewBuilder
    private var tuningPage: some View {
        @Bindable var settings = model.settings
        Text("BAND PLAN")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        Toggle("Follow band plan on QSY", isOn: $settings.followBandPlan)
            .help("Switch the radio between CW and SSB to match the band plan when you tune from the app — clicking a spot, typing a frequency, ⌘↑ / ⌘↓, ⌘J. Turning the VFO knob never changes your mode.")

        Divider()
        tuningSection
    }

    // MARK: Window

    @ViewBuilder
    private var windowPage: some View {
        @Bindable var settings = model.settings
        Text("SPOT LABELS")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        Picker("", selection: $settings.spotLabelSize) {
            ForEach(SpotLabelSize.allCases) { size in
                Text(size.segmentLabel).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(Self.labelSizeHelp)

        Divider()
        windowSection
    }

    // MARK: Reset — the page's own

    /// Each page resets its own settings: the Spots page its filters, the
    /// Tuning page how the knob is followed. The Window page has nothing to
    /// reset — the label size and the bolt are about the operator's eyes
    /// and desk, not about which spots show.
    @ViewBuilder
    private var resetButton: some View {
        let settings = model.settings
        switch tab {
        case .spots:
            Button("Reset Filters") {
                settings.northAmericanSpottersOnly = false
                settings.northAmericanStationsOnly = false
                settings.hideWorkedSpots = false
                settings.hideSkimmerSpots = false
                settings.spotModes = []
                settings.spotBands = []
                settings.spotMaxAgeMinutes = 15
            }
            .disabled(!model.filtersActive && settings.spotMaxAgeMinutes == 15)
        case .tuning:
            Button("Reset Tuning") {
                settings.followBandPlan = true
                settings.callFrameEnabled = true
                settings.autoLeaveRun = true
                settings.autoReturnToRun = true
                settings.tuningToleranceHz = .defaultTolerance
                settings.leaveRunDistanceHz = .defaultLeaveRun
            }
            .disabled(settings.followBandPlan && tuningAtDefaults)
        case .window:
            EmptyView()
        }
    }

    /// WINDOW — the map fastened to the side of its own log window, or free.
    /// Its own seam, like `tuningSection`, for the popover's type-checker
    /// budget. Outside **Reset All**, like the label size: this is about
    /// where the window is, not which spots are on it.
    @ViewBuilder
    private var windowSection: some View {
        @Bindable var settings = model.settings
        Text("WINDOW")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        Toggle("Bolt to the log window", isOn: $settings.bandMapBolted)
            .help("Fasten the map to the side of its own log window — it moves, raises and "
                  + "hides with the window and cannot be dragged off. Free, it is an ordinary "
                  + "window at the log's level, wherever you last put it (⇧⌘B)")
            .shortcutHint("⇧⌘B")
        Picker("", selection: $settings.bandMapBoltSide) {
            ForEach(BandMapBolt.Side.allCases) { side in
                Text(side.label).tag(side)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!settings.bandMapBolted)
        .help("Which side of the log window the map is bolted to — right continues the "
              + "score sidebar's column; left is for a window against the screen's right edge")
    }

    /// TUNING — how the app follows the knob: the ghost call, leaving and
    /// returning to Run, and the two distances per mode. Its own seam so the
    /// popover's one expression stays inside the type-checker's budget.
    @ViewBuilder
    private var tuningSection: some View {
        @Bindable var settings = model.settings
        Text("TUNING")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        Toggle("Show the spot under the VFO as a ghost call (S&P)", isOn: $settings.callFrameEnabled)
            .help("Searching, the nearest visible spot within the tuning tolerance appears in "
                  + "the empty call field in the map's colour for it — Space, or Return under "
                  + "ESM, takes it and its county. Tuning further than the tolerance away erases "
                  + "a call the app put there; typed text is never touched. N1MM's call frame.")
        Toggle("Leave Run when the VFO moves off your CQ frequency", isOn: $settings.autoLeaveRun)
            .help("Past the leave-Run distance below you are hunting, so the mode goes to S&P — "
                  + "a QRM dodge inside it keeps you in Run. F1 in Run remembers the CQ frequency; "
                  + "⌘J jumps back to it. Leaving Run stops Repeat CQ.")
        Toggle("Return to Run when it comes back", isOn: $settings.autoReturnToRun)
            .help("Tuning back within the tolerance of your CQ frequency puts you in Run again — "
                  + "N1MM's default. Off, only F1, ⌘R and ⌘J switch to Run "
                  + "(N1MM's \"Do not automatically switch to Run on CQ-frequency\").")
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("")
                ForEach(ModeClass.allCases) { mode in
                    Text(mode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Spot within").font(.caption)
                ForEach(ModeClass.allCases) { mode in
                    distancePicker(
                        binding: toleranceBinding(mode, settings: settings),
                        choices: Self.toleranceChoices
                    )
                }
            }
            GridRow {
                Text("Leave Run at").font(.caption)
                ForEach(ModeClass.allCases) { mode in
                    distancePicker(
                        binding: leaveRunBinding(mode, settings: settings),
                        choices: Self.leaveRunChoices
                    )
                }
            }
        }
        .help("The tuning tolerance (N1MM's Configurer keeps one per mode, 300 Hz each; "
              + "phone is wider here because SSB spots are posted to the kHz) and how far off "
              + "your CQ frequency counts as leaving it.")
    }

    private static let toleranceChoices = [100, 200, 300, 500, 1000, 2000]
    private static let leaveRunChoices = [500, 1000, 2000, 3000, 5000, 10000]

    private var tuningAtDefaults: Bool {
        let settings = model.settings
        return settings.callFrameEnabled && settings.autoLeaveRun && settings.autoReturnToRun
            && settings.tuningToleranceHz == .defaultTolerance
            && settings.leaveRunDistanceHz == .defaultLeaveRun
    }

    private static func hzLabel(_ hz: Int) -> String {
        hz < 1000 ? "\(hz) Hz" : String(format: "%g kHz", Double(hz) / 1000)
    }

    /// A menu of the usual values — plus whatever is stored, so a hand-edited
    /// preference still shows rather than a blank control.
    private func distancePicker(binding: Binding<Int>, choices: [Int]) -> some View {
        let all = choices.contains(binding.wrappedValue) ? choices : (choices + [binding.wrappedValue]).sorted()
        return Picker("", selection: binding) {
            ForEach(all, id: \.self) { hz in
                Text(Self.hzLabel(hz)).tag(hz)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 70)
    }

    private func toleranceBinding(_ mode: ModeClass, settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.tuningToleranceHz.hz(for: mode) },
            set: { settings.tuningToleranceHz.set($0, for: mode) }
        )
    }

    private func leaveRunBinding(_ mode: ModeClass, settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.leaveRunDistanceHz.hz(for: mode) },
            set: { settings.leaveRunDistanceHz.set($0, for: mode) }
        )
    }

    /// Built from the presets rather than written out, so the point sizes in
    /// the tooltip cannot drift from the table in `SpotLabelSize`.
    private static let labelSizeHelp: String = {
        let sizes = SpotLabelSize.allCases
            .map { "\($0.segmentLabel) \(Int($0.callPointSize)) pt" }
            .joined(separator: ", ")
        return "Callsign size on the band map — \(sizes). Bigger labels need wider "
            + "columns to stack a pile-up sideways, so the panel's minimum width "
            + "grows with the size."
    }()

    private static let ageChoices = [5, 10, 15, 30, 60, 120]

    private static func ageLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr"
    }

    /// Empty set means "all", so materialise the full set before removing an
    /// entry — otherwise unticking the first item would do nothing.
    /// Restricting to the hub is a one-way toggle rather than a per-source
    /// checklist: "cluster only" is what turning the hub off already does.
    private func hubOnlyBinding(settings: AppSettings) -> Binding<Bool> {
        Binding(
            get: { settings.spotSources == [.hub] },
            set: { settings.spotSources = $0 ? [.hub] : [] }
        )
    }

    private func modeBinding(_ mode: ModeClass, settings: AppSettings) -> Binding<Bool> {
        Binding(
            get: { settings.spotModes.isEmpty || settings.spotModes.contains(mode) },
            set: { on in
                var modes = settings.spotModes.isEmpty ? Set(ModeClass.allCases) : settings.spotModes
                if on { modes.insert(mode) } else { modes.remove(mode) }
                settings.spotModes = modes.count == ModeClass.allCases.count ? [] : modes
            }
        )
    }

    private func bandBinding(_ band: Band, settings: AppSettings) -> Binding<Bool> {
        Binding(
            get: { settings.spotBands.isEmpty || settings.spotBands.contains(band) },
            set: { on in
                var bands = settings.spotBands.isEmpty ? Set(model.partyBands) : settings.spotBands
                if on { bands.insert(band) } else { bands.remove(band) }
                settings.spotBands = bands.count == model.partyBands.count ? [] : bands
            }
        )
    }
}
