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
/// Run:  empty call → F1 (CQ); cursor in the call field → F2 (their call and
///       report); otherwise a valid exchange logs and sends F3 (TU).
/// S&P:  cursor in the call field → F1 (my call); otherwise a valid exchange
///       logs and sends F2 (my report).
enum ESM {

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
        exchangeValid: Bool,
        cursorInCall: Bool
    ) -> Action {
        switch mode {
        case .run:
            if callEmpty { return .sendMessage(index: 0) }
            if cursorInCall || !exchangeValid { return .sendMessage(index: 1) }
            return .logAndSend(index: 2)
        case .searchPounce:
            if callEmpty || cursorInCall || !exchangeValid { return .sendMessage(index: 0) }
            return .logAndSend(index: 1)
        }
    }
}
