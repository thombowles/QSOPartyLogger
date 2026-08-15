import SwiftUI

/// What became of the last spot, in the station strip: a state per network,
/// live, tinted by the worst of them. Leaves by itself when the receipt's
/// window closes and comes back for a verdict that lands late.
///
/// Every string and every rule is `SpotReceipt`'s; this only draws — and
/// looks at the clock exactly when it needs to: on each change, and once
/// more when that change's window closes. No ticking timer.
struct SpotReceiptView: View {
    let receipt: SpotReceipt
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var now = Date()

    var body: some View {
        Group {
            if receipt.isVisible(now: now) {
                capsule
            }
        }
        // Re-armed by every change: read the clock, sleep until this change's
        // window closes, read it again — which is the moment the capsule goes.
        .task(id: receipt.changedAt) {
            now = Date()
            let window = receipt.failedNetworks.isEmpty
                ? SpotReceipt.quietWindow : SpotReceipt.failureWindow
            let remaining = receipt.changedAt.addingTimeInterval(window).timeIntervalSince(now)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            now = Date()
        }
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text(receipt.title)
                .font(.caption.weight(.bold).monospaced())
            Text(receipt.summary)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if !receipt.failedNetworks.isEmpty {
                Button("Retry…", action: onRetry)
                    .controlSize(.mini)
                    .help("Open the spot again with only the failed network(s) ticked")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss spot receipt")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
        .help(receipt.networks.map(receipt.line(for:)).joined(separator: "\n"))
    }

    private var color: Color {
        switch receipt.tint {
        case .pending: .secondary
        case .good: .green
        case .bad: .orange
        }
    }
}
