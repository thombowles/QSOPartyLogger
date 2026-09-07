import SwiftUI
import AppKit

/// Data feed for the band map panel — owned by the contest window (MainView)
/// and kept in sync with its band / worked-calls / CQ state.
@MainActor
@Observable
final class BandMapModel {
    var band: Band = .m20
    /// Which log this map belongs to — the party's short name, or the park
    /// (`LogDocument.contestShortLabel`) — for the title bar and the header,
    /// so with several contests in tabs no map is anonymous.
    var contestLabel: String = ""
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

    /// Band, VFO, which contest, the span and the funnel — one line where
    /// the panel is wide enough, two where it is not (`BandMapHeader`).
    private var header: some View {
        BandMapHeader(
            band: model.band.rawValue,
            vfoText: model.vfoKHz.map { String(format: "%.1f", $0) },
            contestLabel: model.contestLabel,
            spanKHz: $spanKHz,
            spanChoices: Self.spanChoices
        ) {
            filtersButton
        }
    }

    /// Everything that decides which spots appear, and how the map behaves,
    /// next to the spots (`BandMapSettingsPopover`).
    private var filtersButton: some View {
        Button {
            showFilters.toggle()
        } label: {
            Image(systemName: model.filtersActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.borderless)
        .help("Band map settings — which spots show, how the map follows the knob, where its window is")
        .popover(isPresented: $showFilters, arrowEdge: .bottom) {
            BandMapSettingsPopover(model: model, isPresented: $showFilters)
        }
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

/// Utility panel hosting the band map, one per contest window — an ordinary
/// window at the log's own level, never floating over another app's.
@MainActor
enum BandMapPanel {
    /// The title: the contest first, so a narrow panel's title bar keeps
    /// the part that tells two maps apart.
    nonisolated static func title(contest: String?) -> String {
        guard let contest, !contest.isEmpty else { return "Band Map" }
        return "\(contest) — Band Map"
    }

    /// Where a map opens: at `saved` when any part of it is on `screen`;
    /// otherwise — the first open, or a monitor that is gone — docked just
    /// right of its window at `size`, kept on the screen; with no window
    /// either, `size` at the origin for AppKit to place.
    nonisolated static func initialFrame(saved: NSRect?, host: NSRect?, screen: NSRect, size: NSSize) -> NSRect {
        if let saved, saved.width > 0, saved.height > 0, screen.intersects(saved) {
            return saved
        }
        guard let host else { return NSRect(origin: .zero, size: size) }
        var x = host.maxX + 8
        if x + size.width > screen.maxX {
            x = screen.maxX - size.width - 8
        }
        let y = max(host.maxY - size.height, screen.minY)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func make(model: BandMapModel, near window: NSWindow?, frame saved: NSRect?) -> NSPanel {
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
        panel.title = title(contest: model.contestLabel)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true  // spot clicks don't steal typing focus
        // AppKit defaults this to true for panels, which is why the map vanished
        // the moment SmartSDR took focus. A band map is for reading while you
        // work another app's panadapter, so it outlives our own activation.
        panel.hidesOnDeactivate = false
        // The log's own level: the map behaves like the log window — behind
        // another app's window when that is in front, forward with the app —
        // rather than floating over everything (the operator's word, 2026-09-07).
        panel.level = .normal
        panel.contentView = NSHostingView(rootView: BandMapView(model: model))

        // Where it was last (`AppSettings.bandMapFrame`, saved by the bolt
        // attachment on every move) — not AppKit's frame autosave, whose one
        // name every window's map fought over.
        let screen = (window?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        panel.setFrame(
            initialFrame(saved: saved, host: window?.frame, screen: screen,
                         size: NSSize(width: width, height: height)),
            display: false
        )
        return panel
    }
}
