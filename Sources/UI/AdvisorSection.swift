import SwiftUI

/// The Advisor, at the top of the score sidebar.
///
/// A layout and nothing else: every sentence on screen comes from
/// `Advisor.evaluate`, which is where the wording is tested. This view decides
/// where the text sits, ticks the engine, and hands a tapped chip's `Spot`
/// straight back to the caller's own `tune(to:)` — the very path a band-map
/// click takes. **It never logs, never keys, and never moves the radio.**
///
/// It renders nothing at all when nothing is live, which is most of a contest.
/// The keyboard shortcuts stay mounted regardless, in a zero-sized button the
/// way `ScoreSidebar` mounts ⇧⌘C, so ⇧⌘A and ⌥⌘A work whether or not there is
/// anything on screen to act on.
struct AdvisorSection: View {

    /// Built on demand with the evaluation's own `now`, rather than handed in
    /// as a value: an `Advisor.Input` carries a rate reading and a trailing
    /// window, both of which are functions of the instant they are read at.
    let input: (Date) -> Advisor.Input
    var onTune: (Spot) -> Void

    @State private var settings = AppSettings.shared
    @State private var engine = Advisor.State()
    @State private var advisories: [Advisor.Advisory] = []

    /// Finer than any sustain window, and only this section redraws on it —
    /// the rosters and county chips below are outside it.
    private static let tick: Duration = .seconds(30)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            shortcuts
            if settings.advisorEnabled, !advisories.isEmpty {
                header
                if !settings.advisorCollapsed {
                    ForEach(advisories) { advisory in
                        row(advisory)
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                evaluate()
                try? await Task.sleep(for: Self.tick)
            }
        }
        // The two controls the operator drives directly answer at once; the
        // rest of the world arrives on the tick.
        .onChange(of: settings.advisorGoal) { evaluate() }
        .onChange(of: settings.advisorMutedKinds) { evaluate() }
        .onChange(of: settings.advisorEnabled) { evaluate() }
    }

    private func evaluate() {
        guard settings.advisorEnabled else {
            advisories = []
            return
        }
        let now = Date()
        (advisories, engine) = Advisor.evaluate(input(now), state: engine, now: now)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Text("ADVISOR")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            // The goal is beside the advice, always, so a recommendation can
            // never be read against the wrong yardstick.
            Picker("Goal", selection: $settings.advisorGoal) {
                ForEach(Advisor.Goal.allCases, id: \.self) { goal in
                    Text(goal.label).tag(goal)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 104)
            .help(goalHelp)

            Button {
                settings.advisorCollapsed.toggle()
            } label: {
                Image(systemName: settings.advisorCollapsed
                      ? "chevron.down.square" : "chevron.up.square")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Collapse or expand the Advisor (⇧⌘A)")
        }
        .contextMenu {
            ForEach(Advisor.Advisory.Kind.allCases, id: \.self) { kind in
                Toggle(kind.label, isOn: muted(kind))
            }
            Divider()
            Button("Turn the Advisor Off") { settings.advisorEnabled = false }
        }
    }

    private var goalHelp: String {
        """
        What a contact is worth (⌥⌘A). Score prices a new multiplier heavily, \
        because it multiplies everything. QSOs prices every valid contact the \
        same, which is what the State QSO Party Challenge pays — there a \
        needed county is worth exactly one QSO.
        """
    }

    /// Inverted on purpose: the menu offers the kinds to *hear*, because a
    /// list of checkmarks reads as what is on rather than what is silenced.
    private func muted(_ kind: Advisor.Advisory.Kind) -> Binding<Bool> {
        Binding(
            get: { !settings.advisorMutedKinds.contains(kind) },
            set: { wanted in
                if wanted {
                    settings.advisorMutedKinds.remove(kind)
                } else {
                    settings.advisorMutedKinds.insert(kind)
                }
            }
        )
    }

    // MARK: One advisory

    private func row(_ advisory: Advisor.Advisory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: icon(advisory.kind))
                    .font(.caption)
                    .foregroundStyle(tint(advisory.kind))
                    .padding(.top, 1)
                Text(advisory.headline)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !advisory.chips.isEmpty {
                FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(advisory.chips) { chip in
                        chipButton(chip)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        // Every advisory names its evidence, and the depth lives here rather
        // than on screen — the inline-status rule the rest of the app follows.
        .help(advisory.detail)
    }

    /// One gesture to the multiplier: the same `tune(to:)` a band-map click
    /// fires, so the radio moves, the call lands in the entry bar, and the
    /// county prefills the exchange. One tune rule, held in one place.
    private func chipButton(_ chip: Advisor.TuneChip) -> some View {
        Button {
            onTune(chip.spot)
        } label: {
            Text(chip.label)
                .font(.system(size: 10, design: .monospaced).weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("Tune to \(chip.spot.call) at \(chip.spot.freqKHz.formatted()) kHz — "
              + "the same thing a band-map click does. You still send the call.")
    }

    private func icon(_ kind: Advisor.Advisory.Kind) -> String {
        switch kind {
        case .runFading: "chart.line.downtrend.xyaxis"
        case .moveCall: "arrow.triangle.swap"
        case .neededMultsSpotted: "star.circle"
        case .bonusStanding: "gift"
        case .scheduleEdge: "clock"
        }
    }

    private func tint(_ kind: Advisor.Advisory.Kind) -> Color {
        switch kind {
        case .runFading: .orange
        case .moveCall: .accentColor
        case .neededMultsSpotted: .green
        case .bonusStanding: .purple
        case .scheduleEdge: .secondary
        }
    }

    // MARK: Keyboard

    /// Zero-sized rather than visible controls, for the reason `ScoreSidebar`
    /// hides ⇧⌘C the same way: these have to work when the section is drawing
    /// nothing at all, and a visible button would have to appear somewhere.
    private var shortcuts: some View {
        ZStack {
            Button("Collapse or Expand the Advisor") {
                settings.advisorCollapsed.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Toggle the Advisor Goal") {
                settings.advisorGoal = settings.advisorGoal == .score ? .qsos : .score
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
