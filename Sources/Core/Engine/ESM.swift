import Foundation

/// Enter-Sends-Message: what Return should do for the contact in progress.
/// Message indexes are 0-based F-key slots into the active mode's set.
///
/// **The call field never logs.** While the cursor is in it, Return only ever
/// calls — your call in S&P, their call and report in Run — however complete
/// the row looks. Logging happens once the cursor has moved off it and the
/// exchange is valid.
///
/// That rule is what a prefilled exchange needs. Hunting a station whose
/// county you already copied from someone else, the row holds a call and a
/// valid exchange before you have made contact at all, and it goes on holding
/// them while he works three other people. Every one of those Returns has to
/// keep calling. Nothing about the *contents* of the row distinguishes that
/// from a completed QSO — only where the operator is looking does.
///
/// Sitting in the exchange field with something that matches no county is its
/// own case: you are copying him and did not get it, so Return asks him to
/// repeat (F5, AGN?) rather than calling a station already talking to you.
///
/// Run:  empty call → F1 (CQ); cursor in the call field → F2 (their call and
///       report); cursor in the exchange with an unmatched one → F5 (AGN?);
///       otherwise a valid exchange logs and sends F3 (TU).
/// S&P:  cursor in the call field → F1 (my call); cursor in the exchange with
///       an unmatched one → F5 (AGN?); otherwise a valid exchange logs and
///       sends F2 (my report).
enum ESM {

    /// Where the operator is looking, which is what separates "still trying to
    /// raise him" from "I have him and am copying".
    enum Cursor: Equatable {
        case call
        case exchange
        /// Signal reports, QSO numbers — anything that is neither.
        case other
    }

    /// What the exchange field holds. `unmatched` is text that matches no
    /// county, state or prefix; `empty` is nothing typed yet, which is not the
    /// same thing and does not ask him to repeat.
    enum ExchangeState: Equatable {
        case empty
        case unmatched
        case valid
    }

    /// F5 in both default sets. Kept here so the one place that decides also
    /// names the slot.
    static let againIndex = 4

    enum Action: Equatable {
        case sendMessage(index: Int)
        case logAndSend(index: Int)
        case none

        /// The F-key slot this action keys, so the messages row can show what
        /// Return will send next. Nil only when Return would just log.
        var messageIndex: Int? {
            switch self {
            case .sendMessage(let index), .logAndSend(let index): index
            case .none: nil
            }
        }
    }

    static func nextAction(
        mode: OperatingMode,
        callEmpty: Bool,
        exchange: ExchangeState,
        cursor: Cursor
    ) -> Action {
        // No callsign is no contact: there is nobody to report to or ask.
        if callEmpty { return .sendMessage(index: 0) }

        if cursor == .exchange, exchange == .unmatched {
            return .sendMessage(index: againIndex)
        }

        // The call field only ever calls, and nothing logs until the exchange
        // actually matches something.
        let stillCalling = cursor == .call || exchange != .valid

        switch mode {
        case .run:
            return stillCalling ? .sendMessage(index: 1) : .logAndSend(index: 2)
        case .searchPounce:
            return stillCalling ? .sendMessage(index: 0) : .logAndSend(index: 1)
        }
    }
}
