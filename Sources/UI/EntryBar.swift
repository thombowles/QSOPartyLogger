import SwiftUI

/// N1MM-style entry row: call, RSTs, exchange with live validation and
/// dupe / new-mult badges. Enter logs from any field.
struct EntryBar: View {
    @Bindable var entry: EntryState
    let party: PartyDefinition?
    let onLog: () -> Void

    enum Field: Hashable {
        case call, rstSent, rstRcvd, exchange
    }

    @FocusState.Binding var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                field("Call", text: $entry.call, width: 140, focusTag: .call)
                    .textCase(.uppercase)
                field("RST S", text: $entry.rstSent, width: 60, focusTag: .rstSent)
                field("RST R", text: $entry.rstRcvd, width: 60, focusTag: .rstRcvd)
                field(exchangeLabel, text: $entry.exchange, width: 170, focusTag: .exchange)
                statusBadge
                Spacer()
                Button("Log", action: onLog)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canLog)
            }
            if let warning = entry.dupeWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if case .invalid(let message) = entry.exchangeStatus {
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var exchangeLabel: String {
        party.map { "County/State (\($0.homeState) Cty ×\($0.countyAbbrLength))" } ?? "Exchange"
    }

    private var canLog: Bool {
        if case .valid = entry.exchangeStatus, !entry.callNormalized.isEmpty {
            return true
        }
        return false
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch entry.exchangeStatus {
        case .idle:
            EmptyView()
        case .valid(let locations):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if locations.count > 1 {
                    Text("COUNTY LINE ×\(locations.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                }
                if entry.isNewMult {
                    Text("NEW MULT")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.25), in: Capsule())
                }
            }
        case .invalid:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        width: CGFloat,
        focusTag: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: width)
                .focused($focus, equals: focusTag)
                .onSubmit(onLog)
                .autocorrectionDisabled()
        }
    }
}
