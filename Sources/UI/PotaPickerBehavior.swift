import Foundation

/// The park picker's keyboard and disclosure rules, independent of SwiftUI.
/// A `body` cannot be asserted on, so the decisions live here and
/// `PotaPickerBehaviorTests` pins them — the split `PartyNotice` uses.
enum PotaPickerBehavior {

    /// What Escape does in the search field.
    enum EscapeAction: Equatable {
        /// There is text: wipe it and close the list in one press.
        case clearAndCollapse
        /// Already empty: just close the list.
        case collapse
    }

    /// What Return does.
    enum SubmitAction: Equatable {
        /// Take the row under the highlight.
        case addHighlighted(Int)
        /// No list to take from, but the field holds a whole reference —
        /// the path for another program's park, a brand-new one, or a
        /// directory that was never downloaded.
        case addTyped(String)
        case nothing
    }

    /// Whether the list below the field is open at all.
    ///
    /// An empty field with the cursor in it offers the nearest parks; an
    /// empty field the operator has left shows nothing, so the section
    /// collapses back to a couple of rows instead of holding a screenful of
    /// results nobody asked for.
    static func showsResults(query: String, focused: Bool) -> Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || focused
    }

    static func escape(query: String) -> EscapeAction {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? .collapse : .clearAndCollapse
    }

    /// Move the highlight, clamped to the list. Also the way a stale
    /// highlight is pulled back into range after typing narrows the results
    /// — call it with `by: 0`.
    static func move(highlighted: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(highlighted + delta, 0), count - 1)
    }

    static func submit(query: String, highlighted: Int, offeredCount: Int) -> SubmitAction {
        if offeredCount > 0, (0..<offeredCount).contains(highlighted) {
            return .addHighlighted(highlighted)
        }
        if let reference = PotaRef.normalize(query) {
            return .addTyped(reference)
        }
        return .nothing
    }
}
