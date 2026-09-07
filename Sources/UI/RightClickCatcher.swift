import AppKit
import SwiftUI

/// An invisible overlay that turns a right-click — or ⌃-click, the
/// one-button right-click — on the view beneath into `action`, at once, and
/// lets every other event fall through to that view.
///
/// SwiftUI has no right-click gesture of its own; `contextMenu` is the
/// nearest thing, and it puts a menu between the click and the deed. The
/// F-keys wanted the deed: right-click, and the Messages editor is open.
struct RightClickCatcher: NSViewRepresentable {
    let action: @MainActor () -> Void

    /// Which events the overlay takes for itself. Everything else — a left
    /// click above all — belongs to the button underneath.
    nonisolated static func claims(type: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            true
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            modifiers.contains(.control)
        default:
            false
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (@MainActor () -> Void)?

        /// AppKit asks the frontmost view under the pointer first; answering
        /// nil for anything but a right-click hands the event to the view
        /// beneath as if this one were not there.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  RightClickCatcher.claims(type: event.type, modifiers: event.modifierFlags)
            else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                action?()
            } else {
                super.mouseDown(with: event)
            }
        }

        override var acceptsFirstResponder: Bool { false }
    }
}
