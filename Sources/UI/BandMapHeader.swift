import SwiftUI

/// The band map's top line: band, VFO, which contest, the span, the funnel.
///
/// One line where the panel is wide enough; where it is not, the span and
/// the funnel fold under the band and VFO. The narrowest panel is 230
/// points, and one line of all five is about 270 — so at the width the map
/// opens at, nothing is squeezed against a side any more. `ViewThatFits`
/// picks by ideal width, as the log window's rows do (`WindowSizeTests`).
struct BandMapHeader<Trailing: View>: View {
    let band: String
    /// The VFO, formatted; nil is "no radio".
    let vfoText: String?
    /// Which log this map belongs to; empty until setup names a party.
    let contestLabel: String
    @Binding var spanKHz: Double
    let spanChoices: [(label: String, kHz: Double)]
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                identity
                Spacer(minLength: 8)
                span.frame(width: 150)
                trailing()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    identity
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    span
                    trailing()
                }
            }
        }
    }

    @ViewBuilder
    private var identity: some View {
        Text(band)
            .font(.headline)
            .help(Self.legend)
        if let vfoText {
            Text(vfoText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.red)
        } else {
            Text("no radio")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !contestLabel.isEmpty {
            Text(contestLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("This map belongs to the \(contestLabel) log")
        }
    }

    private var span: some View {
        Picker("", selection: $spanKHz) {
            ForEach(spanChoices, id: \.kHz) { choice in
                Text(choice.label).tag(choice.kHz)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Visible span in kHz, centered on the VFO")
    }

    /// Computed, not stored: a generic type cannot hold a static let.
    static var legend: String {
        "Red — a multiplier you still need. Blue — unworked, not a multiplier "
            + "(or nobody knows where he is). Grey — worked on this band and mode, "
            + "or superseded. A cluster spot's county comes from your log, previous "
            + "contests or the party's call history file — the same places the "
            + "exchange pre-fill looks."
    }
}
