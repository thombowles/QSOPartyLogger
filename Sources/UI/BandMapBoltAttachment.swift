import AppKit

extension BandMapBolt {
    /// The band map panel's relationship to its log window: free-floating, or
    /// bolted to one side of it as a child window. One per open band map,
    /// made with the panel in `MainView`; closed with it.
    ///
    /// Bolted, the panel is a child of the log window (`addChildWindow`), so
    /// it is raised, lowered, minimised and moved with it; it is held at the
    /// window's level rather than floating, so the *other* log's map is never
    /// on top of this one; and it is pinned to the edge — the window's every
    /// move and resize re-pins it, and so does any attempt to drag the map
    /// away by its title bar. Its own resize is left alone: the width is the
    /// operator's, and snapping the origin back during a live resize from the
    /// left edge would fight the drag.
    ///
    /// A hidden map is never left a child: a child is ordered in with its
    /// parent, and the next click on the log would bring it back.
    @MainActor
    final class Attachment {
        let panel: NSPanel
        let host: NSWindow

        /// The setting as last applied; nil is floating.
        private var side: Side?
        /// Whether the panel is a child of the host right now.
        private(set) var isAttached = false
        /// Whether the operator wants the map up — `show()` / `hide()`. The
        /// map is on screen exactly when this is true *and* the host is
        /// visible (`sync`): a tab that is not selected is ordered out, and
        /// its map must go with it or every tab's map stacks up on screen.
        private var wanted = false
        private var observers: [any NSObjectProtocol] = []

        /// The panel moved or resized by the operator's hand (or the pin's):
        /// its frame, for remembering.
        var onFrameChanged: (@MainActor (NSRect) -> Void)?
        /// The panel's own close button — the operator saying "no map".
        /// Not fired by `close()`, which is the window going away.
        var onClosedByOperator: (@MainActor () -> Void)?

        init(panel: NSPanel, host: NSWindow) {
            self.panel = panel
            self.host = host
            // NSWindow posts these on the main thread, synchronously, from
            // the call that moved the window — a queue of nil keeps it that
            // way, so a test's `setFrameOrigin` has re-pinned by the time it
            // returns.
            let pinned: [(Notification.Name, NSWindow)] = [
                (NSWindow.didMoveNotification, host),
                (NSWindow.didResizeNotification, host),
                (NSWindow.didMoveNotification, panel),
            ]
            for (name, window) in pinned {
                observe(name, of: window) { $0.pin() }
            }
            // The panel's frame, remembered — after the pin above has had its
            // say, since observers fire in the order they were added.
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observe(name, of: panel) { $0.onFrameChanged?($0.panel.frame) }
            }
            observe(NSWindow.willCloseNotification, of: panel) { $0.operatorClosed() }
            // The host going off screen or coming back — a tab deselected or
            // selected, the window miniaturised, the app hidden.
            let visibility: [Notification.Name] = [
                NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSWindow.didChangeOcclusionStateNotification,
            ]
            for name in visibility {
                observe(name, of: host) { $0.sync() }
            }
        }

        private func observe(
            _ name: Notification.Name, of window: NSWindow,
            _ body: @escaping @MainActor (Attachment) -> Void
        ) {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: nil
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        body(self)
                    }
                }
            )
        }

        /// The setting, applied: attach and pin, or detach. Idempotent — the
        /// view applies it on every change and on every open.
        func apply(bolted: Bool, side: Side) {
            self.side = bolted ? side : nil
            if bolted { attach() } else { detach() }
        }

        /// ⌘B, opening: bring the map on screen, bolted if the setting says so.
        func show() {
            wanted = true
            sync()
        }

        /// ⌘B, closing: detach first, so the window cannot bring it back.
        func hide() {
            wanted = false
            sync()
        }

        /// Whether the host is showing: on screen, and — in a tab group —
        /// the selected tab. A deselected tab is ordered out on a live
        /// desktop, but the selection is asked directly rather than relying
        /// on that: the hosted test bundle is never the active app, and
        /// there the deselected tab stays "visible".
        var hostIsShowing: Bool {
            guard host.isVisible else { return false }
            guard let group = host.tabGroup, group.windows.count > 1 else { return true }
            return group.selectedWindow === host
        }

        /// The map on screen exactly when it is wanted and its window is
        /// showing. Idempotent; run on every change of either.
        func sync() {
            if wanted, hostIsShowing {
                if !panel.isVisible { panel.orderFront(nil) }
                attach()
            } else {
                detach()
                if panel.isVisible { panel.orderOut(nil) }
            }
        }

        /// The panel's close button: AppKit orders it out itself; it must not
        /// stay a child, and the operator's choice is reported.
        private func operatorClosed() {
            wanted = false
            detach()
            onClosedByOperator?()
        }

        /// The window is closing: let go of it, stop watching, close the map.
        func close() {
            detach()
            // Observers first: the panel's `willClose` below is not the
            // operator closing the map.
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            panel.close()
        }

        /// Put the map where the bolt says — only if it is not there already,
        /// so the notification the move itself posts finds nothing to do.
        func pin() {
            guard isAttached, let side else { return }
            let target = BandMapBolt.frame(
                host: host.frame, side: side,
                panelWidth: panel.frame.width, minimumHeight: panel.minSize.height
            )
            guard panel.frame != target else { return }
            panel.setFrame(target, display: true)
        }

        private func attach() {
            guard side != nil, panel.isVisible else { return }
            if !isAttached {
                host.addChildWindow(panel, ordered: .above)
                panel.level = host.level
                isAttached = true
            }
            pin()
        }

        private func detach() {
            guard isAttached else { return }
            host.removeChildWindow(panel)
            panel.level = .floating
            isAttached = false
        }
    }
}
