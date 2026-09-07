import Foundation

/// One mutation of a log's rows, as `LogDocument` reports it to whoever is
/// listening (`LogDocument.qsoObserver`) — today the RUMlogNG broadcaster.
/// Carries exactly the rows the mutation touched, so a listener never diffs
/// the log. Undo and redo re-enter the same mutations and so report the
/// inverse change through the same seam; opening a document reports
/// nothing, because nothing was done to it.
enum QSOChange: Equatable, Sendable {
    /// One edited row: what it was, and what it is now. The id is the same.
    struct Replacement: Equatable, Sendable {
        let old: QSO
        let new: QSO

        init(old: QSO, new: QSO) {
            self.old = old
            self.new = new
        }
    }

    case added([QSO])
    case removed([QSO])
    case replaced([Replacement])
}
