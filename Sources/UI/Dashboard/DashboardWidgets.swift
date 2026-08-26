import Foundation

/// The dashboard's widgets in display order, each one show/hide from the
/// toolbar Widgets menu (⌘1–⌘6) so the operator composes the dashboard
/// they want.
enum DashboardWidget: String, CaseIterable, Identifiable, Sendable {
    case seasonCards, potaCards, challenge, contests, pota, upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seasonCards: "Season Summary"
        case .potaCards: "POTA Summary"
        case .challenge: "SQP Challenge"
        case .contests: "Contests"
        case .pota: "POTA History"
        case .upcoming: "Upcoming Contests"
        }
    }

    /// The digit behind ⌘ that toggles this widget — display order, 1-based.
    var shortcutKey: Character {
        Character("\((DashboardWidget.allCases.firstIndex(of: self) ?? 0) + 1)")
    }
}

/// Which widgets are hidden — persisted as a comma-joined raw-value string
/// (names this build doesn't know are ignored, so an older build's prefs
/// and a newer one's coexist). Empty means everything shows, which is the
/// default.
struct DashboardWidgetVisibility: Equatable, Sendable {
    var hidden: Set<DashboardWidget>

    init(hidden: Set<DashboardWidget> = []) {
        self.hidden = hidden
    }

    init(rawValue: String) {
        self.hidden = Set(rawValue.split(separator: ",").compactMap {
            DashboardWidget(rawValue: $0.trimmingCharacters(in: .whitespaces))
        })
    }

    /// Display order, so the stored pref is stable whatever the toggling
    /// order was.
    var rawValue: String {
        DashboardWidget.allCases.filter(hidden.contains).map(\.rawValue)
            .joined(separator: ",")
    }

    func shows(_ widget: DashboardWidget) -> Bool {
        !hidden.contains(widget)
    }

    mutating func toggle(_ widget: DashboardWidget) {
        if hidden.contains(widget) {
            hidden.remove(widget)
        } else {
            hidden.insert(widget)
        }
    }

    /// Everything toggled off — the content area says how to get back.
    var allHidden: Bool {
        hidden.count == DashboardWidget.allCases.count
    }
}
