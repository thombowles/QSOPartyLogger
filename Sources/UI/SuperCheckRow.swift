import SwiftUI

/// Super check partial: the known calls matching the fragment being typed —
/// MASTER.SCP's and the party's call history file's, together — on one quiet
/// line under the entry row.
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
///
/// N1MM's Check window keeps its sources in separate panes; this is one line,
/// so a call from the history file is marked instead — teal, and a shade
/// heavier — and the exact call is bold whichever source it came from
/// (2026-08-16). Weight carries "exact" so the cue never rests on colour alone.
struct SuperCheckRow: View {
    let matches: SuperCheck.Matches
    let typedCall: String

    static let height: CGFloat = 18

    /// The colour of a call the party's call history file knows — for the
    /// Skeeter Hunt, a station on the roster.
    static let historyColor: Color = .teal

    var body: some View {
        HStack(spacing: 8) {
            if matches.total > 0 {
                label
                    .font(.system(size: 10))
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

    /// "SCP 12 · HIST 3" — each source's own count, so a roster call among
    /// fifty database matches is still announced. `SuperCheck.Matches.total`
    /// is the union, and is what the "+N more" tail counts against.
    private var label: Text {
        var pieces: [Text] = []
        if matches.scpTotal > 0 {
            pieces.append(Text("SCP \(matches.scpTotal)").foregroundStyle(.tertiary))
        }
        if matches.historyTotal > 0 {
            pieces.append(Text("HIST \(matches.historyTotal)").foregroundStyle(Self.historyColor))
        }
        guard let first = pieces.first else { return Text("") }
        return pieces.dropFirst().reduce(first) { $0 + Text(" · ").foregroundStyle(.tertiary) + $1 }
    }

    /// One composed Text so overflow truncates with an ellipsis instead of
    /// clipping chips. The exact call is bold — the eye's "that call exists"
    /// confirmation — green from the database, teal from the history; a
    /// history call that is not the exact one is teal and semibold; the
    /// database's others stay secondary.
    private var calls: Text {
        var pieces: [Text] = []
        for match in matches.calls {
            pieces.append(piece(for: match))
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

    private func piece(for match: SuperCheck.Match) -> Text {
        let exact = match.call == typedCall
        switch (exact, match.inHistory) {
        case (true, true): return Text(match.call).foregroundStyle(Self.historyColor).bold()
        case (true, false): return Text(match.call).foregroundStyle(.green).bold()
        case (false, true): return Text(match.call).foregroundStyle(Self.historyColor).fontWeight(.semibold)
        case (false, false): return Text(match.call).foregroundStyle(.secondary)
        }
    }

    private var accessibilitySummary: String {
        guard matches.total > 0 else { return "No super check partial matches" }
        let history = matches.historyTotal > 0 ? ", \(matches.historyTotal) in the call history" : ""
        return "\(matches.total) super check partial matches\(history): "
            + matches.calls.map { $0.inHistory ? "\($0.call) (history)" : $0.call }
                .joined(separator: ", ")
    }
}
