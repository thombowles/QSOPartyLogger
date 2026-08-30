import SwiftUI
import AppKit

/// Data feed for the band map panel — owned by the contest window (MainView)
/// and kept in sync with its band / worked-calls / CQ state.
@MainActor
@Observable
final class BandMapModel {
    var band: Band = .m20
    var workedCalls: Set<String> = []
    var cqKHz: Double?
    /// Bands the party allows — what the band filter menu offers.
    var partyBands: [Band] = Band.allCases
    /// Modes the active party permits — a spot's mode is inferred against
    /// these, not the generic band plan.
    var allowedModes: [ModeClass] = []
    /// `CALL|COUNTY` pairs already worked on this band and mode.
    var workedCallCounties: Set<String> = []

    /// The active party and log, for deciding whether a spot's county is a
    /// multiplier still worth chasing. Setting either drops the cache.
    var party: PartyDefinition? {
        didSet { dropCaches() }
    }
    var log: ContestLog? {
        didSet { dropCaches() }
    }
    /// Previous contests, and the party's call history file — what a cluster
    /// spot's location is looked up in when it carries none. Set by MainView
    /// wherever it sets the flow's; the file is already checked against the
    /// party there.
    var archiveIndex = StationMemory.Index.empty {
        didSet { dropCaches() }
    }
    var callHistory: CallHistoryFile.Parsed? {
        didSet { dropCaches() }
    }
    /// Deliberately **not** observed. `isNeededMultiplier` runs once per spot
    /// inside the band map's body, and memoises as it goes. Were this an
    /// observed stored property, each render would write it, the write would
    /// invalidate the view, and SwiftUI would render again — a loop that spun
    /// until the stack was gone. It crashed the app on 2026-07-25 with
    /// EXC_BAD_ACCESS between `AppGraph.graphDidChange()` and
    /// `scenesDidChange`. The cache is derived data, so nothing should ever
    /// redraw because it changed; `party` and `log` are observed, and dropping
    /// the cache in their `didSet` is what keeps it honest.
    @ObservationIgnored private var neededMultiplierCache: [String: Bool] = [:]
    /// Call → what the app knows of its location, nil included — the second
    /// memo under the same rule. A dictionary of optionals so "looked up,
    /// nothing known" is remembered too, and not re-derived every render.
    @ObservationIgnored private var locationCache: [String: Located?] = [:]

    private func dropCaches() {
        neededMultiplierCache = [:]
        locationCache = [:]
    }

    /// The log's current multiplier keys, from the window's `LiveScore` —
    /// nil until wired, which keeps the re-scoring path. A closure so the
    /// map can never hold a stale set; `@ObservationIgnored` because it is
    /// wiring, not state.
    @ObservationIgnored var currentMultKeys: () -> Set<ScoreEngine.MultKey>? = { nil }

    var onTuneSpot: ((Spot) -> Void)?
    var onTuneKHz: ((Double) -> Void)?
    /// Right-click → spot this station, to whichever networks apply. Opens
    /// the same confirmation sheet ⇧⌘S does; nothing is ever posted from the
    /// menu.
    var onSpotStation: ((Spot) -> Void)?
    /// Whether a spot has anywhere to go at all — a callsign to post under and
    /// a network on offer. False hides the menu item rather than offering
    /// something that cannot work.
    var canSpot = false

    private let radio: RadioController
    private let spotStore: SpotStore
    /// Held directly so filter changes re-render without any syncing.
    let settings: AppSettings

    init(radio: RadioController, spotStore: SpotStore, settings: AppSettings) {
        self.radio = radio
        self.spotStore = spotStore
        self.settings = settings
    }

    var vfoKHz: Double? {
        radio.radioState.map { Double($0.frequencyHz) / 1000 }
    }

    /// Spots for the displayed band, after the operator's filters. The band
    /// filter still applies: an excluded band shows nothing even when tuned.
    var spots: [Spot] {
        SpotFilter.filter(
            spotStore.spots(band: band),
            options: settings.spotFilterOptions(
                workedCalls: workedCalls, allowedModes: allowedModes,
                workedCallCounties: workedCallCounties
            )
        )
    }

    var filtersActive: Bool {
        settings.spotFilterOptions(
            workedCalls: workedCalls, allowedModes: allowedModes,
            workedCallCounties: workedCallCounties
        ).isActive
    }

    /// Already in the log on this band and mode. `workedCalls` is uppercased at
    /// the source, so the spot's call has to be too — a cluster spot arriving
    /// in mixed case used to slip past this and never grey out.
    ///
    /// A spot reporting a county is judged on call+county: a mobile that has
    /// moved is a new contact, so it un-greys rather than staying struck
    /// through for the rest of the contest.
    func isWorked(_ spot: Spot) -> Bool {
        SpotFilter.isWorked(spot, workedCalls: workedCalls,
                            workedCallCounties: workedCallCounties)
    }

    /// Where a spot's location came from, for the tooltip and for how far to
    /// trust it. A hub or local spot names its own county; a cluster spot is
    /// looked up the way the exchange pre-fill looks the call up.
    enum LocationSource: Equatable, Sendable {
        case spot, thisLog, archive, callHistory

        init(_ source: StationMemory.Source) {
            switch source {
            case .thisLog: self = .thisLog
            case .archive: self = .archive
            case .callHistory: self = .callHistory
            }
        }
    }

    struct LocationVerdict: Equatable, Sendable {
        let location: String
        let source: LocationSource
        /// Whether that location would still add a multiplier on the spot's
        /// band and mode.
        let needed: Bool
    }

    private struct Located: Equatable {
        let location: String
        let source: LocationSource
    }

    /// The location the app knows for this spot's station and whether it is a
    /// multiplier still worth chasing — nil when nothing is known, which the
    /// map draws blue and calls "location unknown".
    ///
    /// A hub or local spot carries a county and uses it: the spot is where he
    /// is *now*, which for a rover outranks where the log last had him. A
    /// cluster spot carries none, so `StationMemory.knownLocation` resolves
    /// the call — this log, the archive, the call history file — the same
    /// chain the exchange pre-fill uses, so a red spot is exactly one whose
    /// county will land in the exchange field.
    ///
    /// `wouldAddMultiplier` honours the party's scored-multiplier ceiling, so
    /// this never sends the operator after a multiplier that pays nothing.
    /// Memoised per call and per location+band+mode; see the caches.
    func verdict(for spot: Spot) -> LocationVerdict? {
        guard let party, let log, let band = spot.band else { return nil }
        let located: Located?
        if let county = spot.county, !county.isEmpty {
            located = Located(location: county, source: .spot)
        } else {
            located = knownLocation(call: spot.call, log: log, party: party)
        }
        guard let located else { return nil }
        let mode = SpotFilter.modeClass(freqKHz: spot.freqKHz, comment: spot.comment,
                                        allowedModes: allowedModes)
        let key = "\(located.location)|\(band.rawValue)|\(mode.rawValue)"
        let needed: Bool
        if let cached = neededMultiplierCache[key] {
            needed = cached
        } else {
            needed = if let current = currentMultKeys() {
                ScoreEngine.wouldAddMultiplier(
                    theirLocs: [located.location], band: band, modeClass: mode,
                    log: log, party: party, current: current
                )
            } else {
                ScoreEngine.wouldAddMultiplier(
                    theirLocs: [located.location], band: band, modeClass: mode, log: log, party: party
                )
            }
            neededMultiplierCache[key] = needed
        }
        return LocationVerdict(location: located.location, source: located.source, needed: needed)
    }

    private func knownLocation(call: String, log: ContestLog, party: PartyDefinition) -> Located? {
        let key = call.uppercased()
        if let cached = locationCache[key] { return cached }
        let role: ExchangeParser.Role = log.myLocation.isInState ? .inState : .outOfState
        let known = StationMemory.knownLocation(
            call: key, log: log.qsos, index: archiveIndex, callHistory: callHistory,
            party: party, role: role
        )
        let located = known.map { Located(location: $0.text, source: LocationSource($0.source)) }
        // updateValue, not subscript assignment: assigning nil would remove
        // the key, and "nothing known" is exactly what is worth remembering.
        locationCache.updateValue(located, forKey: key)
        return located
    }

    /// Whether this spot's county is a multiplier still worth chasing.
    func isNeededMultiplier(_ spot: Spot) -> Bool {
        verdict(for: spot)?.needed ?? false
    }

    /// The colour: grey for worked or superseded, red for a needed
    /// multiplier, blue otherwise. Read by the map for every spot and by the
    /// entry bar for the ghost call, so the two never disagree.
    func status(for spot: Spot) -> SpotStatus {
        if spot.isSuperseded || isWorked(spot) { return .worked }
        return verdict(for: spot)?.needed == true ? .neededMultiplier : .unworked
    }
}

extension SpotStatus {
    /// N1MM's scheme: "Blue: Will be a good QSO, not a multiplier / Red:
    /// Single Multiplier / Gray: Dupe".
    var color: Color {
        switch self {
        case .worked: .secondary
        case .neededMultiplier: .red
        case .unworked: .blue
        }
    }
}

/// N1MM-style band map: vertical frequency ruler for the current band, spots
/// plotted at their frequency, red VFO marker, dashed CQ-frequency marker.
/// Click a spot to tune + pre-fill the call; click empty map to QSY there.
struct BandMapView: View {
    let model: BandMapModel
    @AppStorage("bandMapSpanKHz") private var spanKHz: Double = 50
    @State private var showFilters = false

    private static let spanChoices: [(label: String, kHz: Double)] = [
        ("25", 25), ("50", 50), ("100", 100), ("All", 10_000),
    ]
    private let rulerWidth = CGFloat(BandMapMetrics.rulerWidth)

    /// Everything about how big a spot label is drawn — both font sizes, the
    /// column pitch, the row clearance, the centring offset, and the panel
    /// width that pitch needs. The view keeps no label geometry of its own.
    private var labelSize: SpotLabelSize { model.settings.spotLabelSize }

    private static let minHeight: CGFloat = 280

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geo in
                map(size: geo.size)
            }
        }
        .padding(10)
        .frame(minWidth: CGFloat(labelSize.minimumPanelWidth), minHeight: Self.minHeight)
        .background(
            PanelMinimumSize(
                width: CGFloat(labelSize.minimumPanelWidth), height: Self.minHeight
            )
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.band.rawValue)
                .font(.headline)
                .help("Red — a multiplier you still need. Blue — unworked, not a multiplier "
                      + "(or nobody knows where he is). Grey — worked on this band and mode, "
                      + "or superseded. A cluster spot's county comes from your log, previous "
                      + "contests or the party's call history file — the same places the "
                      + "exchange pre-fill looks.")
            if let vfo = model.vfoKHz {
                Text(String(format: "%.1f", vfo))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Text("no radio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $spanKHz) {
                ForEach(Self.spanChoices, id: \.kHz) { choice in
                    Text(choice.label).tag(choice.kHz)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .help("Visible span in kHz, centered on the VFO")
            filtersButton
        }
    }

    /// Everything that decides which spots appear, next to the spots.
    ///
    /// A popover rather than a Menu: macOS dismisses a menu on every click,
    /// so ticking three bands meant reopening it three times, and a Picker
    /// inside a menu hides its current value.
    private var filtersButton: some View {
        Button {
            showFilters.toggle()
        } label: {
            Image(systemName: model.filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.borderless)
        .help("Filter spots by spotter continent, mode, and band; set how long spots live and whether QSY follows the band plan")
        .popover(isPresented: $showFilters, arrowEdge: .bottom) {
            filtersPopover
        }
    }

    private var filtersPopover: some View {
        @Bindable var settings = model.settings
        return VStack(alignment: .leading, spacing: 10) {
            Text("Band Map")
                .font(.headline)

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

            Divider()
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

            Divider()
            Text("BAND PLAN")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Toggle("Follow band plan on QSY", isOn: $settings.followBandPlan)
                .help("Switch the radio between CW and SSB to match the band plan when you tune from the app — clicking a spot, typing a frequency, ⌘↑ / ⌘↓, ⌘J. Turning the VFO knob never changes your mode.")

            Divider()
            tuningSection

            Divider()
            HStack {
                Button("Reset All") {
                    settings.northAmericanSpottersOnly = false
                    settings.northAmericanStationsOnly = false
                    settings.hideWorkedSpots = false
                    settings.hideSkimmerSpots = false
                    settings.spotModes = []
                    settings.spotBands = []
                    settings.spotMaxAgeMinutes = 15
                    settings.followBandPlan = true
                    settings.callFrameEnabled = true
                    settings.autoLeaveRun = true
                    settings.autoReturnToRun = true
                    settings.tuningToleranceHz = .defaultTolerance
                    settings.leaveRunDistanceHz = .defaultLeaveRun
                }
                .disabled(!model.filtersActive && settings.spotMaxAgeMinutes == 15
                          && settings.followBandPlan && tuningAtDefaults)
                Spacer()
                Button("Done") { showFilters = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(width: 330)
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
                  + "hides with the window and cannot be dragged off, so with two logs open "
                  + "each map sits beside its own. Free, it floats above every window, the "
                  + "other log's included (⇧⌘B)")
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

    private func map(size: CGSize) -> some View {
        let scale = BandMapScale(
            band: model.band,
            centerKHz: model.vfoKHz ?? model.cqKHz,
            spanKHz: spanKHz
        )
        let h = Double(size.height)

        return ZStack(alignment: .topLeading) {
            // Background doubles as click-to-QSY surface.
            Rectangle()
                .fill(.background.secondary)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let kHz = (scale.kHz(atY: Double(value.location.y), height: h) * 10).rounded() / 10
                        model.onTuneKHz?(kHz)
                    }
                )

            // Frequency gridlines + ruler labels.
            ForEach(scale.tickKHz(), id: \.self) { tick in
                let y = scale.y(forKHz: tick, height: h)
                Path { p in
                    p.move(to: CGPoint(x: rulerWidth, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(.quaternary, lineWidth: 1)
                Text(String(Int(tick)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: rulerWidth / 2 - 2, y: y)
            }

            // CQ frequency marker (dashed blue).
            if let cq = model.cqKHz, cq >= scale.lowKHz, cq <= scale.highKHz {
                let y = scale.y(forKHz: cq, height: h)
                Path { p in
                    p.move(to: CGPoint(x: rulerWidth, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(.blue, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("CQ")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
                    .position(x: size.width - 12, y: y - 6)
            }

            // VFO marker (solid red) — where the radio is right now.
            if let vfo = model.vfoKHz, vfo >= scale.lowKHz - 0.001, vfo <= scale.highKHz + 0.001 {
                let y = scale.y(forKHz: vfo, height: h)
                Path { p in
                    p.move(to: CGPoint(x: rulerWidth - 6, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(.red, lineWidth: 1.5)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                    .position(x: rulerWidth - 10, y: y)
            }

            // Spots, stacked sideways where they collide (see BandMapLayout).
            ForEach(placements(scale: scale, size: size)) { row in
                let status = model.status(for: row.spot)
                let verdict = model.verdict(for: row.spot)
                let needed = status == .neededMultiplier
                Button {
                    model.onTuneSpot?(row.spot)
                } label: {
                    HStack(spacing: 3) {
                        Circle().frame(width: 5, height: 5)
                        Text(row.spot.call)
                            .font(.system(size: CGFloat(labelSize.callPointSize),
                                          design: .monospaced).weight(.semibold))
                            .strikethrough(status == .worked)
                        // The county is the whole reason the hub feed exists —
                        // a cluster spot never carries one.
                        if let county = row.spot.county, !county.isEmpty {
                            Text(county)
                                .font(.system(size: CGFloat(labelSize.countyPointSize),
                                              design: .monospaced))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(needed ? Color.red.opacity(0.18)
                                                     : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(needed ? Color.red : Color.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if model.canSpot {
                        Button("Spot \(row.spot.call)…") {
                            model.onSpotStation?(row.spot)
                        }
                    }
                }
                .foregroundStyle(status.color)
                .opacity(row.spot.isSuperseded ? 0.45 : 1)
                .offset(
                    x: rulerWidth + labelInset
                        + CGFloat(row.column) * CGFloat(labelSize.columnWidth),
                    y: CGFloat(row.y) - CGFloat(labelSize.verticalOffset)
                )
                .help(helpText(for: row.spot, status: status, verdict: verdict))
            }
        }
        .clipped()
    }

    /// Everything the label had no room for. The reconstructed-frequency and
    /// superseded notes are warnings, not decoration: one means the frequency
    /// was inferred rather than read, the other that the board has already
    /// corrected this call. The location line says where the app got it, so a
    /// red spot from last season's roster reads as exactly that.
    private func helpText(for spot: Spot, status: SpotStatus, verdict: BandMapModel.LocationVerdict?) -> String {
        var parts = [String(format: "%.1f de %@", spot.freqKHz, spot.spotter)]
        if !spot.comment.isEmpty { parts.append("(\(spot.comment))") }
        if let verdict {
            let origin = switch verdict.source {
            case .spot: ""
            case .thisLog: " (your log)"
            case .archive: " (a previous contest)"
            case .callHistory: " (call history)"
            }
            parts.append(verdict.location + origin
                         + (verdict.needed ? " — NEW MULTIPLIER" : " — already counted"))
        } else if spot.county == nil {
            parts.append("location unknown")
        }
        if spot.source == .hub { parts.append("via QSO Party Hub") }
        if spot.source == .pota, let park = spot.park {
            parts.append("activating \(park) — via the POTA board; tuning fills the P2P park")
        }
        if spot.source == .local { parts.append("from your own log — nobody spotted him") }
        if spot.frequencyConfidence == .reconstructed {
            parts.append("frequency reconstructed from a malformed entry — verify before calling")
        }
        if spot.isSuperseded {
            parts.append("a later spot on this frequency corrected this call")
        }
        parts.append(status == .worked ? "already worked on this band and mode" : "click to tune")
        return parts.joined(separator: " — ")
    }

    private let labelInset = CGFloat(BandMapMetrics.labelInset)

    /// Column pitch and row clearance come off the label size, so bigger text
    /// stacks into wider columns instead of overlapping in the old ones.
    private func placements(scale: BandMapScale, size: CGSize) -> [BandMapLayout.Placement] {
        BandMapLayout.place(
            spots: model.spots,
            scale: scale,
            height: Double(size.height),
            rowHeight: labelSize.rowHeight,
            columnWidth: labelSize.columnWidth,
            availableWidth: Double(size.width - rulerWidth - labelInset)
        )
    }
}

/// Holds the hosting panel to the label size's minimum.
///
/// SwiftUI's `.frame(minWidth:)` stops the *view* laying out any narrower, but
/// the `NSPanel` around it knows nothing of that — left alone it would be
/// dragged smaller and clip the map. So the window needs its own
/// `contentMinSize`. And a panel restored from its autosaved frame at the old
/// width has to be *widened* when the operator picks a bigger size, not merely
/// stopped from shrinking further, or the new pitch would leave room for a
/// single column and send every collision into the push-down branch.
private struct PanelMinimumSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        // Deferred: there is no window during the first layout pass, and
        // resizing one from inside that pass re-enters layout.
        Task { @MainActor in
            guard let window = view.window else { return }
            window.contentMinSize = NSSize(width: width, height: height)
            let content = window.contentRect(forFrameRect: window.frame)
            guard content.width < width else { return }
            var frame = window.frame
            frame.size.width += width - content.width
            window.setFrame(frame, display: true)
        }
    }
}

/// Floating utility panel hosting the band map, one per contest window.
@MainActor
enum BandMapPanel {
    static func make(model: BandMapModel, near window: NSWindow?) -> NSPanel {
        // 230 is the long-standing default and comfortably clears the smallest
        // label size; only a bigger one raises it, so a panel opened for the
        // first time at XL is already wide enough for two columns instead of
        // being widened out from under the operator a moment later.
        let width = max(230, CGFloat(model.settings.spotLabelSize.minimumPanelWidth))
        let height: CGFloat = 560
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Band Map"
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true  // spot clicks don't steal typing focus
        // AppKit defaults this to true for panels, which is why the map vanished
        // the moment SmartSDR took focus. A band map is for reading while you
        // work another app's panadapter, so it outlives our own activation.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: BandMapView(model: model))

        if !panel.setFrameUsingName("BandMapPanel"), let win = window, let screen = win.screen {
            // First open: dock just right of the contest window.
            var x = win.frame.maxX + 8
            if x + width > screen.visibleFrame.maxX {
                x = screen.visibleFrame.maxX - width - 8
            }
            let y = max(win.frame.maxY - height, screen.visibleFrame.minY)
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }
        panel.setFrameAutosaveName("BandMapPanel")
        return panel
    }
}
