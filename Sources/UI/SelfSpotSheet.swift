import SwiftUI

/// Confirms a self-spot before it goes out.
///
/// Every send is confirmed, not just the first. The hub's form has no CSRF
/// token, no authentication and no session, so whatever is posted reaches a
/// public board immediately and a repeated submit posts twice — during a
/// contest, with hands on the keyboard, that is not a theoretical risk.
///
/// Everything is pre-filled from the radio and the log, because retyping a
/// frequency mid-run is why operators stop self-spotting at all. Return sends,
/// Escape cancels.
struct SelfSpotSheet: View {

    let party: PartyDefinition
    let source: HubSpotSource
    @Binding var fields: HubSelfSpot.Fields
    let onSend: (HubSelfSpot.Fields) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Field?

    private enum Field: Hashable { case station, frequency, county, comment }

    private var problem: HubSelfSpot.Problem? {
        HubSelfSpot.validate(fields, party: party)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spot to QSO Party Hub")
                .font(.headline)
            Text("This posts publicly to \(URL(string: source.postURL)?.host ?? "the hub") "
                 + "for everyone in the \(party.name) to see.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Call spotted").gridColumnAlignment(.trailing)
                    TextField("", text: $fields.station)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .station)
                        .frame(width: 130)
                }
                GridRow {
                    Text("Frequency").gridColumnAlignment(.trailing)
                    HStack(spacing: 4) {
                        TextField("", value: $fields.frequencyKHz, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: .frequency)
                            .frame(width: 100)
                        Text("kHz").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("County").gridColumnAlignment(.trailing)
                    Picker("", selection: countyBinding) {
                        Text("— none —").tag("")
                        ForEach(party.counties) { county in
                            Text("\(county.abbr) — \(county.name)").tag(county.abbr)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    Text("Comment").gridColumnAlignment(.trailing)
                    TextField("optional", text: $fields.comment)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .comment)
                        .frame(width: 260)
                }
                GridRow {
                    Text("Posted by").gridColumnAlignment(.trailing)
                    Text(fields.poster.isEmpty ? "—" : fields.poster)
                        .font(.system(.body, design: .monospaced))
                }
            }

            if let problem {
                Label(problem.errorDescription ?? "", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Post Spot") { onSend(fields) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear { focused = .station }
    }

    /// The picker speaks the party's own abbreviations; translation to the
    /// hub's token happens at the wire, not here.
    private var countyBinding: Binding<String> {
        Binding(
            get: { fields.county ?? "" },
            set: { fields.county = $0.isEmpty ? nil : $0 }
        )
    }
}
