import AppKit

/// Every contest is a tab of one log window.
///
/// AppKit's window tabbing does the work — the tab bar, ⌃Tab / ⌃⇧Tab, the
/// Window menu's tab items, dragging a tab out into its own window — once a
/// window asks for it (`tabbingMode = .preferred`) under a shared identifier.
/// Each contest keeps its own `NSWindow`, so the key monitor, the shared
/// radio's window count, sheets and the bolted band map all keep working per
/// window, unchanged.
///
/// One wrinkle: AppKit tabs a new window at the moment it is first ordered
/// front, and SwiftUI's `DocumentGroup` shows the window before the view's
/// accessor can mark it. So a log window that arrives untabbed is added to
/// the front log window's group by hand (`join`).
@MainActor
enum LogWindowTabs {
    /// The identifier every log window tabs under. The dashboard is
    /// `.disallowed`, so it never lands in this group.
    static let identifier = "org.b5n.QSOPartyLogger.log"

    /// Ask for tabs. Called once per log window, as soon as it is known.
    static func configure(_ window: NSWindow) {
        // The app-wide switch, said out loud: it is what puts the tab items
        // (and ⌃Tab / ⌃⇧Tab) in the Window menu.
        NSWindow.allowsAutomaticWindowTabbing = true
        window.tabbingMode = .preferred
        window.tabbingIdentifier = identifier
    }

    /// If `window` has no tab siblings, add it — in front — to the group of
    /// the first other log window in `candidates` that is on screen. Returns
    /// whether it was moved. A window AppKit already tabbed, the first log
    /// window of the run, and a window with no visible log window to join
    /// are all left alone.
    @discardableResult
    static func join(_ window: NSWindow, among candidates: [NSWindow]) -> Bool {
        guard (window.tabbedWindows?.count ?? 1) <= 1 else { return false }
        guard let host = candidates.first(where: { candidate in
            candidate !== window
                && candidate.isVisible
                && candidate.tabbingIdentifier == identifier
                && candidate.tabbingMode != .disallowed
        }) else { return false }
        host.addTabbedWindow(window, ordered: .above)
        window.tabGroup?.selectedWindow = window
        return true
    }

    /// `join`, over the app's own windows.
    @discardableResult
    static func join(_ window: NSWindow) -> Bool {
        join(window, among: NSApp.orderedWindows)
    }
}
