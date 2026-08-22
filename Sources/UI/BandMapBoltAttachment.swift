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
        private var observers: [any NSObjectProtocol] = []

        init(panel: NSPanel, host: NSWindow) {
            self.panel = panel
            self.host = host
            // NSWindow posts these on the main thread, synchronously, from
            // the call that moved the window — a queue of nil keeps it that
            // way, so a test's `setFrameOrigin` has re-pinned by the time it
            // returns.
            let watched: [(Notification.Name, NSWindow)] = [
                (NSWindow.didMoveNotification, host),
                (NSWindow.didResizeNotification, host),
                (NSWindow.didMoveNotification, panel),
            ]
            for (name, window) in watched {
                observers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: nil
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.pin() }
                    }
                )
            }
        }

        /// The setting, applied: attach and pin, or detach. Idempotent — the
        /// view applies it on every change and on every open.
        func apply(bolted: Bool, side: Side) {
            self.side = bolted ? side : nil
            if bolted { attach() } else { detach() }
        }

        /// ⌘B, opening: bring the map on screen, bolted if the setting says so.
        func show() {
            panel.orderFront(nil)
            attach()
        }

        /// ⌘B, closing: detach first, so the window cannot bring it back.
        func hide() {
            detach()
            panel.orderOut(nil)
        }

        /// The window is closing: let go of it, stop watching, close the map.
        func close() {
            detach()
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
