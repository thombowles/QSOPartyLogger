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
        didSet { neededMultiplierCache = [:] }
    }
    var log: ContestLog? {
        didSet { neededMultiplierCache = [:] }
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
    var onTuneSpot: ((Spot) -> Void)?
    var onTuneKHz: ((Double) -> Void)?

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

    /// Whether this spot's county is a multiplier still worth chasing.
    ///
    /// Only hub spots carry a county, and there are few of them next to a
    /// cluster's hundreds, so the scoring call below is reached rarely — and
    /// memoised per county+band+mode besides. `wouldAddMultiplier` honours the
    /// party's scored-multiplier ceiling, so this never sends the operator
    /// after a multiplier that pays nothing.
    func isNeededMultiplier(_ spot: Spot) -> Bool {
        guard let county = spot.county, !county.isEmpty,
              let party, let log, let band = spot.band else { return false }
        let mode = SpotFilter.modeClass(freqKHz: spot.freqKHz, comment: spot.comment,
                                        allowedModes: allowedModes)
        let key = "\(county)|\(band.rawValue)|\(mode.rawValue)"
        if let cached = neededMultiplierCache[key] { return cached }
        let needed = ScoreEngine.wouldAddMultiplier(
            theirLocs: [county], band: band, modeClass: mode, log: log, party: party
        )
        neededMultiplierCache[key] = needed
        return needed
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
    private let rulerWidth: CGFloat = 46

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geo in
                map(size: geo.size)
            }
        }
        .padding(10)
        .frame(minWidth: 190, minHeight: 280)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.band.rawValue)
                .font(.headline)
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

            Text("SPOT FILTERS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Toggle("North American stations only", isOn: $settings.northAmericanStationsOnly)
                .help("Hide spots of DX stations — a state QSO party exchange comes from NA")
            Toggle("North American spotters only", isOn: $settings.northAmericanSpottersOnly)
                .help("Hide spots posted from outside North America")
            Toggle("Hide stations already worked", isOn: $settings.hideWorkedSpots)
                .help("Drop worked calls from the map entirely — off, they stay greyed out and ⌘← / ⌘→ steps over them")
            Toggle("Hide RBN / skimmer spots", isOn: $settings.hideSkimmerSpots)
                .help("Drop automated skimmer spots (\"-#\" nodes and dB/WPM reports)")
            Toggle("QSO Party Hub spots only", isOn: hubOnlyBinding(settings: settings))
                .help("A cluster carries hundreds of spots against the hub's handful — "
                    + "this isolates the ones that name a county when you're hunting multipliers")
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
                .help("Switch the radio between CW and SSB to match the band plan when you tune from the app — clicking a spot, typing a frequency, ⌘← / ⌘→, ⌘J. Turning the VFO knob never changes your mode.")

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
                }
                .disabled(!model.filtersActive && settings.spotMaxAgeMinutes == 15 && settings.followBandPlan)
                Spacer()
                Button("Done") { showFilters = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(width: 290)
    }

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
                let worked = model.isWorked(row.spot)
                let needed = model.isNeededMultiplier(row.spot)
                Button {
                    model.onTuneSpot?(row.spot)
                } label: {
                    HStack(spacing: 3) {
                        Circle().frame(width: 5, height: 5)
                        Text(row.spot.call)
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                            .strikethrough(worked || row.spot.isSuperseded)
                        // The county is the whole reason the hub feed exists —
                        // a cluster spot never carries one.
                        if let county = row.spot.county, !county.isEmpty {
                            Text(county)
                                .font(.system(size: 8, design: .monospaced))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(needed ? Color.accentColor.opacity(0.25)
                                                     : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(needed ? Color.accentColor : Color.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(spotColor(worked: worked, spot: row.spot))
                .opacity(row.spot.isSuperseded ? 0.45 : 1)
                .offset(
                    x: rulerWidth + labelInset + CGFloat(row.column) * Self.columnWidth,
                    y: CGFloat(row.y) - 6
                )
                .help(helpText(for: row.spot, worked: worked, needed: needed))
            }
        }
        .clipped()
    }

    private func spotColor(worked: Bool, spot: Spot) -> Color {
        if spot.isSuperseded || worked { return .secondary }
        return .primary
    }

    /// Everything the label had no room for. The reconstructed-frequency and
    /// superseded notes are warnings, not decoration: one means the frequency
    /// was inferred rather than read, the other that the board has already
    /// corrected this call.
    private func helpText(for spot: Spot, worked: Bool, needed: Bool) -> String {
        var parts = [String(format: "%.1f de %@", spot.freqKHz, spot.spotter)]
        if !spot.comment.isEmpty { parts.append("(\(spot.comment))") }
        if let county = spot.county, !county.isEmpty {
            parts.append(needed ? "\(county) — NEW MULTIPLIER" : "\(county) — already counted")
        }
        if spot.source == .hub { parts.append("via QSO Party Hub") }
        if spot.frequencyConfidence == .reconstructed {
            parts.append("frequency reconstructed from a malformed entry — verify before calling")
        }
        if spot.isSuperseded {
            parts.append("a later spot on this frequency corrected this call")
        }
        parts.append(worked ? "already worked on this band and mode" : "click to tune")
        return parts.joined(separator: " — ")
    }

    /// Horizontal pitch of the label columns — a six-character call at 10 pt
    /// monospaced plus its dot, with room to breathe.
    private static let columnWidth: CGFloat = 60
    /// Clearance one label needs vertically before the next may share a column.
    private static let rowHeight: Double = 13
    private let labelInset: CGFloat = 8

    private func placements(scale: BandMapScale, size: CGSize) -> [BandMapLayout.Placement] {
        BandMapLayout.place(
            spots: model.spots,
            scale: scale,
            height: Double(size.height),
            rowHeight: Self.rowHeight,
            columnWidth: Double(Self.columnWidth),
            availableWidth: Double(size.width - rulerWidth - labelInset)
        )
    }
}

/// Floating utility panel hosting the band map, one per contest window.
@MainActor
enum BandMapPanel {
    static func make(model: BandMapModel, near window: NSWindow?) -> NSPanel {
        let width: CGFloat = 230
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
