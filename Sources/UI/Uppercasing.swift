import AppKit
import SwiftUI

/// A text field that holds upper case: the callsigns, counties, names, grids
/// and park references that go into a log in capitals.
///
/// Folding has two halves, and this is the only place that applies both — which
/// is why each half below is private to this file. Building one of these fields
/// is the only way to get either.
///
/// - **The keystroke**, folded before the field editor ever sees it, so what
///   AppKit holds is already what will be logged.
/// - **The value**, folded on its way through the binding, for text that arrives
///   some other way: a paste, a drag, an auto-fill.
///
/// Folding only the value is what put the caret at the end of the field on
/// 2026-08-08. The field editor held `k5cw` while the model held `K5CW`, and the
/// next render — there is one on every keystroke, since the super check strip
/// and the dupe warning both read the call — pushed the model's text back into
/// the editor. Replacing a field editor's text drops the insertion point at the
/// end of it, so typing at the head of a call placed the first character
/// correctly and appended every one after it: `KE5CW` came out `K5CWE`.
///
/// Pinned by `UppercasingFieldCaretTests`, which types at a real field.
@MainActor
func uppercasingTextField(_ label: String, text: Binding<String>) -> some View {
    TextField(label, text: text.uppercasing)
        .uppercasingKeystrokes()
}

/// Which keystrokes are folded, and to what.
///
/// The plumbing around it is not unit-testable — an `NSEvent` built in a test
/// never reaches a SwiftUI key handler unless the whole window is real — so the
/// decision is a pure function here, the way `KeyMonitorGate` splits the same
/// problem.
enum UppercasingInput {

    /// What this keystroke should insert instead of itself, or nil to let the
    /// field editor handle the key exactly as it always has.
    ///
    /// Everything that is not lower-case text falls through untouched, and it
    /// falls through by construction rather than by a list of exceptions:
    /// digits, `/`, `-`, Return, Tab, Escape, Delete, the arrows and the
    /// function keys all upper-case to themselves. So does anything typed with
    /// ⇧ or Caps Lock already down.
    static func replacement(for characters: String, modifiers: EventModifiers) -> String? {
        // A chord is a command, not text: ⌘V pastes, ⌥ composes a dead key,
        // ⌃A goes to the start of the line. None of them are ours to rewrite.
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let folded = characters.uppercased()
        return folded == characters ? nil : folded
    }
}

private extension Binding where Value == String {
    /// Folds to upper case on the way in, so a field shows what will actually
    /// be logged.
    ///
    /// `.textCase(.uppercase)` only restyles what is drawn — the bound string
    /// keeps whatever case was typed, and the row disagrees with the log until
    /// export normalises it.
    var uppercasing: Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { typed in
                let folded = typed.uppercased()
                // Only write on a real change: assigning an identical string
                // would still publish, and every publish costs a render.
                if wrappedValue != folded { wrappedValue = folded }
            }
        )
    }
}

private extension View {
    func uppercasingKeystrokes() -> some View {
        modifier(UppercasingKeystrokes())
    }
}

/// Folds a typed character before the field editor inserts it.
///
/// Inserting through the editor rather than through the binding is the whole
/// point: the editor places the caret after what it inserted, and because the
/// text it now holds is already folded, nothing is left for a later render to
/// push back.
private struct UppercasingKeystrokes: ViewModifier {
    @Environment(\.fieldEditorWindow) private var fieldEditorWindow

    func body(content: Content) -> some View {
        content.onKeyPress(phases: [.down, .repeat]) { press in
            guard let folded = UppercasingInput.replacement(
                for: press.characters,
                modifiers: press.modifiers
            ),
                let editor = (fieldEditorWindow ?? NSApp.keyWindow)?
                    .firstResponder as? NSTextView,
                // Mid-composition, the marked text is the input method's to
                // finish. It hands over a committed string, which the binding
                // folds.
                !editor.hasMarkedText()
            else { return .ignored }
            editor.insertText(folded, replacementRange: editor.selectedRange())
            return .handled
        }
    }
}

extension EnvironmentValues {
    /// The window whose first responder an uppercasing field types into.
    ///
    /// Nil means the key window, which is the whole truth in the app: an
    /// operator can only type into the window that holds the keyboard. The
    /// caret tests set it, because a test host is never the active application
    /// and so never has a key window at all.
    @Entry var fieldEditorWindow: NSWindow?
}
