import SwiftUI

/// Confirms a spot before it goes out — to every network ticked, at once.
///
/// Every send is confirmed, not just the first. The hub's form has no
/// authentication and reaches a public board immediately, a cluster spot
/// goes to every node on the network, and a pota.app post lands on the spot
/// page — and fanning one press out to all three makes that rule more
/// important, not less. Everything is pre-filled from the radio and the log,
/// because retyping a frequency mid-run is why operators stop spotting.
///
/// Return posts, Escape cancels, ⌘1/⌘2/⌘3 tick and untick the networks.
/// Each network row shows exactly what that network will receive, or the
/// reason it is not on offer, or its objection to the draft — so nothing
/// that goes out is a surprise and a greyed checkbox is never a mystery.
struct SpotSheet: View {

    let target: SpotNetworkAvailability.Target
    let party: PartyDefinition
    /// Everything but the draft's park — that half is read live from the
    /// draft, so typing a park enables the POTA row as you type.
    let baseContext: SpotNetworkAvailability.Context
    @Binding var draft: SpotDraft
    let onSend: (SpotDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Field?

    private enum Field: Hashable { case station, frequency, county, comment, park, mode }

    private var context: SpotNetworkAvailability.Context {
        var context = baseContext
        context.draftPark = draft.park
        context.target = target
        return context
    }

    private var available: Set<SpotNetwork> { SpotNetworkAvailability.available(in: context) }

    private var canPost: Bool { draft.sending(available: available).canPost(party: party) }

    private var title: String {
        switch target {
        case .myself:
            return "Spot Myself"
        case .station:
            let call = draft.station.trimmingCharacters(in: .whitespaces).uppercased()
            return call.isEmpty ? "Spot a Station" : "Spot \(call)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            Text("Return posts to every network ticked below — publicly, at once. Esc cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            fields

            VStack(alignment: .leading, spacing: 8) {
                Text("Send to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SpotNetwork.allCases) { network in
                    networkRow(network)
                }
            }

            HStack {
                Text("Posted by \(draft.poster.isEmpty ? "—" : draft.poster)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .shortcutHint("Esc")
                Button("Post Spot") { onSend(draft.sending(available: available)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPost)
                    .shortcutHint("⏎")
            }
            .background(shortcuts)
        }
        .padding(20)
        .frame(width: 540)
        // Land on whatever still needs an answer. Reaching for the command
        // before typing the call leaves the station blank; a contact logged
        // without a radio arrives with no frequency. Either is a field the
        // operator has to supply before this can go anywhere.
        .onAppear {
            if draft.station.isEmpty {
                focused = .station
            } else {
                focused = draft.frequencyKHz > 0 ? .station : .frequency
            }
        }
    }

    // MARK: The spot

    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Call spotted").gridColumnAlignment(.trailing)
                TextField("", text: $draft.station)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .station)
                    .frame(width: 130)
            }
            GridRow {
                Text("Frequency").gridColumnAlignment(.trailing)
                HStack(spacing: 4) {
                    TextField("", value: $draft.frequencyKHz, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .frequency)
                        .frame(width: 100)
                    Text("kHz").foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text(party.countyTerm.sentenceCased).gridColumnAlignment(.trailing)
                TextField("optional — MDSN, or MDSN/LIME on a line", text: countyBinding)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .county)
                    .frame(width: 320)
            }
            GridRow {
                Text("Comment").gridColumnAlignment(.trailing)
                TextField("optional", text: $draft.comment)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .comment)
                    .frame(width: 320)
            }
        }
    }

    // MARK: Network rows

    @ViewBuilder
    private func networkRow(_ network: SpotNetwork) -> some View {
        let availability = SpotNetworkAvailability.availability(of: network, in: context)
        let ticked = draft.networks.contains(network) && availability.isAvailable
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Toggle(isOn: tick(network)) {
                    HStack(spacing: 6) {
                        Text(network.displayName).fontWeight(.medium)
                        Text("·").foregroundStyle(.tertiary)
                        Text(availability.text)
                            .foregroundStyle(availability.isAvailable ? Color.secondary : Color.orange)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!availability.isAvailable)
                Spacer()
                Text("⌘\(String(network.shortcutDigit))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if network == .pota, availability.isAvailable || target == .station {
                potaFields
            }
            if ticked {
                if let problem = draft.problem(for: network, party: party) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                } else {
                    Text(draft.preview(for: network, party: party))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 20)
                        .help("Exactly what this network receives")
                }
            }
        }
    }

    /// POTA's own two: the board takes one park per spot, and a mode. Both
    /// pre-filled — your first park, the radio's mode as ADIF spells it —
    /// and both editable, because a two-fer names its second park here and
    /// the manual mode picker is what stands in with no radio.
    private var potaFields: some View {
        HStack(spacing: 6) {
            Text("Park").foregroundStyle(.secondary)
            TextField("US-0817", text: $draft.park)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($focused, equals: .park)
                .frame(width: 110)
            Text("Mode").foregroundStyle(.secondary)
            TextField("CW", text: $draft.mode)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($focused, equals: .mode)
                .frame(width: 60)
        }
        .padding(.leading, 20)
    }

    // MARK: Keyboard

    /// ⌘1/⌘2/⌘3 tick and untick the rows from wherever the cursor is — a
    /// checkbox is not in the Tab order without Full Keyboard Access, and the
    /// hands are on the keyboard. Zero-sized rather than visible, the way
    /// `AdvisorSection` and `ScoreSidebar` carry theirs; a network that is
    /// not on offer ignores its key, as its checkbox would.
    private var shortcuts: some View {
        ZStack {
            ForEach(SpotNetwork.allCases) { network in
                Button("Toggle \(network.displayName)") {
                    guard SpotNetworkAvailability.availability(of: network, in: context).isAvailable
                    else { return }
                    tick(network).wrappedValue.toggle()
                }
                .keyboardShortcut(KeyEquivalent(network.shortcutDigit), modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func tick(_ network: SpotNetwork) -> Binding<Bool> {
        Binding(
            get: { draft.networks.contains(network) },
            set: { on in
                if on { draft.networks.insert(network) } else { draft.networks.remove(network) }
            }
        )
    }

    /// Free text, not a picker, because a county-line operator gives two to
    /// four and a picker can only say one. The field speaks the party's own
    /// abbreviations; splitting, validating and translating to the hub's own
    /// tokens all happen in `HubSelfSpot`, at the wire.
    ///
    /// The raw string is what is stored. Splitting into an array here and
    /// rejoining on the way back would eat the separator the moment it is
    /// typed and fight the cursor for the next keystroke.
    private var countyBinding: Binding<String> {
        Binding(
            get: { draft.county ?? "" },
            set: { draft.county = $0.isEmpty ? nil : $0 }
        )
    }
}
