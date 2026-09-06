import AppKit

/// A window that comes back where it was.
///
/// Made for a window with the frame last saved for it; restores that frame
/// if the window opens alone and the frame is still on a screen, then hands
/// every move and resize to `save`. One per log window, held by the view for
/// the window's life.
///
/// Not AppKit's `setFrameAutosaveName`: one name serves one window, so the
/// second tab's call fails silently and stops saving; and it restores at a
/// moment SwiftUI may still be placing the window.
@MainActor
final class WindowFrameMemory {
    /// Removed in `deinit`, which Swift 6 runs nonisolated — the tokens are
    /// only ever touched on the main actor, where the class lives.
    nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

    /// The frame to restore: `saved`, if any part of it is on any of
    /// `screens` (their visible frames) — a monitor that is gone leaves the
    /// window to the system rather than restored off every screen.
    static func placement(saved: CGRect?, screens: [CGRect]) -> CGRect? {
        guard let saved, saved.width > 0, saved.height > 0 else { return nil }
        return screens.contains { $0.intersects(saved) } ? saved : nil
    }

    init(
        window: NSWindow,
        saved: CGRect?,
        screens: [CGRect] = NSScreen.screens.map(\.visibleFrame),
        save: @escaping @MainActor (CGRect) -> Void
    ) {
        // A window opening into a tab group takes the group's frame;
        // restoring the saved one would move every tab.
        let alone = (window.tabbedWindows?.count ?? 1) <= 1
        if alone, let frame = Self.placement(saved: saved, screens: screens), window.frame != frame {
            window.setFrame(frame, display: true)
        }
        // Observed after the restore, so the frame just read back is not
        // written straight out again. Synchronous, on the main thread, like
        // the bolt's observers.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { note in
                    guard let moved = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated { save(moved.frame) }
                }
            )
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
