import AppKit
import SwiftUI

/// A dialog in the middle of the screen — not a sheet hung from the window,
/// which the window's position pushes off the bottom of the display when
/// the window sits low (Contest Setup on a window against the screen's
/// bottom edge lost its Save button; the operator, 2026-09-07).
///
/// Presented app-modally, like a sheet: nothing else in the app takes input
/// until it closes, Esc and Return reach its own buttons, and the key
/// monitor treats a modal window as it treats a sheet (`KeyMonitorGate`).
/// Unlike a sheet it can be dragged. `isPresented` opens and closes it; the
/// content closes itself by flipping the binding it was handed.
struct CenteredDialog<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder let content: () -> Content

    /// Where the dialog goes: the exact middle of `screen` — its visible
    /// frame, so the menu bar and the Dock are out of the reckoning.
    nonisolated static func frame(size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(
            x: (screen.midX - size.width / 2).rounded(),
            y: (screen.midY - size.height / 2).rounded(),
            width: size.width, height: size.height
        )
    }

    func makeCoordinator() -> Presenter { Presenter() }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let presenter = context.coordinator
        presenter.wanted = isPresented
        guard isPresented != (presenter.window != nil) else { return }
        // Deferred: opening or closing a window from inside SwiftUI's update
        // is re-entrant, and on the first pass the anchor has no window yet
        // to say which screen the log is on.
        let content = content()
        let title = title
        DispatchQueue.main.async {
            presenter.sync(content: content, title: title, screen: view.window?.screen)
        }
    }

    /// The window and its modal session. Made once per anchor; the window
    /// is made on open and let go on close.
    @MainActor
    final class Presenter {
        var wanted = false
        private(set) var window: NSWindow?
        private var running = false

        /// Open or close, whichever `wanted` asks for and is not yet so.
        func sync<V: View>(content: V, title: String, screen: NSScreen?) {
            if wanted, window == nil {
                let screenFrame = (screen ?? NSScreen.main)?.visibleFrame
                    ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
                let window = Self.makeWindow(content: content, title: title, on: screenFrame)
                self.window = window
                window.makeKeyAndOrderFront(nil)
                running = true
                NSApp.runModal(for: window)
                running = false
            } else if !wanted, let window {
                if running { NSApp.stopModal() }
                window.orderOut(nil)
                self.window = nil
            }
        }

        /// The window: sheet-like — no title bar to see, no buttons, not
        /// resizable, draggable by its background — sized to its content
        /// and centred on `screen`.
        static func makeWindow<V: View>(content: V, title: String, on screen: CGRect) -> NSWindow {
            let hosting = NSHostingController(rootView: content)
            let size = hosting.sizeThatFits(in: .zero)
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.title = title
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.setContentSize(size)
            window.setFrame(CenteredDialog.frame(size: window.frame.size, in: screen), display: false)
            return window
        }
    }
}
