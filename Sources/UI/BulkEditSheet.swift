import SwiftUI

/// Change one field across every selected row.
///
/// The sheet *is* the confirmation N1MM puts in a second dialog: the field, the
/// value and the exact row count are all on screen, and the button says what it
/// will do. Nothing is written until it is pressed, and a value the party
/// refuses writes nothing at all.
struct BulkEditSheet: View {

    /// A selection on its way to the sheet. Identifiable so it can drive
    /// `.sheet(item:)`, and a fresh id per request so re-selecting the same
    /// rows re-presents.
    struct Request: Identifiable {
        let id = UUID()
        let rows: [QSO]
    }

    let rows: [QSO]
    /// The whole log, not the selection — the county-line guard needs a
    /// group's other rows, which are exactly what a selection may be missing.
    let allRows: [QSO]
    let party: PartyDefinition?
    /// Where Contest Setup says this log is operating from, which decides what
    /// "My exchange" will accept.
    let isInState: Bool
    let onApply: ([QSO]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var field: BulkEdit.Field = .band
    @State private var band: Band = .m20
    @State private var rawMode = "CW"
    @State private var text = ""
    @State private var validationMessage: String?

    private var fields: [BulkEdit.Field] {
        BulkEdit.fields(for: party)
    }

    private var partition: BulkEdit.Partition {
        BulkEdit.partition(rows, field: field, allRows: allRows)
    }

    private var value: BulkEdit.Value {
        switch field {
        case .band: .band(band)
        case .mode: .mode(rawMode)
        case .myLoc, .nameSent, .memberSent, .myPotaRefs: .text(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(rows.count) Contacts")
                .font(.title3.weight(.semibold))

            Text("One field, one value, applied to every selected row. What the "
                 + "other stations sent stays editable one row at a time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Change")
                    Picker("", selection: $field) {
                        ForEach(fields) { field in
                            Text(BulkEdit.label(field, party: party)).tag(field)
                        }
                    }
                    .frame(width: 190)
                }
                GridRow {
                    Text("To")
                    control
                }
            }

            if !partition.excluded.isEmpty {
                Label(exclusionText, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(applyTitle) { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(partition.changing.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: seed)
        // A refusal belongs to the value that earned it, not to the next one
        // typed — and switching field re-partitions the selection, so a stale
        // message would be describing rows that are no longer in play.
        .onChange(of: field) { _, newField in
            validationMessage = nil
            text = seedText(for: newField)
        }
        .onChange(of: text) { _, _ in validationMessage = nil }
    }

    @ViewBuilder
    private var control: some View {
        switch field {
        case .band:
            Picker("", selection: $band) {
                ForEach(party?.validBands ?? Band.allCases) { band in
                    Text(band.rawValue).tag(band)
                }
            }
            .frame(width: 100)
        case .mode:
            Picker("", selection: $rawMode) {
                ForEach(RadioBar.rawModes(for: party), id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 100)
        case .myLoc, .nameSent, .memberSent, .myPotaRefs:
            TextField("", text: $text.uppercasing)
                .font(.body.monospaced())
                .frame(width: 140)
        }
    }

    private var applyTitle: String {
        let count = partition.changing.count
        return count == 1 ? "Apply to 1 Row" : "Apply to \(count) Rows"
    }

    /// Named, not silent. A count that quietly shrinks from 18 to 15 is the
    /// app deciding something on the operator's behalf without saying so.
    private var exclusionText: String {
        let count = partition.excluded.count
        let rows = count == 1 ? "1 county-line row is" : "\(count) county-line rows are"
        return "\(rows) left unchanged — setting one location across a "
            + "county-line contact would duplicate its rows. Edit those individually."
    }

    /// Start from what the first selected row already carries: the common case
    /// is nudging a value, not inventing one.
    private func seed() {
        let first = fields.first ?? .band
        field = first
        band = rows.first?.band ?? band
        rawMode = rows.first?.rawMode ?? rawMode
        text = seedText(for: first)
    }

    /// The selected field's current value on the first selected row — so
    /// switching from Name to Skeeter # does not leave a name in the box.
    private func seedText(for field: BulkEdit.Field) -> String {
        guard let first = rows.first else { return "" }
        switch field {
        case .myLoc: return first.myLoc
        case .nameSent: return first.nameSent ?? ""
        case .memberSent: return first.memberSent ?? ""
        case .myPotaRefs: return (first.myPotaRefs ?? []).joined(separator: ",")
        case .band, .mode: return text
        }
    }

    private func apply() {
        let partition = partition
        switch BulkEdit.apply(
            value, field: field, to: partition.changing,
            party: party, isInState: isInState
        ) {
        case .failure(let failure):
            validationMessage = failure.message
        case .success(let updated):
            onApply(updated)
            dismiss()
        }
    }
}
