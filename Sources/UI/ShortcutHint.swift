import SwiftUI

/// Shortcut hints — ⌘/, or Help › Keyboard Shortcut Hints. While they are on,
/// every control that has a key wears it as a small keycap badge, and the
/// legend under the messages row lists the keys that have no button.
///
/// The badge reads `AppSettings.shared` directly rather than an environment
/// value so it works in every window the app opens — the log window, its
/// sheets, the band-map panel, the dashboard — with no plumbing to forget.

extension View {
    /// Wear `keys` ("⌘B", "⇧⌘S", "⌘E · ⇧⌘E") as a badge while hints are on.
    func shortcutHint(_ keys: String) -> some View {
        modifier(ShortcutHintBadge(keys: keys))
    }
}

struct ShortcutHintBadge: ViewModifier {
    let keys: String
    @State private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if settings.showShortcutHints {
                Text(keys)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .offset(x: 4, y: -6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
    }
}

/// The keys that have no button to wear a badge, in the order the operating
/// loop reaches for them. Rendered under the messages row while hints are on.
enum ShortcutLegend {
    struct Item: Equatable {
        let keys: String
        let action: String
    }

    static let items: [Item] = [
        Item(keys: "F1–F8", action: "messages"),
        Item(keys: "F12", action: "clear entry"),
        Item(keys: "Esc", action: "abort"),
        Item(keys: "⌘↑ ⌘↓", action: "next / previous spot"),
        Item(keys: "⌘J", action: "CQ frequency"),
        Item(keys: "⌘= ⌘-", action: "WPM ±1"),
        Item(keys: "⇧⌘= ⇧⌘-", action: "WPM ±2"),
        Item(keys: "⇧⌘← ⇧⌘→", action: "VFO ±100 Hz"),
        Item(keys: "⌘A", action: "select all rows"),
        Item(keys: "⌘/", action: "hide these hints"),
    ]

    /// "F12 clear entry · Esc abort · …" — one line, for the strip.
    static var line: String {
        items.map { "\($0.keys) \($0.action)" }.joined(separator: " · ")
    }

    /// The readout of the last key the monitor ruled on, or the invitation.
    static func lastKeyLine(_ readout: String?) -> String {
        "Last key: \(readout ?? "— (press one)")"
    }
}
