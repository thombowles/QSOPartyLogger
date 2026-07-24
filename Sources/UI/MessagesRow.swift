import SwiftUI

/// F1–F8 CW message buttons with expanded-preview tooltips.
struct MessagesRow: View {
    let messages: [String]
    let expand: (String) -> String
    let onSend: (String) -> Void
    let enabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(messages.prefix(8).enumerated()), id: \.offset) { index, template in
                Button {
                    onSend(template)
                } label: {
                    VStack(spacing: 1) {
                        Text("F\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(shortLabel(template))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 66)
                }
                .disabled(!enabled || template.isEmpty)
                .help(expand(template))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func shortLabel(_ template: String) -> String {
        let expanded = expand(template)
        return expanded.count > 14 ? String(expanded.prefix(13)) + "…" : expanded
    }
}
