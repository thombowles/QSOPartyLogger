import SwiftUI

/// Super check partial: the community calls matching the fragment being
/// typed, on one quiet line under the entry row.
///
/// Two deliberate shapes, both with house precedent:
///
/// - **Fixed height, present even when empty.** The strip fills and
///   empties on every keystroke; a row that reflowed the window at 35 WPM
///   would cost more than the 18 px it saves. Same reasoning as
///   `WorkedBeforeTable`'s height arithmetic, solved by reservation
///   because this row's population changes far faster.
/// - **Not interactive**, like `WorkedBeforeTable`'s rows: a click target
///   directly above the log table is a mis-click hazard mid-run, and the
///   operator is already typing the call. The strip is for the eye.
struct SuperCheckRow: View {
    let matches: SCPDatabase.Matches
    let typedCall: String

    static let height: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            if matches.total > 0 {
                Text("SCP \(matches.total)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                calls
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// One composed Text so overflow truncates with an ellipsis instead of
    /// clipping chips. The exact call is tinted — the eye's "that call
    /// exists" confirmation; weight as well as colour, so the cue does not
    /// rest on colour alone.
    private var calls: Text {
        var pieces: [Text] = []
        for call in matches.calls {
            pieces.append(
                call == typedCall
                    ? Text(call).foregroundStyle(.green).bold()
                    : Text(call).foregroundStyle(.secondary)
            )
        }
        if matches.total > matches.calls.count {
            pieces.append(
                Text("+\(matches.total - matches.calls.count) more")
                    .foregroundStyle(.tertiary)
            )
        }
        guard let first = pieces.first else { return Text("") }
        return pieces.dropFirst().reduce(first) { $0 + Text("  ") + $1 }
    }

    private var accessibilitySummary: String {
        matches.total == 0
            ? "No super check partial matches"
            : "\(matches.total) super check partial matches: "
                + matches.calls.joined(separator: ", ")
    }
}
