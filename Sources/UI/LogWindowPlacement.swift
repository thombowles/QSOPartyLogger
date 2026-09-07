import AppKit
import SwiftUI
import os

/// Where a new log window opens, decided before it is shown.
///
/// `WindowFrameMemory` restores the saved frame once the window exists —
/// but by then SwiftUI has shown it, centred at its default size, and the
/// operator watches it jump. `DocumentGroup.defaultWindowPlacement` asks
/// *before* the window is made — for a restored window too, the unified
/// log shows — so the saved frame is the window's first frame, and the
/// memory finds nothing to correct.
///
/// SwiftUI's placement space is the primary display's flipped coordinate
/// space: origin at its top-left corner, y down (the menu bar puts the
/// visible rect at y 30). The position is the window frame's top-left
/// corner and the size is the frame's size, chrome included — calibrated on
/// 2026-09-07 by placing at {300, 396, 1200 × 648} and reading the window's
/// frame back as {300, 252, 1200 × 648} on a 1296-point display. AppKit's
/// frames are bottom-left, y up; only y changes hands.
enum LogWindowPlacement {

    /// The saved frame in SwiftUI's space, or nil to let the system place
    /// the window: nothing saved, or a frame off every screen. A rect
    /// rather than a `WindowPlacement`, which is not `Sendable` and so
    /// cannot leave the main actor the store is read on.
    nonisolated static func placement(frame: CGRect?, screens: [CGRect], primaryHeight: CGFloat) -> CGRect? {
        guard let frame = WindowFrameMemory.placement(saved: frame, screens: screens) else { return nil }
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// `placement` as SwiftUI wants it.
    nonisolated static func windowPlacement(_ rect: CGRect?) -> WindowPlacement {
        guard let rect else { return WindowPlacement() }
        return WindowPlacement(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// The saved log window, read straight from the preference store — never
    /// through `AppSettings.shared`, which must not be built at launch (see
    /// `PreferenceIsolationTests`).
    @MainActor
    static func saved() -> CGRect? {
        let store = Preferences.store
        let rect = placement(
            frame: AppSettings.storedFrame(forKey: "logWindowFrame", in: store),
            screens: NSScreen.screens.map(\.visibleFrame),
            primaryHeight: NSScreen.screens.first?.frame.height ?? 0
        )
        log.notice("placing a new log window: \(rect.map(NSStringFromRect) ?? "system default", privacy: .public) (SwiftUI space)")
        return rect
    }

    private static let log = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "window")
}
