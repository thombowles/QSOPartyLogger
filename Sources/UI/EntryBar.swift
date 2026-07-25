import SwiftUI

/// N1MM-style entry row: call, RSTs, exchange with live validation and
/// dupe / new-mult badges. Enter logs from any field.
struct EntryBar: View {
    @Bindable var entry: EntryState
    let party: PartyDefinition?
    let onLog: () -> Void

    enum Field: Hashable {
        case call, rstSent, rstRcvd, serialSent, serialRcvd, exchange

        /// Where Space moves next, cycling back to the call from the exchange.
        /// Call jumps straight to the exchange because the RSTs are pre-filled
        /// — Tab still walks every field for the rare 579, which is how N1MM
        /// splits the two keys ("the spacebar … skips over signal report
        /// fields"; Tab walks them all).
        ///
        /// A received QSO number is the one numeric field an operator *must*
        /// type every contact, so where a party exchanges one, Call lands there
        /// first and it leads on to the exchange.
        func next(includesRST: Bool, includesSerial: Bool = false) -> Field {
            switch self {
            case .call: includesSerial ? .serialRcvd : .exchange
            case .rstSent: includesRST ? .rstRcvd : .exchange
            case .rstRcvd: includesSerial ? .serialRcvd : .exchange
            case .serialSent: .serialRcvd
            case .serialRcvd: .exchange
            case .exchange: .call
            }
        }
    }

    @FocusState.Binding var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                field("Call", text: $entry.call.uppercasing, width: 140, focusTag: .call)
                if party?.exchangeIncludesRST ?? true {
                    field("RST S", text: $entry.rstSent, width: 60, focusTag: .rstSent)
                    field("RST R", text: $entry.rstRcvd, width: 60, focusTag: .rstRcvd)
                }
                if party?.exchangeIncludesSerial ?? false {
                    field("Ser S", text: $entry.serialSent, width: 60, focusTag: .serialSent)
                    field("Ser R", text: $entry.serialRcvd, width: 60, focusTag: .serialRcvd)
                }
                field(exchangeLabel, text: $entry.exchange.uppercasing, width: 170, focusTag: .exchange)
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
        .onChange(of: focus) { _, landed in
            guard landed == .rstSent || landed == .rstRcvd else { return }
            selectStrengthDigit()
        }
    }

    /// Landing in a signal report selects the S digit alone, so 599 → 579 is
    /// one keystroke rather than retyping the group — the behaviour the N1MM
    /// manual describes for Tab.
    ///
    /// SwiftUI's TextField exposes no selection, so this reaches the window's
    /// field editor, which becomes first responder a runloop turn after the
    /// focus change lands.
    private func selectStrengthDigit() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                // R S T — the strength digit is the middle one, and the second
                // character in both the CW (599) and phone (59) forms.
                guard editor.string.count >= 2 else { return }
                editor.setSelectedRange(NSRange(location: 1, length: 1))
            }
        }
    }

    private var exchangeLabel: String {
        party.map { "County/State (\($0.homeState) Cty ×\($0.countyAbbrLengthHint))" } ?? "Exchange"
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
                // Space advances rather than typing one, in every field — from
                // the exchange it wraps back to the call, so the row cycles.
                // Mults are separated with "/" or "," instead.
                .onKeyPress(.space) {
                    focus = focusTag.next(
                        includesRST: party?.exchangeIncludesRST ?? true,
                        includesSerial: party?.exchangeIncludesSerial ?? false
                    )
                    return .handled
                }
        }
    }
}
